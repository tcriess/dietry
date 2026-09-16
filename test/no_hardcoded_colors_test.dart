import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A colour literal outside the palette has no dark-mode value, so it ends up
/// unreadable in one of the two modes.
void main() {
  test('no hardcoded colours outside the palette', () {
    const allowedFiles = {
      'lib/theme/app_colors.dart',
    };
    final allowedLine = RegExp(r'seedColor:|Colors\.transparent');
    // The lookbehind spares `AppColors.light`, the palette wiring itself.
    final literal = RegExp(r'(?<![\w.])Colors\.[a-z]\w*|Color\(0x');

    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path;
      if (allowedFiles.contains(path)) continue;
      if (path.startsWith('lib/l10n/')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (allowedLine.hasMatch(line)) continue;
        if (literal.hasMatch(line)) {
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Use context.colors instead:\n${offenders.join('\n')}');
  });
}
