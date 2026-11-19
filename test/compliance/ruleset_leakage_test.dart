@TestOn('vm')
library;

import 'dart:io';
import 'package:test/test.dart';

/// Lexical compliance audit for ruleset neutrality.
///
/// Note: This test performs lexical scanning for specific banned tokens to prevent
/// obvious terminology leaks. It does not prove semantic neutrality, which is an
/// architectural invariant governed by ownership principles and structural tests
/// (see `ruleset_genericity_compliance_test.dart` and `AGENTS.md`).

/// Strips Dart comments while preserving line breaks so line numbers stay exact.
String _stripCommentsPreservingLines(String source) {
  final out = StringBuffer();
  final len = source.length;
  var i = 0;
  while (i < len) {
    final c = source[i];
    final next = i + 1 < len ? source[i + 1] : '';
    // Keep strings verbatim so comment tokens inside strings aren't stripped.
    if (c == 'r' && (next == "'" || next == '"')) {
      final quote = next;
      final isTriple = i + 3 < len && source[i + 2] == quote && source[i + 3] == quote;
      final start = i;
      i += isTriple ? 4 : 2;
      while (i < len) {
        if (isTriple) {
          if (i + 2 < len && source[i] == quote && source[i + 1] == quote && source[i + 2] == quote) {
            i += 3;
            break;
          }
        } else if (source[i] == quote) {
          i++;
          break;
        }
        i++;
      }
      out.write(source.substring(start, i));
      continue;
    }
    if (c == "'" || c == '"') {
      final quote = c;
      final isTriple = i + 2 < len && source[i + 1] == quote && source[i + 2] == quote;
      final start = i;
      i += isTriple ? 3 : 1;
      while (i < len) {
        if (source[i] == '\\') {
          i += 2;
          continue;
        }
        if (isTriple) {
          if (i + 2 < len && source[i] == quote && source[i + 1] == quote && source[i + 2] == quote) {
            i += 3;
            break;
          }
        } else if (source[i] == quote) {
          i++;
          break;
        }
        i++;
      }
      out.write(source.substring(start, i));
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < len && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < len && depth > 0) {
        if (source[i] == '/' && i + 1 < len && source[i + 1] == '*') {
          depth++;
          i += 2;
        } else if (source[i] == '*' && i + 1 < len && source[i + 1] == '/') {
          depth--;
          i += 2;
        } else {
          if (source[i] == '\n') out.write('\n');
          i++;
        }
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Splits camelCase, PascalCase, snake_case, and non-alphanumeric separators
/// into lower-case words.
List<String> splitIdentifierOrStringWords(String token) {
  final withSpaces = token
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');
  return withSpaces
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

const Set<String> _bannedSingleWords = {
  // Existing test banned single-word terms
  'dnd',
  '5e',
  'srd5',
  'strength',
  'dexterity',
  'constitution',
  'wisdom',
  'charisma',
  // Fix 8.4 additions
  'species',
  'background',
  'proficiency',
  'proficiencies',
  'proficient',
  'expertise',
  'saving',
  'cantrip',
  'cantrips',
  'spell',
  'spells',
  'warlock',
  'pact',
  'attunement',
  'subclass',
  'alignment',
  'd20',
};

const Set<String> _bannedWordPairs = {
  'armor class',
  'target ac',
  'challenge rating',
  'spell slot',
  'weapon mastery',
  'bonus action',
  'short rest',
  'long rest',
};

List<String> scanCoreWordBar(String relativePath, String source) {
  final cleaned = _stripCommentsPreservingLines(source);
  final violations = <String>[];
  final tokenRe = RegExp(
    r'''r?"""[\s\S]*?"""|r?\x27\x27\x27[\s\S]*?\x27\x27\x27|r?"(?:\\.|[^"\\\n])*"|r?\x27(?:\\.|[^\x27\\\n])*\x27|[A-Za-z_][A-Za-z0-9_]*''',
  );

  for (final m in tokenRe.allMatches(cleaned)) {
    final token = m.group(0)!;
    final lineNum = '\n'.allMatches(cleaned.substring(0, m.start)).length + 1;
    final words = splitIdentifierOrStringWords(token);
    for (final w in words) {
      if (_bannedSingleWords.contains(w)) {
        violations.add('$relativePath:$lineNum: $w in $token');
      }
    }
    for (var i = 0; i + 1 < words.length; i++) {
      final pair = '${words[i]} ${words[i + 1]}';
      if (_bannedWordPairs.contains(pair)) {
        violations.add('$relativePath:$lineNum: $pair in $token');
      }
    }
  }
  return violations;
}

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

    test('Fix 8.4 controls: word bar splits identifiers and strings and ignores comments', () {
      expect(
        scanCoreWordBar('lib/a.dart', 'final int? zzSpellSaveDc;'),
        ['lib/a.dart:1: spell in zzSpellSaveDc'],
      );
      expect(
        scanCoreWordBar('lib/a.dart', "const k = 'savingThrowProficiencies';"),
        containsAll([
          "lib/a.dart:1: saving in 'savingThrowProficiencies'",
          "lib/a.dart:1: proficiencies in 'savingThrowProficiencies'",
        ]),
      );
      expect(
        scanCoreWordBar('lib/a.dart', 'int armorClass = 10; int targetAc = 12;'),
        [
          'lib/a.dart:1: armor class in armorClass',
          'lib/a.dart:1: target ac in targetAc',
        ],
      );
      expect(
        scanCoreWordBar(
          'lib/a.dart',
          'final hitPoints = 1; final initiativeScore = 2; final effectiveAbilityScores = 3; final feats = 4;',
        ),
        isEmpty,
      );
      expect(
        scanCoreWordBar(
          'lib/a.dart',
          '// species background spellSlot armorClass d20\n/* savingThrowProficiencies */\nfinal ok = 1;',
        ),
        isEmpty,
      );
    });

    test('Fix 8.4: Core lib/ identifiers and strings contain zero banned ruleset words or pairs', () {
      const allowedFiles = <String>{};
      expect(allowedFiles, isEmpty);

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final violations = <String>[];
      for (final file in dartFiles) {
        final rel = file.path.replaceAll('\\', '/');
        violations.addAll(scanCoreWordBar(rel, file.readAsStringSync()));
      }

      expect(
        violations,
        isEmpty,
        reason: 'Core word bar violations found:\n${violations.join('\n')}',
      );
    });
  });
}
