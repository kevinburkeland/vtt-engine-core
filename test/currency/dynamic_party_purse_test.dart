import 'package:test/test.dart';
import 'package:vtt_engine_core/models/party_purse.dart';

void main() {
  group('Dynamic PartyPurse Ruleset-Agnostic Lattice Tests', () {
    test('supports arbitrary custom currency denominations', () {
      var purse = const PartyPurse();

      purse = purse.modifyDenomination('credits', 500, nodeId: 'nodeA');
      purse = purse.modifyDenomination('scrip', 150, nodeId: 'nodeA');

      expect(purse.getBalance('credits'), equals(500));
      expect(purse.getBalance('scrip'), equals(150));
      expect(purse.totalCoins, equals(650));
    });

    test(
        'reconciles concurrent mutations across heterogeneous nodes deterministically',
        () {
      final nodeA = const PartyPurse()
          .modifyDenomination('credits', 300, nodeId: 'nodeA')
          .modifyDenomination('mana_shards', 50, nodeId: 'nodeA');

      final nodeB = const PartyPurse()
          .modifyDenomination('credits', 200, nodeId: 'nodeB')
          .modifyDenomination('mana_shards', 30, nodeId: 'nodeB');

      // Lattice join (A merge B)
      final mergedA = nodeA.merge(nodeB);
      // Lattice join (B merge A)
      final mergedB = nodeB.merge(nodeA);

      // Mathematical commutativity: A ⊔ B == B ⊔ A
      expect(mergedA, equals(mergedB));
      expect(mergedA.getBalance('credits'), equals(500));
      expect(mergedA.getBalance('mana_shards'), equals(80));
    });

    test('serializes and deserializes custom denominations cleanly', () {
      final original = const PartyPurse()
          .modifyDenomination('gp', 100, nodeId: 'runner1')
          .modifyDenomination('credits', 2500, nodeId: 'runner1');

      final map = original.toMap();
      final restored = PartyPurse.fromMap(map);

      expect(restored, equals(original));
      expect(restored.getBalance('gp'), equals(100));
      expect(restored.getBalance('credits'), equals(2500));
    });
  });
}
