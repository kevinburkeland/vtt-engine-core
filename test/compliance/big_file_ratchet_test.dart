@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

const int kMaxAllowedLines = 1500;

/// Core has an empty big-file allowlist: no `.dart` file under `lib/` may
/// exceed [kMaxAllowedLines] lines.
const Map<String, int> kCoreBigFileAllowlist = <String, int>{};

List<String> evaluateBigFileRatchet({
  required Map<String, int> actualLineCounts,
  required Map<String, int> allowlist,
  int limit = kMaxAllowedLines,
}) {
  final problems = <String>[];
  final sortedActual = actualLineCounts.keys.toList()..sort();

  for (final path in sortedActual) {
    final lines = actualLineCounts[path]!;
    final ceiling = allowlist[path];
    if (ceiling == null) {
      if (lines > limit) {
        problems.add(
          '$path has $lines lines (limit $limit, not on allowlist)',
        );
      }
    } else {
      if (lines > ceiling) {
        problems.add(
          '$path grew to $lines lines (allowlist ceiling $ceiling)',
        );
      } else if (lines <= limit) {
        problems.add(
          '$path shrank to $lines lines (<= $limit); remove it from the allowlist',
        );
      } else if (lines < ceiling) {
        problems.add(
          '$path shrank to $lines lines (allowlist ceiling $ceiling); lower its ceiling',
        );
      }
    }
  }

  final sortedAllowlist = allowlist.keys.toList()..sort();
  for (final path in sortedAllowlist) {
    if (!actualLineCounts.containsKey(path)) {
      problems.add('$path is on the allowlist but does not exist');
    }
  }

  return problems;
}

Map<String, int> _collectLibLineCounts() {
  final counts = <String, int>{};
  final libDir = Directory('lib');
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final path = entity.path.replaceAll('\\', '/');
      final content = entity.readAsStringSync();
      final lines = content.isEmpty ? 0 : '\n'.allMatches(content).length + (content.endsWith('\n') ? 0 : 1);
      counts[path] = lines;
    }
  }
  return counts;
}

void main() {
  group('Fix 7.3: Core Big-File Ratchet Controls (in-memory)', () {
    test('control: 1501 lines not on allowlist fails naming file and 1501', () {
      final problems = evaluateBigFileRatchet(
        actualLineCounts: {'lib/oversized.dart': 1501},
        allowlist: const {},
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('lib/oversized.dart'));
      expect(problems.single, contains('1501'));
    });

    test('control: 1500 lines not on allowlist passes', () {
      final problems = evaluateBigFileRatchet(
        actualLineCounts: {'lib/exact.dart': 1500},
        allowlist: const {},
      );
      expect(problems, isEmpty);
    });
  });

  group('Fix 7.3: Core Big-File Ratchet on live lib/ tree', () {
    test('allowlist is empty', () {
      expect(kCoreBigFileAllowlist, isEmpty);
    });

    test('no lib/ .dart file exceeds $kMaxAllowedLines lines', () {
      final counts = _collectLibLineCounts();
      final problems = evaluateBigFileRatchet(
        actualLineCounts: counts,
        allowlist: kCoreBigFileAllowlist,
      );
      expect(
        problems,
        isEmpty,
        reason: 'Big-file ratchet violations:\n${problems.join('\n')}',
      );
    });
  });
}
