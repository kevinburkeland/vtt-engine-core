import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';

void main() {
  group('PnCounter CvRDT Properties & Mathematics', () {
    test('Default constructor creates empty counter with value 0', () {
      const counter = PnCounter();
      expect(counter.value, 0);
      expect(counter.positiveSum, 0);
      expect(counter.negativeSum, 0);
    });

    test('withInitialValue creates counter on designated node', () {
      final counter = PnCounter.withInitialValue(100, nodeId: 'dm-node');
      expect(counter.value, 100);
      expect(counter.positive, {'dm-node': 100});
      expect(counter.negative, isEmpty);
    });

    test('increments and decrements advance respective vectors per node', () {
      var counter = const PnCounter();
      counter = counter.increment(50, nodeId: 'player-1');
      counter = counter.increment(25, nodeId: 'player-2');
      counter = counter.decrement(10, nodeId: 'player-1');

      expect(counter.positive['player-1'], 50);
      expect(counter.positive['player-2'], 25);
      expect(counter.negative['player-1'], 10);
      expect(counter.value, 65);
    });

    test('value clamps at zero when decrements exceed increments', () {
      var counter = const PnCounter();
      counter = counter.increment(20, nodeId: 'node-a');
      counter = counter.decrement(50, nodeId: 'node-a');

      expect(counter.positiveSum, 20);
      expect(counter.negativeSum, 50);
      expect(counter.value, 0);
    });

    test('CvRDT Lattice Merge: Idempotent, Commutative, and Associative', () {
      final a = const PnCounter()
          .increment(100, nodeId: 'node-1')
          .decrement(30, nodeId: 'node-1');

      final b = const PnCounter()
          .increment(100, nodeId: 'node-1')
          .increment(50, nodeId: 'node-2')
          .decrement(10, nodeId: 'node-2');

      final c = const PnCounter()
          .increment(75, nodeId: 'node-3')
          .decrement(20, nodeId: 'node-1');

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
      final initialPurse = PnCounter.withInitialValue(100, nodeId: 'host');

      // Peer A spends the entire 100 GP
      final peerA = initialPurse.decrement(100, nodeId: 'peerA');
      expect(peerA.value, 0);

      // Peer B concurrently deposits 50 GP of loot without knowing Peer A spent 100 GP
      final peerB = initialPurse.increment(50, nodeId: 'peerB');
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
      final original = const PnCounter()
          .increment(200, nodeId: 'node-x')
          .decrement(45, nodeId: 'node-y');

      final map = original.toMap();
      final restored = PnCounter.fromMap(map);

      expect(restored, equals(original));
      expect(restored.value, 155);
    });
  });
}
