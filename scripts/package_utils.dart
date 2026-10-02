/// 市场包校验与索引构建的共享逻辑。
///
/// 与客户端 `PackageVerifier`（advisor_core/lib/domain/market.dart）保持**同一套口径**，
/// 任一侧改动必须同步，否则会出现"CI 通过但客户端拒绝安装"。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 单文件上限 5MB，整包上限 20MB。
const int maxFileBytes = 5 * 1024 * 1024;
const int maxPackageBytes = 20 * 1024 * 1024;

/// 禁止的可执行扩展名。
const Set<String> forbiddenExtensions = {
  '.exe', '.dll', '.bat', '.cmd', '.ps1', '.sh', '.py', '.js',
  '.jar', '.msi', '.scr', '.com', '.vbs', '.so', '.dylib', '.app',
};

/// 允许出现在包内的文件扩展名（白名单，比黑名单更安全）。
const Set<String> allowedExtensions = {'.json', '.md', '.png', '.jpg', '.jpeg', '.txt'};

const Set<String> allowedCategories = {
  '01-ProductDesign', '02-Engineering', '03-GameSpatial', '04-DataAI',
  '05-MarketingGrowth', '06-ContentCreative', '07-SalesCommerce',
  '08-FinanceInvestment', '09-OperationsHR', '10-ProjectQuality',
  '11-SecurityCompliance', '12-IndustryConsultant', '13-TencentZone',
  '14-WorldWise', '15-Education',
};

String sha256Bytes(List<int> bytes) => sha256.convert(bytes).toString();

/// 包整体哈希：按契约 04 §4，`path + "\0" + sha256 + "\n"` 拼接后取 sha256。
String computePackageHash(List<({String path, String sha256})> files) {
  final sorted = List<({String path, String sha256})>.from(files)
    ..sort((a, b) => a.path.compareTo(b.path));
  final buf = StringBuffer();
  for (final f in sorted) {
    buf.write(f.path);
    buf.write('\u0000');
    buf.write(f.sha256);
    buf.write('\n');
  }
  return sha256Bytes(utf8.encode(buf.toString()));
}

/// 校验结果。
class ValidationResult {
  final List<String> errors = [];
  final List<String> warnings = [];

  bool get ok => errors.isEmpty;

  String report(String slug) {
    final b = StringBuffer();
    if (ok) {
      b.writeln('  ✓ $slug');
      for (final w in warnings) {
        b.writeln('    ! $w');
      }
    } else {
      b.writeln('  ✗ $slug');
      for (final e in errors) {
        b.writeln('    - $e');
      }
    }
    return b.toString();
  }
}

/// 收集包目录内所有文件（相对路径）。
List<File> listPackageFiles(Directory dir) {
  final out = <File>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is File) out.add(e);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String relativePath(Directory root, File f) =>
    f.path.replaceAll('\\', '/').substring(root.path.replaceAll('\\', '/').length + 1);

