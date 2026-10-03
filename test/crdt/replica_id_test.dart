import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('ReplicaId Value Object Tests', () {
    test('successfully instantiates with valid non-local replica string', () {
      final id = ReplicaId('node-uuid-1234');
      expect(id.value, equals('node-uuid-1234'));
      expect(id.toString(), equals('node-uuid-1234'));
    });

    test('rejects empty, whitespace-only, and "local" identifiers', () {
      expect(() => ReplicaId(''), throwsArgumentError);
      expect(() => ReplicaId('   '), throwsArgumentError);
      expect(() => ReplicaId('local'), throwsArgumentError);
      expect(() => ReplicaId('Local'), throwsArgumentError);
      expect(() => ReplicaId('LOCAL'), throwsArgumentError);
      expect(() => ReplicaId('  local  '), throwsArgumentError);
    });

    test('implements value equality and comparison', () {
      final id1 = ReplicaId('alpha');
      final id2 = ReplicaId('alpha');
      final id3 = ReplicaId('beta');

      expect(id1, equals(id2));
      expect(id1.hashCode, equals(id2.hashCode));
      expect(id1, isNot(equals(id3)));
      expect(id1.compareTo(id3), lessThan(0));
    });
  });

  group('PnCounter Replica Identity Hardening', () {
    test('withInitialValue, increment, and decrement reject "local" and empty nodeId', () {
      expect(
        () => PnCounter.withInitialValue(10, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => PnCounter.withInitialValue(10, nodeId: '   '),
        throwsArgumentError,
      );

      final counter = PnCounter.withInitialValue(10, nodeId: 'node-1');
      expect(
        () => counter.increment(5, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => counter.increment(5, nodeId: ''),
        throwsArgumentError,
      );
      expect(
        () => counter.decrement(2, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => counter.decrement(2, nodeId: '   '),
        throwsArgumentError,
      );
    });

    test('preserves historical "local" contributions from persisted maps', () {
      const historicalMap = {
        'positive': {'local': 100, 'node-1': 50},
        'negative': {'local': 20},
      };

      final counter = PnCounter.fromMap(historicalMap);
      expect(counter.value, equals(130));
      expect(counter.positive['local'], equals(100));
      expect(counter.negative['local'], equals(20));

      // Subsequent writes must use durable replica ID
      final updated = counter.increment(10, nodeId: 'durable-replica');
      expect(updated.value, equals(140));
      expect(updated.positive['durable-replica'], equals(10));
      expect(updated.positive['local'], equals(100));
    });
  });

  group('PartyPurse Replica Identity Hardening', () {
    test('modifyDenomination, setDenomination, add, deduct reject "local" and empty nodeId', () {
      final purse = const PartyPurse();

      expect(
        () => purse.modifyDenomination('gp', 50, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => purse.modifyDenomination('gp', 50, nodeId: ''),
        throwsArgumentError,
      );
      expect(
        () => purse.setDenomination('gp', 100, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => purse.setDenomination('gp', 100, nodeId: '   '),
        throwsArgumentError,
      );

      const other = PartyPurse();
      expect(
        () => purse.add(other, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => purse.deduct(other, nodeId: 'local'),
        throwsArgumentError,
      );
    });
  });

  group('RoomNodeState copyWith Replica Identity Hardening', () {
    test('rejects raw Iterable activeEncounter with "local" or null nodeId', () {
      const room = RoomNodeState(roomId: 'r1', roomCode: 'ROOM1', title: 'Test Room');
      final participants = [
        const EncounterParticipant(
          participantId: 'p1',
          entityLink: RoomEntityLink(
            entityId: 'e1',
            displayName: 'Hero',
          ),
          currentHp: 20,
          maxHp: 20,
        ),
      ];

      expect(
        () => room.copyWith(activeEncounter: participants, nodeId: 'local'),
        throwsArgumentError,
      );
      expect(
        () => room.copyWith(activeEncounter: participants),
        throwsArgumentError,
      );

      final valid = room.copyWith(
        activeEncounter: participants,
        nodeId: 'replica-dm',
      );
      expect(valid.activeEncounterList.length, equals(1));
      expect(
        valid.activeEncounter.items['p1']!.timestamp.nodeId,
        equals('replica-dm'),
      );
    });
  });
}
