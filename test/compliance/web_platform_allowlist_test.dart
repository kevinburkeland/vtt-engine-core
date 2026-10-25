@TestOn("vm")
library;

import "dart:io";
import "package:test/test.dart";

List<String> findSelectors(String source) {
  final pattern = RegExp(
    r"@Test" r"On\s*\([^)]*\)|"
    r"@On" r"Platform\s*\([^)]*\)|"
    r"@" r"Skip\s*\([^)]*\)|"
    r"@" r"Tags\s*\([^)]*\)|"
    r"(?<!@)\btest" r"On:\s*[^,\n)]*|"
    r"(?<!@)\bon" r"Platform:[^,\n)]*|"
    r"(?<!@)\bskip:[^,\n)]*|"
    r"(?<!@)\btags:[^,\n)]*",
  );
  return pattern.allMatches(source).map((m) => m.group(0)!).toList();
}

bool isVmMarker(String marker) {
  final trimmed = marker.trim();
  final testOnAnnotationPattern =
      RegExp(r"^@Test" r"On\s*\(\s*[\x27\x22]vm[\x27\x22]\s*\)$");
  final testOnArgPattern =
      RegExp(r"^test" r"On:\s*[\x27\x22]vm[\x27\x22]$");
  return testOnAnnotationPattern.hasMatch(trimmed) ||
      testOnArgPattern.hasMatch(trimmed);
}

void main() {
  group("Web Platform Allowlist Tests", () {
    test("verifies exact allowlist of VM-only test markers", () {
      // Control check: in-memory string holding one of each of the 8 selector kinds
      const controlString =
          "@Test" "On(\x27vm\x27)\n"
          "test" "On: \x27vm\x27\n"
          "on" "Platform: {}\n"
          "skip" ": \x27reason\x27\n"
          "@" "Skip(\x27reason\x27)\n"
          "@On" "Platform({})\n"
          "@" "Tags([\x27tag\x27])\n"
          "tags" ": [\x27tag\x27]\n";
      final controlMatches = findSelectors(controlString);
      expect(
        controlMatches.length,
        equals(8),
        reason: "Control check failed: counter must detect 8 markers in control string",
      );

      // Check 2: dart_test.yaml must not exist anywhere in the repository
      final repoRoot = Directory.current;
      final dartTestYamlFiles = repoRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) {
            final segments = f.uri.pathSegments.where((s) => s.isNotEmpty).toList();
            return segments.isNotEmpty && segments.last == "dart_test.yaml";
          })
          .toList();
      expect(
        dartTestYamlFiles,
        isEmpty,
        reason: "dart_test.yaml must not exist: ${dartTestYamlFiles.map((f) => f.path).join(", ")}",
      );

      const expectedCounts = <String, int>{
        "test/compliance/domain_purity_test.dart": 1,
        "test/compliance/licensing_and_dco_test.dart": 1,
        "test/compliance/ruleset_genericity_compliance_test.dart": 1,
        "test/compliance/ruleset_leakage_test.dart": 1,
        "test/compliance/web_platform_allowlist_test.dart": 1,
        "test/models/blob_ref_test.dart": 1,
        "test/models/campaign_profile_edition_type_test.dart": 1,
        "test/models/legacy_entity_links_migration_test.dart": 9,
        "test/simulation/dpr_simulator_test.dart": 2,
      };

      final testDir = Directory("test");
      expect(testDir.existsSync(), isTrue, reason: "test/ must exist");

      final dartFiles = testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(".dart"))
          .toList();

      final actualCounts = <String, int>{};
      final nonVmMarkers = <String>[];

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll(r"\\", "/");
        final relativePath = normalizedPath.startsWith("./")
            ? normalizedPath.substring(2)
            : normalizedPath;
        final content = file.readAsStringSync();
        final selectors = findSelectors(content);
        if (selectors.isNotEmpty) {
          actualCounts[relativePath] = selectors.length;
          for (final marker in selectors) {
            if (!isVmMarker(marker)) {
              nonVmMarkers.add("$relativePath: non-vm marker \"$marker\"");
            }
          }
        }
      }

      final failures = <String>[];

      if (nonVmMarkers.isNotEmpty) {
        failures.addAll(nonVmMarkers);
      }

      for (final entry in expectedCounts.entries) {
        final filePath = entry.key;
        final expectedCount = entry.value;
        final actualCount = actualCounts[filePath] ?? 0;
        if (actualCount != expectedCount) {
          failures.add(
            "$filePath marker count mismatch: actual $actualCount, expected $expectedCount",
          );
        }
      }

      for (final entry in actualCounts.entries) {
        final filePath = entry.key;
        final actualCount = entry.value;
        if (!expectedCounts.containsKey(filePath)) {
          failures.add(
            "$filePath marker count mismatch: actual $actualCount, expected 0",
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join("\n"));
    });
  });
}
