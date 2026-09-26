import 'package:test/test.dart';
import 'package:vtt_engine_core/models/party_purse.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';


extension on PartyPurse {
  int get gp => getBalance('gp');
  int get sp => getBalance('sp');
  PnCounter get gpCounter => getCounter('gp');
  PnCounter get spCounter => getCounter('sp');

  PartyPurse setCoins({int? gp, int? sp, String nodeId = 'local'}) {
    var p = this;
    if (gp != null) p = p.setDenomination('gp', gp, nodeId: nodeId);
    if (sp != null) p = p.setDenomination('sp', sp, nodeId: nodeId);
    return p;
  }

  PartyPurse withdrawCoins({int gp = 0, int sp = 0, String nodeId = 'local'}) {
    var p = this;
    if (gp > 0) p = p.modifyDenomination('gp', -(gp > p.gp ? p.gp : gp), nodeId: nodeId);
    if (sp > 0) p = p.modifyDenomination('sp', -(sp > p.sp ? p.sp : sp), nodeId: nodeId);
    return p;
  }
}

void main() {
  group('PartyPurse CvRDT Reduction & Convergence Tests', () {
    test(
        'setCoins decrements correctly and converges across CvRDT lattice join',
        () {
      // 1. Initial purse on Node A with 100 GP
      final purseA = const PartyPurse().setCoins(gp: 100, nodeId: 'nodeA');
      expect(purseA.gp, 100);
      expect(purseA.gpCounter.positive['nodeA'], 100);
      expect(purseA.gpCounter.negative['nodeA'] ?? 0, 0);

      // 2. Node A spends 40 GP, reducing balance to 60 GP
      final updatedA = purseA.setCoins(gp: 60, nodeId: 'nodeA');
      expect(updatedA.gp, 60);
      expect(updatedA.gpCounter.positive['nodeA'], 100);
      expect(updatedA.gpCounter.negative['nodeA'], 40);

      // 3. Node B had the original purse (100 GP)
      final purseB = purseA;

      // 4. Merge updatedA (60 GP) with purseB (100 GP)
      // Prior bug: merge took max(positive) and max(negative), but since negative was empty, it reverted to 100!
      // With our fix: negative has 40, so max(pos)=100, max(neg)=40 => 100 - 40 = 60!
      final merged = updatedA.merge(purseB);
      expect(merged.gp, 60,
          reason:
              'Reduced balance must NOT revert to previous maximum on merge');
    });

    test('copyWith with scalar reduction records negative decrement vector',
        () {
      final initial =
          const PartyPurse().setCoins(gp: 50, sp: 20, nodeId: 'node1');
      expect(initial.gp, 50);
      expect(initial.sp, 20);

      final reduced = initial.setCoins(gp: 30, sp: 5, nodeId: 'node1');
      expect(reduced.gp, 30);
      expect(reduced.sp, 5);
      expect(reduced.gpCounter.negative['node1'], 20);
      expect(reduced.spCounter.negative['node1'], 15);

      // Merge with previous snapshot
      final merged = reduced.merge(initial);
      expect(merged.gp, 30);
      expect(merged.sp, 5);
    });

    test(
        'withdrawCoins records negative decrement and preserves CvRDT lattice monotonicity',
        () {
      final purse = const PartyPurse().setCoins(gp: 150, nodeId: 'local');
      final afterWithdraw = purse.withdrawCoins(gp: 50, nodeId: 'local');
      expect(afterWithdraw.gp, 100);

      final merged = afterWithdraw.merge(purse);
      expect(merged.gp, 100,
          reason: 'Merged purse must honor withdrawal and remain 100 GP');
    });

    test('Multiple nodes spending concurrently converges deterministically',
        () {
      final base = const PartyPurse().setCoins(gp: 200, nodeId: 'init');

      // Node A spends 30 GP
      final nodeA = base.withdrawCoins(gp: 30, nodeId: 'nodeA');
      expect(nodeA.gp, 170);

      // Node B spends 50 GP
      final nodeB = base.withdrawCoins(gp: 50, nodeId: 'nodeB');
      expect(nodeB.gp, 150);

      // Merge on Node A
      final mergedOnA = nodeA.merge(nodeB);
      // Total spent = 30 + 50 = 80 => 200 - 80 = 120 GP
      expect(mergedOnA.gp, 120);

      // Merge on Node B
      final mergedOnB = nodeB.merge(nodeA);
      expect(mergedOnB.gp, 120);
      expect(mergedOnA, equals(mergedOnB));
    });
  });
}
