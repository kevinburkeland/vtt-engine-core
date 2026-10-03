import 'package:test/test.dart';
import 'package:vtt_engine_core/models/character_models.dart';
import 'package:vtt_engine_core/models/core_types.dart';
import 'package:vtt_engine_core/models/entity_reference.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/rules/i_ruleset_module.dart';

class MinimalTestRuleset implements IRulesetModule {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  String get moduleId => 'minimal_boardgame';
  @override
  String get displayName => 'Minimal Board Game';
  @override
  String get rulesetVersion => '1.0';

  @override
  IExhaustionMechanic? get exhaustionMechanic => null;
  @override
  IRestMechanic? get restMechanic => null;
  @override
  IActionEconomy? get actionEconomy => null;

  @override
  bool hasCapability<T extends IRulesetCapability>() =>
      getCapability<T>() != null;

  @override
  T? getCapability<T extends IRulesetCapability>() => null;
}

void main() {
  group('Generic Tabletop Entity & State Representation', () {
    test('Can represent an entity with no class, no level, no proficiency bonus, no HP, no initiative, and no concept of death', () {
      // Represents a worker-placement meeple or an abstract entity
      final meepleRef = RoomEntityLink(
        refType: const EntityCategory('worker_meeple', 'Worker Meeple'),
        entityId: 'meeple-blue-1',
        displayName: 'Blue Worker',
      );

      final participant = EncounterParticipant(
        participantId: 'part-1',
        entityLink: meepleRef,
        // No initiative
        initiativeScore: null,
        initiativeTieBreaker: null,
        // No HP
        currentHp: null,
        maxHp: null,
        tempHp: null,
        // No defense
        defense: null,
        // No death
        isDead: null,
        isDefeated: null,
        customProperties: {
          'assignedZone': 'wheat_field',
          'actionPoints': 3,
        },
      );

      expect(participant.participantId, equals('part-1'));
      expect(participant.initiativeScore, isNull);
      expect(participant.currentHp, isNull);
      expect(participant.maxHp, isNull);
      expect(participant.tempHp, isNull);
      expect(participant.defense, isNull);
      expect(participant.isDead, isNull);
      expect(participant.isDefeated, isNull);
      expect(participant.customProperties['assignedZone'], equals('wheat_field'));

      // Round-trip toMap / fromMap
      final map = participant.toMap();
      expect(map.containsKey('currentHp'), isFalse);
      expect(map.containsKey('maxHp'), isFalse);
      expect(map.containsKey('initiativeScore'), isFalse);
      expect(map.containsKey('isDead'), isFalse);

      final restored = EncounterParticipant.fromMap(map);
      expect(restored.participantId, equals('part-1'));
      expect(restored.currentHp, isNull);
      expect(restored.maxHp, isNull);
      expect(restored.initiativeScore, isNull);
      expect(restored.isDead, isNull);
      expect(restored.customProperties['actionPoints'], equals(3));
    });

    test('Can represent a ruleset-neutral Character without class, level, or speed', () {
      const character = Character(
        id: EntityId(
          slug: 'inspector-legrasse',
          ruleset: RulesetVersion.homebrew,
        ),
        name: 'Inspector Legrasse',
        speciesRef: EntityReference<DomainEntity>(
          refType: EntityType.custom,
          slug: 'human',
          displayName: 'Human',
        ),
        rulesetId: 'coc_7e',
        // No class progression
        progression: null,
        // No speed
        baseSpeed: null,
        // Generic scores
        baseScores: AttributePool({'sanity': 65, 'investigation': 70}),
        bonusScores: AttributePool.zero(),
        customProperties: {
          'occupation': 'Detective',
          'insanityStatus': 'normal',
        },
      );

      expect(character.name, equals('Inspector Legrasse'));
      expect(character.progression, isNull);
      expect(character.baseSpeed, isNull);
      expect(character.baseScores.getScore('sanity'), equals(65));
      expect(character.customProperties['occupation'], equals('Detective'));

      final map = character.toMap();
      final restored = Character.fromMap(map);
      expect(restored.name, equals('Inspector Legrasse'));
      expect(restored.progression, isNull);
      expect(restored.baseSpeed, isNull);
      expect(restored.baseScores.getScore('sanity'), equals(65));
      expect(restored.customProperties['insanityStatus'], equals('normal'));
    });

    test('EntityInstance models arbitrary game pieces without taxonomy constraints', () {
      final piece = EntityInstance(
        instanceId: 'ship-galleon-42',
        entityDefinitionId: 'ship_heavy_galleon',
        entityType: 'vehicle',
        displayName: 'The Black Pearl',
        position: {'x': 100, 'y': 250, 'heading': 90},
        runtimeData: {
          'hullIntegrity': 100,
          'cannonsReady': 12,
          'cargoUnits': 450,
        },
      );

      expect(piece.entityType, equals('vehicle'));
      expect(piece.position!['x'], equals(100));
      expect(piece.runtimeData['cannonsReady'], equals(12));

      final map = piece.toMap();
      final restored = EntityInstance.fromMap(map);
      expect(restored, equals(piece));
    });

    test('IRulesetModule capabilities query works cleanly for capability extensions', () {
      final module = MinimalTestRuleset();
      expect(module.hasCapability<IRestMechanic>(), isFalse);
      expect(module.getCapability<IRestMechanic>(), isNull);
      expect(module.hasCapability<IExhaustionMechanic>(), isFalse);
      expect(module.hasCapability<IActionEconomy>(), isFalse);
    });
  });
}
