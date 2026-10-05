import 'package:test/test.dart';
import 'package:vtt_engine_core/models/core_types.dart';
import 'package:vtt_engine_core/models/entity_reference.dart';
import 'package:vtt_engine_core/models/character_models.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/homebrew/models/homebrew_entity.dart';
import 'package:vtt_engine_core/utils/deep_immutable.dart';

void main() {
  group('Cold Iron Birdcage — Pass 2.3: Replicated Value Semantics (Core)', () {
    group('deepFreezeMap Key Integrity', () {
      test('nested String-key map succeeds and deep freezes', () {
        final input = {
          'outer': {
            'inner': {'leaf': 42}
          }
        };
        final frozen = deepFreezeMap(input);
        expect(frozen['outer']['inner']['leaf'], equals(42));
      });

      test('integer key throws ArgumentError and does not stringify', () {
        final input = {
          1: 'val',
        };
        expect(
          () => deepFreezeMap(input),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Replicated JSON-like metadata requires string map keys'),
          )),
        );
      });

      test('nested integer key throws ArgumentError', () {
        final input = {
          'valid': {
            2: 'nested_int_key',
          }
        };
        expect(
          () => deepFreezeMap(input),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('mixed String and int keys throw ArgumentError', () {
        final input = {
          'a': 1,
          2: 'b',
        };
        expect(
          () => deepFreezeMap(input),
          throwsA(isA<ArgumentError>()),
        );
      });

      test("{1: a, 1: b} throws rather than collapsing", () {
        final input = {
          1: 'a',
          '1': 'b',
        };
        expect(
          () => deepFreezeMap(input),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('null and empty map return empty unmodifiable map', () {
        final fromNull = deepFreezeMap(null);
        final fromEmpty = deepFreezeMap({});
        expect(fromNull, isEmpty);
        expect(fromEmpty, isEmpty);
        expect(() => fromNull['a'] = 1, throwsUnsupportedError);
      });
    });

    group('EntityReference Deep Value Semantics', () {
      test('independently allocated nested-equal EntityReferences are equal with identical hashCodes', () {
        final refA = EntityReference(
          refType: const EntityType('item'),
          slug: 'ring_protection',
          displayName: 'Ring of Protection',
          grantedSkills: ['acrobatics', 'athletics'],
          customProperties: {
            'bonus': 1,
            'nested': {'type': 'ward', 'tags': ['abjuration', 'attunement']}
          },
        );

        final refB = EntityReference(
          refType: const EntityType('item'),
          slug: 'ring_protection',
          displayName: 'Ring of Protection',
          grantedSkills: ['acrobatics', 'athletics'],
          customProperties: {
            'bonus': 1,
            'nested': {'type': 'ward', 'tags': ['abjuration', 'attunement']}
          },
        );

        expect(refA, equals(refB));
        expect(refB, equals(refA));
        expect(refA.hashCode, equals(refB.hashCode));
      });

      test('reordered nested map keys remain equal with equal hashCodes', () {
        final refA = EntityReference(
          refType: const EntityType('spell'),
          slug: 'fireball',
          displayName: 'Fireball',
          customProperties: {
            'a': 1,
            'b': {'x': 10, 'y': 20},
          },
        );

        final refB = EntityReference(
          refType: const EntityType('spell'),
          slug: 'fireball',
          displayName: 'Fireball',
          customProperties: {
            'b': {'y': 20, 'x': 10},
            'a': 1,
          },
        );

        expect(refA, equals(refB));
        expect(refA.hashCode, equals(refB.hashCode));
      });

      test('nested list element order differences remain unequal', () {
        final refA = EntityReference(
          refType: const EntityType('item'),
          slug: 'item1',
          displayName: 'Item 1',
          grantedSkills: ['athletics', 'acrobatics'],
        );

        final refB = EntityReference(
          refType: const EntityType('item'),
          slug: 'item1',
          displayName: 'Item 1',
          grantedSkills: ['acrobatics', 'athletics'],
        );

        expect(refA, isNot(equals(refB)));
      });

      test('nested metadata difference causes inequality', () {
        final refA = EntityReference(
          refType: const EntityType('feat'),
          slug: 'alert',
          displayName: 'Alert',
          customProperties: {'initiative': 5},
        );

        final refB = EntityReference(
          refType: const EntityType('feat'),
          slug: 'alert',
          displayName: 'Alert',
          customProperties: {'initiative': 4},
        );

        expect(refA, isNot(equals(refB)));
      });

      test('copyWith and cast preserve deep equality semantics', () {
        final refA = EntityReference(
          refType: const EntityType('feat'),
          slug: 'alert',
          displayName: 'Alert',
          customProperties: {'val': 1},
        );

        final refCopy = refA.copyWith();
        expect(refCopy, equals(refA));
        expect(refCopy.hashCode, equals(refA.hashCode));

        final refModified = refA.copyWith(customProperties: {'val': 2});
        expect(refModified, isNot(equals(refA)));
      });
    });

    group('LootContainer & InventoryItemInstance Deep Value Semantics', () {
      test('LootContainer structural equality and hashCode', () {
        final c1 = LootContainer(
          containerId: 'chest_1',
          name: 'Old Chest',
          items: [
            InventoryItemInstance(
              itemRef: const EntityReference.empty(
                refType: EntityType('item'),
                slug: 'potion',
                displayName: 'Potion',
              ),
              instanceId: 'inst_1',
              customProperties: {'healing': 10},
            ),
          ],
          customProperties: {'material': 'wood'},
        );

        final c2 = LootContainer(
          containerId: 'chest_1',
          name: 'Old Chest',
          items: [
            InventoryItemInstance(
              itemRef: const EntityReference.empty(
                refType: EntityType('item'),
                slug: 'potion',
                displayName: 'Potion',
              ),
              instanceId: 'inst_1',
              customProperties: {'healing': 10},
            ),
          ],
          customProperties: {'material': 'wood'},
        );

        expect(c1, equals(c2));
        expect(c1.hashCode, equals(c2.hashCode));

        final c3 = c1.copyWith(customProperties: {'material': 'iron'});
        expect(c1, isNot(equals(c3)));
      });

      test('InventoryItemInstance observes customProperties changes even with identical length', () {
        final itemA = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            refType: EntityType('weapon'),
            slug: 'dagger',
            displayName: 'Dagger',
          ),
          instanceId: 'dagger_1',
          customProperties: {'damage': '1d4'},
        );

        final itemB = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            refType: EntityType('weapon'),
            slug: 'dagger',
            displayName: 'Dagger',
          ),
          instanceId: 'dagger_1',
          customProperties: {'damage': '1d6'}, // Same length (1 key), different value!
        );

        expect(itemA, isNot(equals(itemB)));
        expect(itemA.hashCode, isNot(equals(itemB.hashCode)));
      });
    });

    group('HomebrewEntity Deep Value Semantics', () {
      test('HomebrewEntity observes rawPayload, normalizedData, and unparsedPayload changes', () {
        final e1 = HomebrewEntity(
          id: 'hb_1',
          name: 'Custom Monster',
          entityType: 'monster',
          ruleset: RulesetVersion.v2024,
          normalizedData: {'cr': 5},
          unparsedPayload: {'unknownField': 'preserved'},
        );

        final e2 = HomebrewEntity(
          id: 'hb_1',
          name: 'Custom Monster',
          entityType: 'monster',
          ruleset: RulesetVersion.v2024,
          normalizedData: {'cr': 5},
          unparsedPayload: {'unknownField': 'preserved'},
        );

        expect(e1, equals(e2));
        expect(e1.hashCode, equals(e2.hashCode));

        final e3 = e1.copyWith(normalizedData: {'cr': 6});
        expect(e1, isNot(equals(e3)));

        final e4 = e1.copyWith(unparsedPayload: {'unknownField': 'modified'});
        expect(e1, isNot(equals(e4)));
      });
    });
 
    group('Session Graph Models Deep Value Semantics', () {
      test('RoomNodeState observes container, minion, and customProperties changes', () {
        final r1 = RoomNodeState(
          roomId: 'room_1',
          roomCode: 'ROOM-1',
          title: 'Dungeon Room',
          customProperties: {'lighting': 'dim'},
        );

        final r2 = RoomNodeState(
          roomId: 'room_1',
          roomCode: 'ROOM-1',
          title: 'Dungeon Room',
          customProperties: {'lighting': 'dim'},
        );

        expect(r1, equals(r2));
        expect(r1.hashCode, equals(r2.hashCode));

        final r3 = r1.copyWith(customProperties: {'lighting': 'bright'});
        expect(r1, isNot(equals(r3)));
        expect(r1.hashCode, isNot(equals(r3.hashCode)));
      });

      test('EntityInstance observes position, runtimeData, and customProperties changes', () {
        final e1 = EntityInstance(
          instanceId: 'inst_1',
          displayName: 'Statue',
          position: {'x': 10, 'y': 20},
          runtimeData: {'activated': false},
        );

        final e2 = EntityInstance(
          instanceId: 'inst_1',
          displayName: 'Statue',
          position: {'x': 10, 'y': 20},
          runtimeData: {'activated': false},
        );

        expect(e1, equals(e2));
        expect(e1.hashCode, equals(e2.hashCode));

        final e3 = e1.copyWith(position: {'x': 11, 'y': 20});
        expect(e1, isNot(equals(e3)));

        final e4 = e1.copyWith(runtimeData: {'activated': true});
        expect(e1, isNot(equals(e4)));
      });

      test('RoomEntityLink observes position and cloneRuntimeData changes', () {
        final l1 = RoomEntityLink(
          entityId: 'ent_1',
          displayName: 'Link 1',
          position: {'x': 1},
          cloneRuntimeData: {'hp': 15},
        );

        final l2 = RoomEntityLink(
          entityId: 'ent_1',
          displayName: 'Link 1',
          position: {'x': 1},
          cloneRuntimeData: {'hp': 15},
        );

        expect(l1, equals(l2));
        expect(l1.hashCode, equals(l2.hashCode));

        final l3 = l1.copyWith(cloneRuntimeData: {'hp': 10});
        expect(l1, isNot(equals(l3)));
      });

      test('EncounterParticipant observes all logical fields including activeConditions and customProperties', () {
        final p1 = EncounterParticipant(
          participantId: 'p_1',
          entityLink: const RoomEntityLink.empty(),
          currentHp: 20,
          maxHp: 20,
          activeConditions: ['poisoned'],
          customProperties: {'buff': 'shield'},
        );

        final p2 = EncounterParticipant(
          participantId: 'p_1',
          entityLink: const RoomEntityLink.empty(),
          currentHp: 20,
          maxHp: 20,
          activeConditions: ['poisoned'],
          customProperties: {'buff': 'shield'},
        );

        expect(p1, equals(p2));
        expect(p1.hashCode, equals(p2.hashCode));

        final p3 = p1.copyWith(activeConditions: ['blinded']);
        expect(p1, isNot(equals(p3)));

        final p4 = p1.copyWith(customProperties: {'buff': 'bless'});
        expect(p1, isNot(equals(p4)));
      });
    });
  });
}
