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
    test('withInitialValue, increment, and decrement require strongly-typed ReplicaId', () {
      final replica = ReplicaId('node-1');
      final counter = PnCounter.withInitialValue(10, replicaId: replica);
      expect(counter.value, equals(10));
      expect(counter.positive['node-1'], equals(10));

      final inc = counter.increment(5, replicaId: replica);
      expect(inc.value, equals(15));
      expect(inc.positive['node-1'], equals(15));

      final dec = inc.decrement(2, replicaId: replica);
      expect(dec.value, equals(13));
      expect(dec.negative['node-1'], equals(2));
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

      // Subsequent active writes must use a typed ReplicaId
      final updated = counter.increment(10, replicaId: ReplicaId('durable-replica'));
      expect(updated.value, equals(140));
      expect(updated.positive['durable-replica'], equals(10));
      expect(updated.positive['local'], equals(100));
    });
  });

  group('PartyPurse Replica Identity Hardening', () {
    test('modifyDenomination, setDenomination, add, deduct require strongly-typed ReplicaId', () {
      const purse = PartyPurse.empty();
      final replica = ReplicaId('active-runtime-writer');

      final modified = purse.modifyDenomination('gp', 50, replicaId: replica);
      expect(modified.getBalance('gp'), equals(50));

      final set = modified.setDenomination('gp', 100, replicaId: replica);
      expect(set.getBalance('gp'), equals(100));

      final other = const PartyPurse.empty().modifyDenomination('sp', 20, replicaId: replica);
      final added = set.add(other, replicaId: replica);
      expect(added.getBalance('sp'), equals(20));

      final deducted = added.deduct(other, replicaId: replica);
      expect(deducted.getBalance('sp'), equals(0));
    });
  });

  group('RoomNodeState copyWith Replica Identity Hardening', () {
    test('rejects raw Iterable activeEncounter with "local" or null nodeId', () {
      final room = RoomNodeState(roomId: 'r1', roomCode: 'ROOM1', title: 'Test Room');
      final participants = [
        EncounterParticipant(
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
