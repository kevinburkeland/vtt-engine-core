@TestOn('vm')
library;

import 'dart:io';
import 'package:test/test.dart';

int countVmMarkers(String source) {
  final pattern = RegExp(
    '@Test' 'On\\([\'"]vm[\'"]\\)|'
    'test' 'On:\\s*[\'"]vm[\'"]',
  );
  return pattern.allMatches(source).length;
}

void main() {
  group('Web Platform Allowlist Tests', () {
    test('verifies exact allowlist of VM-only test markers', () {
      // Control check: in-memory string holding 3 markers
      const controlString =
          '@Test' "On('vm')\n"
          'test' "On: 'vm'\n"
          'test' 'On: "vm"\n';
      expect(
        countVmMarkers(controlString),
        equals(3),
        reason: 'Control check failed: counter must detect 3 markers in control string',
      );

      const expectedCounts = <String, int>{
        'test/compliance/domain_purity_test.dart': 1,
        'test/compliance/licensing_and_dco_test.dart': 1,
        'test/compliance/ruleset_genericity_compliance_test.dart': 1,
        'test/compliance/ruleset_leakage_test.dart': 1,
        'test/compliance/web_platform_allowlist_test.dart': 1,
        'test/models/blob_ref_test.dart': 1,
        'test/models/campaign_profile_edition_type_test.dart': 1,
        'test/models/legacy_entity_links_migration_test.dart': 9,
        'test/simulation/dpr_simulator_test.dart': 2,
      };

      final testDir = Directory('test');
      expect(testDir.existsSync(), isTrue, reason: 'test/ must exist');

      final dartFiles = testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final actualCounts = <String, int>{};
      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll(r'\', '/');
        final relativePath = normalizedPath.startsWith('./')
            ? normalizedPath.substring(2)
            : normalizedPath;
        final content = file.readAsStringSync();
        final count = countVmMarkers(content);
        if (count > 0) {
          actualCounts[relativePath] = count;
        }
      }

      final failures = <String>[];

      for (final entry in expectedCounts.entries) {
        final filePath = entry.key;
        final expectedCount = entry.value;
        final actualCount = actualCounts[filePath] ?? 0;
        if (actualCount != expectedCount) {
          failures.add(
            '$filePath marker count mismatch: actual $actualCount, expected $expectedCount',
          );
        }
      }

      for (final entry in actualCounts.entries) {
        final filePath = entry.key;
        final actualCount = entry.value;
        if (!expectedCounts.containsKey(filePath)) {
          failures.add(
            '$filePath marker count mismatch: actual $actualCount, expected 0',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}
