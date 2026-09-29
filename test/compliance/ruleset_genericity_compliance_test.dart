import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Ruleset Genericity & Structural Compliance Tests', () {
    final libDir = Directory('lib');

    test('lib/ must exist', () {
      expect(libDir.existsSync(), isTrue);
    });

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('Core must not declare D&D-specific progression types or classes', () {
      final bannedDeclarations = [
        RegExp(r'\bclass\s+ClassLevelProgression\b'),
        RegExp(r'\bclass\s+CharacterProgression\b'),
        RegExp(r'\benum\s+SessionRefType\b'),
        RegExp(r'\bclass\s+MinionInstance\b'),
        RegExp(r'\bclass\s+ArenaCondition\b'),
        RegExp(r'\bclass\s+FeatureGrant\b'),
      ];

      final violations = <String>[];
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final pattern in bannedDeclarations) {
          if (pattern.hasMatch(content)) {
            violations.add('${file.path} matched banned declaration: $pattern');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Core must not declare concrete D&D progression or taxonomy types.\n'
            '${violations.join('\n')}',
      );
    });

    test('Core must not compute proficiency bonus from total level', () {
      // D&D level-to-proficiency formula pattern: ((totalLevel - 1) ~/ 4) + 2
      final pbFormula = RegExp(r'(\btotalLevel\b|\blevel\b)[^;]*~/ 4');
      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pbFormula.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1} -> ${lines[i].trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Core must not compute D&D proficiency bonus from level.\n'
            '${violations.join('\n')}',
      );
    });

    test('Core session and room models must not contain concrete D&D entity taxonomies', () {
      final sessionModelsFile = File('lib/models/session_graph_models.dart');
      expect(sessionModelsFile.existsSync(), isTrue);

      final content = sessionModelsFile.readAsStringSync();
      // Must not contain hardcoded SessionRefType enum with character, monster, npc
      expect(content.contains('enum SessionRefType'), isFalse);
      expect(content.contains('SessionRefType.monster'), isFalse);
      expect(content.contains('SessionRefType.character'), isFalse);
      expect(content.contains('SessionRefType.lootContainer'), isFalse);
    });

    test('Core models must not assume mandatory HP, AC, initiative, or death', () {
      final sessionModelsFile = File('lib/models/session_graph_models.dart');
      final content = sessionModelsFile.readAsStringSync();

      // EncounterParticipant must allow optional/nullable combat stats
      expect(content.contains('final int? currentHp;'), isTrue);
      expect(content.contains('final int? maxHp;'), isTrue);
      expect(content.contains('final int? initiativeScore;'), isTrue);
      expect(content.contains('final bool? isDead;'), isTrue);
    });

    test('Core must have zero dependencies on external ruleset toolkit packages', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('dangerously_nerdy_5e_toolkit'), isFalse);
      expect(pubspec.contains('dnd5e'), isFalse);
    });
  });
}
