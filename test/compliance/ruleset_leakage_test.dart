import 'dart:io';
import 'package:test/test.dart';

/// Lexical compliance audit for ruleset neutrality.
///
/// Note: This test performs lexical scanning for specific banned tokens to prevent
/// obvious terminology leaks. It does not prove semantic neutrality, which is an
/// architectural invariant governed by ownership principles and structural tests
/// (see `ruleset_genericity_compliance_test.dart` and `AGENTS.md`).

void main() {
  group('Ruleset Neutrality & Leakage Tests', () {
    test(
        'Ensures production files in lib/ contain zero obvious 5E-specific concepts or identifiers',
        () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final bannedPatterns = <String, RegExp>{
        'dnd': RegExp(r'\bdnd\b', caseSensitive: false),
        '5e': RegExp(r'\b5e\b', caseSensitive: false),
        'srd5': RegExp(r'\bsrd5\b', caseSensitive: false),
        'strength': RegExp(r'\bstrength\b', caseSensitive: false),
        'dexterity': RegExp(r'\bdexterity\b', caseSensitive: false),
        'constitution': RegExp(r'\bconstitution\b', caseSensitive: false),
        'wisdom': RegExp(r'\bwisdom\b', caseSensitive: false),
        'charisma': RegExp(r'\bcharisma\b', caseSensitive: false),
        'armorClass': RegExp(r'\barmorclass\b', caseSensitive: false),
        'challengeRating': RegExp(r'\bchallengerating\b', caseSensitive: false),
        'spellSlot': RegExp(r'\bspellslot\b', caseSensitive: false),
        'weaponMastery': RegExp(r'\bweaponmastery\b', caseSensitive: false),
        'bonusAction': RegExp(r'\bbonusaction\b', caseSensitive: false),
        'shortRest': RegExp(r'\bshortrest\b', caseSensitive: false),
        'longRest': RegExp(r'\blongrest\b', caseSensitive: false),
      };

      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          for (final entry in bannedPatterns.entries) {
            if (entry.value.hasMatch(line)) {
              violations.add(
                '${file.path}:${i + 1} [term: ${entry.key}] -> ${line.trim()}',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'lib/ MUST NOT leak 5E/D&D-specific terminology. '
            'Violations found:\n${violations.join('\n')}',
      );
    });
  });
}