/// 校验单个包目录。
ValidationResult validatePackage(Directory pkgDir) {
  final r = ValidationResult();
  final slug = pkgDir.path.replaceAll('\\', '/').split('/').last;

  final manifestFile = File('${pkgDir.path}/manifest.json');
  final expertFile = File('${pkgDir.path}/expert.json');
  final readmeFile = File('${pkgDir.path}/README.md');

  if (!manifestFile.existsSync()) {
    r.errors.add('缺少 manifest.json');
    return r;
  }
  if (!expertFile.existsSync()) r.errors.add('缺少 expert.json');
  if (!readmeFile.existsSync()) r.warnings.add('建议提供 README.md');

  Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    r.errors.add('manifest.json 解析失败：$e');
    return r;
  }

  // 必填字段
  for (final k in [
    'schemaVersion', 'packageId', 'slug', 'version', 'appVersion',
    'displayName', 'categoryId', 'entry', 'sha256', 'capabilities', 'files',
  ]) {
    if (manifest[k] == null) r.errors.add('manifest 缺少字段 $k');
  }
  if (r.errors.isNotEmpty) return r;

  if (manifest['schemaVersion'] != 1) r.errors.add('schemaVersion 必须为 1');
  if (manifest['slug'] != slug) {
    r.errors.add('slug(${manifest['slug']}) 与目录名($slug) 不一致');
  }
  if (!RegExp(r'^[a-z0-9]+(\.[a-z0-9][a-z0-9-]*)+$').hasMatch('${manifest['packageId']}')) {
    r.errors.add('packageId 需为反向域名：${manifest['packageId']}');
  }
  if (!RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$').hasMatch('${manifest['version']}')) {
    r.errors.add('version 非语义化版本：${manifest['version']}');
  }
  if (!allowedCategories.contains(manifest['categoryId'])) {
    r.errors.add('categoryId 不在 15 类之内：${manifest['categoryId']}');
  }

  // 能力必须全部 false
  final caps = manifest['capabilities'];
  if (caps is! Map) {
    r.errors.add('capabilities 必须是对象');
  } else {
    for (final k in ['network', 'filesystem', 'shell', 'tools']) {
      if (caps[k] != false) r.errors.add('capabilities.$k 必须为 false');
    }
  }

  // 逐文件校验
  final declared = <String, String>{};
  final filesJson = manifest['files'];
  if (filesJson is! List || filesJson.isEmpty) {
    r.errors.add('files 必须是非空数组');
  } else {
    for (final e in filesJson) {
      if (e is! Map) {
        r.errors.add('files 项必须是对象');
        continue;
      }
      declared['${e['path']}'] = '${e['sha256']}';
    }
  }

  final actualFiles = listPackageFiles(pkgDir)
      .where((f) => relativePath(pkgDir, f) != 'manifest.json')
      .toList();

  final actualHashes = <({String path, String sha256})>[];
  var totalBytes = 0;

  for (final f in actualFiles) {
    final rel = relativePath(pkgDir, f);
    final bytes = f.readAsBytesSync();
    totalBytes += bytes.length;

    if (bytes.length > maxFileBytes) r.errors.add('$rel 超过 5MB');

    final ext = rel.contains('.') ? '.${rel.split('.').last.toLowerCase()}' : '';
    if (forbiddenExtensions.contains(ext)) {
      r.errors.add('$rel 是可执行文件，禁止打包');
    } else if (!allowedExtensions.contains(ext)) {
      r.warnings.add('$rel 扩展名不在白名单（$allowedExtensions）');
    }

    final h = sha256Bytes(bytes);
    actualHashes.add((path: rel, sha256: h));

    if (!declared.containsKey(rel)) {
      r.errors.add('$rel 未在 manifest.files 中声明');
    } else if (declared[rel] != h) {
      r.errors.add('$rel 哈希不符（manifest=${declared[rel]} actual=$h）');
    }
  }

  for (final d in declared.keys) {
    if (!actualHashes.any((a) => a.path == d)) {
      r.errors.add('manifest 声明的 $d 实际不存在');
    }
  }

  if (totalBytes > maxPackageBytes) r.errors.add('整包超过 20MB');

  // 整体哈希
  final expected = computePackageHash(actualHashes);
  if (expected != manifest['sha256']) {
    r.errors.add('整包 sha256 不符（manifest=${manifest['sha256']} actual=$expected）');
  }

  // entry 存在
  final entry = '${manifest['entry']}';
  if (!actualHashes.any((a) => a.path == entry)) {
    r.errors.add('entry 指向的文件不存在：$entry');
  }

  // 头像规格
  final avatar = actualFiles.firstWhere(
    (f) => relativePath(pkgDir, f).startsWith('avatars/'),
    orElse: () => File(''),
  );
  if (avatar.path.isEmpty) {
    r.warnings.add('建议提供 avatars/expert.png（512×512，≤500KB）');
  } else if (avatar.lengthSync() > 500 * 1024) {
    r.errors.add('头像超过 500KB');
  }

  // expert.json 内容
  if (expertFile.existsSync()) {
    try {
      final ej = jsonDecode(expertFile.readAsStringSync()) as Map<String, dynamic>;
      for (final k in ['displayName', 'profession', 'description']) {
        if (ej[k] == null || '${ej[k]}'.trim().isEmpty) {
          r.errors.add('expert.json 缺少 $k');
        }
      }
      final desc = '${ej['description'] ?? ''}';
      if (desc.isNotEmpty && (desc.length < 20 || desc.length > 80)) {
        r.warnings.add('description 建议 40–50 字（当前 ${desc.length} 字）');
      }
      final tags = ej['tags'];
      if (tags is List && tags.length > 6) r.errors.add('tags 最多 6 个');
    } catch (e) {
      r.errors.add('expert.json 解析失败：$e');
    }
  }

  return r;
}

/// 生成索引条目。
Map<String, dynamic> buildIndexEntry(Directory pkgDir, {String? releaseBaseUrl}) {
  final manifest =
      jsonDecode(File('${pkgDir.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final expert =
      jsonDecode(File('${pkgDir.path}/expert.json').readAsStringSync()) as Map<String, dynamic>;

  final slug = manifest['slug'];
  final version = manifest['version'];
  final base = releaseBaseUrl ?? 'https://github.com/TZW1982/private-advisor-market/releases/download';

  return {
    'packageId': manifest['packageId'],
    'slug': slug,
    'displayName': manifest['displayName'],
    'profession': expert['profession'],
    'description': expert['description'],
    'categoryId': manifest['categoryId'],
    'tags': expert['tags'] ?? [],
    // 第 7 轮 T06（emoji 方案）：把包内 expert.json 的 emoji / color 透传进索引。
    // **纯 additive**：仅当非空才写；`schemaVersion` 保持 1——客户端
    // `MarketPackage.fromJson` 逐字段取值、忽略未知字段 → 旧客户端读到这两个
    // 新字段会忽略、行为不变；新客户端读旧索引则两字段缺失 → 走回退档。
    // 红线：绝不允许借此改动 `packages-src/**` 内任何已有包（改则 sha256 不符 → 包被剔除）。
    if ('${expert['emoji'] ?? ''}'.trim().isNotEmpty) 'emoji': expert['emoji'],
    if ('${expert['color'] ?? ''}'.trim().isNotEmpty) 'color': expert['color'],
    'latestVersion': version,
    'versions': [
      {
        'version': version,
        'releaseUrl': '$base/$slug/$slug-$version.expert',
        'sha256': manifest['sha256'],
        if (manifest['signature'] != null) 'signature': manifest['signature'],
        'publishedAt': manifest['publishedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      }
    ],
  };
}

/// 计算包目录的 zip 载荷（用于本地打包/自检，不产生真实 zip）。
Uint8List readBytes(String path) => File(path).readAsBytesSync();
