import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Core Domain Architecture Purity Tests', () {
    test(
        'Ensures all files in lib/ contain zero package:flutter imports',
        () {
      final domainDir = Directory('lib');
      expect(domainDir.existsSync(), isTrue, reason: 'lib/ must exist');

      final dartFiles = domainDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ') && line.contains('package:flutter/')) {
            violations.add('${file.path}:${i + 1} -> $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'lib/ MUST NOT import package:flutter/... '
            'Violations found:\n${violations.join('\n')}',
      );
    });
  });
}
