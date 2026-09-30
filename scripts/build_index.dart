/// 由 packages-src/ 生成 catalog/index.json。
///
/// 用法：`dart run scripts/build_index.dart`
/// CI 在合并到 main 后自动运行并提交产物。
library;

import 'dart:convert';
import 'dart:io';

import 'package_utils.dart';

void main(List<String> args) {
  final root = Directory.current;
  final src = Directory('${root.path}/packages-src');

  if (!src.existsSync()) {
    stderr.writeln('找不到 packages-src/ 目录');
    exit(1);
  }

  final releaseBase = args.isNotEmpty ? args.first : null;

  final dirs = src.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final entries = <Map<String, dynamic>>[];
  for (final dir in dirs) {
    final result = validatePackage(dir);
    if (!result.ok) {
      stderr.writeln('跳过未通过校验的包：${dir.path}');
      continue;
    }
    entries.add(buildIndexEntry(dir, releaseBaseUrl: releaseBase));
  }

  entries.sort((a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'));

  final index = {
    'schemaVersion': 1,
    'generatedAt': DateTime.now().millisecondsSinceEpoch,
    'packages': entries,
  };

  final outDir = Directory('${root.path}/catalog');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final outFile = File('${outDir.path}/index.json');
  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(index),
  );

  stdout.writeln('已生成 ${outFile.path}');
  stdout.writeln('收录 ${entries.length} 个专家包');
}
