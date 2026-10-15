import 'package:test/test.dart';
import 'package:vtt_engine_core/models/room_roll.dart';
import 'package:vtt_engine_core/models/entity_reference.dart';
import 'package:vtt_engine_core/models/core_types.dart';
import 'package:vtt_engine_core/models/generic_tabletop_primitives.dart';

void main() {
  group('RoomRoll Serialization & Encoder Decoupling', () {
    test('toJsonMap produces integer millisecond timestamps', () {
      final now = DateTime.utc(2026, 3, 14, 12);
      final roll = RoomRoll(
        id: 'roll-1',
        roomCode: 'room1',
        playerName: 'Hero',
        timestamp: now,
        formulaString: '1d20+5',
        total: 18,
        individualRolls: const [13],
        isCrit: false,
        isFumble: false,
      );

      final jsonMap = roll.toJsonMap();
      expect(jsonMap['timestamp'], equals(now.millisecondsSinceEpoch));
      expect(
        jsonMap['expireAt'],
        equals(now.add(const Duration(hours: 24)).millisecondsSinceEpoch),
      );
      expect(jsonMap['formulaString'], equals('1d20+5'));
      expect(jsonMap['total'], equals(18));
    });

    test('toFirestoreMap requires and uses encodeTimestamp callback', () {
      final now = DateTime.utc(2026, 3, 14, 12);
      final roll = RoomRoll(
        id: 'roll-1',
        roomCode: 'room1',
        playerName: 'Hero',
        timestamp: now,
        formulaString: '1d20+5',
        total: 18,
        individualRolls: const [13],
        isCrit: false,
        isFumble: false,
      );

      final fsMap = roll.toFirestoreMap((dt) => 'Timestamp(${dt.toIso8601String()})');
      expect(fsMap['timestamp'], equals('Timestamp(${now.toIso8601String()})'));
      expect(
        fsMap['expireAt'],
        equals('Timestamp(${now.add(const Duration(hours: 24)).toIso8601String()})'),
      );
    });
  });

  group('EntityReference toTraitDefinition resolver decoupling', () {
    test('toTraitDefinition executes required resolver callback', () {
      const ref = EntityReference<DomainEntity>.empty(
        refType: EntityType('trait'),
        slug: 'grappler',
        displayName: 'Grappler',
      );

      final trait = ref.toTraitDefinition((slug) {
        expect(slug, equals('grappler'));
        return const ITraitDefinition(
          id: 'grappler',
          name: 'Grappler',
          category: 'feat',
          properties: {'prerequisite': 'Strength 13+'},
        );
      });

      expect(trait.id, equals('grappler'));
      expect(trait.name, equals('Grappler'));
      expect(trait.properties['prerequisite'], equals('Strength 13+'));
    });
  });
}
