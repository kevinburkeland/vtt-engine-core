import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';

void main() {
  group('PnCounter CvRDT Properties & Mathematics', () {
    test('Default constructor creates empty counter with value 0', () {
      const counter = PnCounter.empty();
      expect(counter.value, 0);
      expect(counter.positiveSum, 0);
      expect(counter.negativeSum, 0);
    });

    test('withInitialValue creates counter on designated replica', () {
      final counter = PnCounter.withInitialValue(100, replicaId: ReplicaId('dm-node'));
      expect(counter.value, 100);
      expect(counter.positive, {'dm-node': 100});
      expect(counter.negative, isEmpty);
    });

    test('increments and decrements advance respective vectors per replica', () {
      var counter = const PnCounter.empty();
      final p1 = ReplicaId('player-1');
      final p2 = ReplicaId('player-2');
      counter = counter.increment(50, replicaId: p1);
      counter = counter.increment(25, replicaId: p2);
      counter = counter.decrement(10, replicaId: p1);

      expect(counter.positive['player-1'], 50);
      expect(counter.positive['player-2'], 25);
      expect(counter.negative['player-1'], 10);
      expect(counter.value, 65);
    });

    test('value clamps at zero when decrements exceed increments', () {
      var counter = const PnCounter.empty();
      final nodeA = ReplicaId('node-a');
      counter = counter.increment(20, replicaId: nodeA);
      counter = counter.decrement(50, replicaId: nodeA);

      expect(counter.positiveSum, 20);
      expect(counter.negativeSum, 50);
      expect(counter.value, 0);
    });

    test('CvRDT Lattice Merge: Idempotent, Commutative, and Associative', () {
      final n1 = ReplicaId('node-1');
      final n2 = ReplicaId('node-2');
      final n3 = ReplicaId('node-3');

      final a = const PnCounter.empty()
          .increment(100, replicaId: n1)
          .decrement(30, replicaId: n1);

      final b = const PnCounter.empty()
          .increment(100, replicaId: n1)
          .increment(50, replicaId: n2)
          .decrement(10, replicaId: n2);

      final c = const PnCounter.empty()
          .increment(75, replicaId: n3)
          .decrement(20, replicaId: n1);

      // Idempotence: a merge a == a
      expect(a.merge(a), equals(a));

      // Commutativity: a merge b == b merge a
      final ab = a.merge(b);
      final ba = b.merge(a);
      expect(ab, equals(ba));
      expect(ab.value, (100 + 50) - (30 + 10)); // 110

      // Associativity: (a merge b) merge c == a merge (b merge c)
      final left = (a.merge(b)).merge(c);
      final right = a.merge(b.merge(c));
      expect(left, equals(right));
      expect(left.positive['node-1'], 100);
      expect(left.positive['node-2'], 50);
      expect(left.positive['node-3'], 75);
      expect(left.negative['node-1'], 30); // max(30, 20) = 30
      expect(left.negative['node-2'], 10);
    });

    test(
        'Concurrent deposit and withdrawal converge deterministically without coin resurrection',
        () {
      // Starting balance of 100 GP created on host
      final initialPurse = PnCounter.withInitialValue(100, replicaId: ReplicaId('host'));

      // Peer A spends the entire 100 GP
      final peerA = initialPurse.decrement(100, replicaId: ReplicaId('peerA'));
      expect(peerA.value, 0);

      // Peer B concurrently deposits 50 GP of loot without knowing Peer A spent 100 GP
      final peerB = initialPurse.increment(50, replicaId: ReplicaId('peerB'));
      expect(peerB.value, 150);

      // Merge on reconciliation
      final merged = peerA.merge(peerB);

      // Total deposits: host (100) + peerB (50) = 150
      // Total withdrawals: peerA (100)
      // Net balance: 150 - 100 = 50 GP!
      // Peer A spending money down to 0 does NOT resurrect the 100 GP!
      expect(merged.value, 50);
      expect(merged.positiveSum, 150);
      expect(merged.negativeSum, 100);
    });

    test('Serialization round-trip: toMap and fromMap preserve vectors', () {
      final original = const PnCounter.empty()
          .increment(200, replicaId: ReplicaId('node-x'))
          .decrement(45, replicaId: ReplicaId('node-y'));

      final map = original.toMap();
      final restored = PnCounter.fromMap(map);

      expect(restored, equals(original));
      expect(restored.value, 155);
    });
  });

  group('Multi-Runtime Concurrent PN-Counter Correctness (Claude Bug Regression)', () {
    test('two concurrent runtimes sharing durable context do not lose independent increments', () {
      // Base historical counter with 10 under an existing historical component
      final base = PnCounter(
        positive: {'historical-component': 10},
        negative: const {},
      );

      // Each runtime/tab receives a distinct active ReplicaId
      final replicaA = ReplicaId('runtime-tab-a-uuid');
      final replicaB = ReplicaId('runtime-tab-b-uuid');

      final stateA = base.increment(5, replicaId: replicaA);
      final stateB = base.increment(8, replicaId: replicaB);

      final merged = stateA.merge(stateB);

      expect(replicaA, isNot(equals(replicaB)));
      expect(merged.value, equals(23)); // 10 + 5 + 8 = 23
      expect(merged.positive['historical-component'], equals(10));
      expect(merged.positive[replicaA.value], equals(5));
      expect(merged.positive[replicaB.value], equals(8));
    });

    test('failure-shape demonstration: shared writer IDs merge incorrectly via lattice max', () {
      // Base historical counter with 10 under a component
      final base = PnCounter(
        positive: {'shared-device-writer': 10},
        negative: const {},
      );

      // If two concurrent tabs share the same single-writer identity:
      final sharedWriter = ReplicaId('shared-device-writer');

      // Tab A adds 5 -> component becomes 15
      final tabA = base.increment(5, replicaId: sharedWriter);
      expect(tabA.positive['shared-device-writer'], equals(15));

      // Tab B concurrently adds 8 from the same base -> component becomes 18
      final tabB = base.increment(8, replicaId: sharedWriter);
      expect(tabB.positive['shared-device-writer'], equals(18));

      // Merge takes component-wise max: max(15, 18) = 18
      final badMerge = tabA.merge(tabB);

      // FAILURE: 5 increments from Tab A are permanently LOST because both tabs wrote
      // to the same monotonic single-writer component!
      expect(badMerge.value, equals(18));
      expect(badMerge.value, isNot(equals(23)));
    });

    test('two concurrent runtimes sharing durable context do not lose independent decrements', () {
      final base = PnCounter(
        positive: {'historical-component': 50},
        negative: const {},
      );

      final replicaA = ReplicaId('runtime-tab-a-uuid');
      final replicaB = ReplicaId('runtime-tab-b-uuid');

      final stateA = base.decrement(10, replicaId: replicaA);
      final stateB = base.decrement(15, replicaId: replicaB);

      final merged = stateA.merge(stateB);

      expect(replicaA, isNot(equals(replicaB)));
      expect(merged.value, equals(25)); // 50 - (10 + 15) = 25
      expect(merged.negative[replicaA.value], equals(10));
      expect(merged.negative[replicaB.value], equals(15));
    });
  });
}
