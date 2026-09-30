/// 为 packages-src/ 下的包回填 manifest.json 的 `files[]` 与整体 `sha256`。
///
/// 用法：`dart run scripts/seal.dart`
///
/// 作者只需维护 manifest 的元数据（packageId / version / displayName / ...），
/// 哈希由本脚本按契约 04 §4 的口径自动计算。
library;

import 'dart:convert';
import 'dart:io';

import 'package_utils.dart';

void main() {
  final root = Directory.current;
  final src = Directory('${root.path}/packages-src');

  if (!src.existsSync()) {
    stderr.writeln('找不到 packages-src/ 目录');
    exit(1);
  }

  final dirs = src.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var sealed = 0;

  for (final dir in dirs) {
    final manifestFile = File('${dir.path}/manifest.json');
    if (!manifestFile.existsSync()) {
      stderr.writeln('跳过（无 manifest.json）：${dir.path}');
      continue;
    }

    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

    final files = listPackageFiles(dir)
        .where((f) => relativePath(dir, f) != 'manifest.json')
        .map((f) => (
              path: relativePath(dir, f),
              sha256: sha256Bytes(f.readAsBytesSync()),
            ))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    manifest['files'] = files.map((f) => {'path': f.path, 'sha256': f.sha256}).toList();
    manifest['sha256'] = computePackageHash(files);
    manifest['publishedAt'] ??= DateTime.now().millisecondsSinceEpoch;

    manifestFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );

    final slug = dir.path.replaceAll('\\', '/').split('/').last;
    stdout.writeln('已封包 $slug：${files.length} 个文件，sha256=${manifest['sha256']}');
    sealed++;
  }

  stdout.writeln('\n完成，共封包 $sealed 个包。');
}
