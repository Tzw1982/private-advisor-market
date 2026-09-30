/// 校验 packages-src/ 下所有专家包。
///
/// 用法：`dart run scripts/validate.dart`
/// CI 会在每个 PR 上运行；失败则阻断合并。
library;

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

  if (dirs.isEmpty) {
    stderr.writeln('packages-src/ 下没有包');
    exit(1);
  }

  stdout.writeln('校验 ${dirs.length} 个专家包…\n');

  var failed = 0;
  var warned = 0;

  for (final dir in dirs) {
    final result = validatePackage(dir);
    stdout.write(result.report(dir.path.replaceAll('\\', '/').split('/').last));
    if (!result.ok) failed++;
    if (result.warnings.isNotEmpty) warned++;
  }

  stdout.writeln('\n${'-' * 50}');
  stdout.writeln('合计 ${dirs.length} 个包：失败 $failed，含警告 $warned');

  if (failed > 0) {
    stdout.writeln('校验未通过 ✗');
    exit(1);
  }
  stdout.writeln('全部通过 ✅');
}
