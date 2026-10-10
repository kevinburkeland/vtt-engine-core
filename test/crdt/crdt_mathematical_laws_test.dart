import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/models/party_purse.dart';

void main() {
  group('Cold Iron Birdcage — Pass 3.0: Primitive CRDT Mathematical Correctness', () {
    const seed = 0xCAFEBABE;
    const iterations = 100;

    group('A & B. PnCounter Signed Math and Component Invariants', () {
      test('direct construction with negative component value fails loudly with ArgumentError', () {
        expect(
          () => PnCounter(positive: {'node-1': -5}),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => PnCounter(negative: {'node-1': -1}),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('fromMap with negative component value fails loudly with FormatException', () {
        expect(
          () => PnCounter.fromMap({
            'positive': {'node-1': -5}
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => PnCounter.fromMap({
            'negative': {'node-1': -1}
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('historical arbitrary keys (including "init" and "cloud") are accepted and preserved', () {
        final counter = PnCounter.fromMap({
          'positive': {'init': 100, 'cloud': 50, 'custom-uuid-1': 20},
          'negative': {'cloud': 10, 'custom-uuid-2': 5},
        });
        expect(counter.positive['init'], equals(100));
        expect(counter.positive['cloud'], equals(50));
        expect(counter.negative['cloud'], equals(10));
        expect(counter.value, equals((100 + 50 + 20) - (10 + 5))); // 155
      });

      test('withInitialValue correctly represents signed amounts', () {
        final pos = PnCounter.withInitialValue(10, replicaId: ReplicaId('nodeA'));
        expect(pos.value, equals(10));
        expect(pos.positive['nodeA'], equals(10));
        expect(pos.negative, isEmpty);

        final neg = PnCounter.withInitialValue(-15, replicaId: ReplicaId('nodeA'));
        expect(neg.value, equals(-15));
        expect(neg.positive, isEmpty);
        expect(neg.negative['nodeA'], equals(15));

        final zero = PnCounter.withInitialValue(0, replicaId: ReplicaId('nodeA'));
        expect(zero.value, equals(0));
        expect(zero.positive, isEmpty);
        expect(zero.negative, isEmpty);
      });
    });

    group('C. PnCounter Hash Contract', () {
      test('Counters with same mappings inserted in different orders compare equal and have identical hashCodes', () {
        final c1 = PnCounter(
          positive: {'node-a': 10, 'node-b': 20, 'node-c': 30},
          negative: {'node-x': 5, 'node-y': 15},
        );
        final c2 = PnCounter(
          positive: {'node-c': 30, 'node-a': 10, 'node-b': 20},
          negative: {'node-y': 15, 'node-x': 5},
        );

        expect(c1, equals(c2));
        expect(c2, equals(c1));
        expect(c1.hashCode, equals(c2.hashCode));
      });
    });

    group('D & E. PartyPurse Nonnegative Balance View & setDenomination Math', () {
      test('visible balance clamps at zero while underlying counter retains signed debt', () {
        final counter = PnCounter(
          positive: {'node-a': 10},
          negative: {'node-b': 20},
        );
        expect(counter.value, equals(-10));
        expect(counter.effectiveNonNegativeValue, equals(0));

        final purse = PartyPurse.fromCounters({'gp': counter});
        expect(purse.getBalance('gp'), equals(0));
        expect(purse.balances['gp'], equals(0));
        expect(purse.getCounter('gp').value, equals(-10));
      });

      test('setDenomination against hidden negative debt applies differential against signed value', () {
        // counter true value = -10, visible currency balance = 0
        final counter = PnCounter(
          positive: {'node-a': 10},
          negative: {'node-b': 20},
        );
        final purse = PartyPurse.fromCounters({'gp': counter});
        expect(purse.getBalance('gp'), equals(0));
        expect(purse.getCounter('gp').value, equals(-10));

        // setDenomination(target: 5) must apply +15, producing mathematical value 5
        final updated = purse.setDenomination('gp', 5, replicaId: ReplicaId('player-1'));
        expect(updated.getCounter('gp').value, equals(5));
        expect(updated.getBalance('gp'), equals(5));
        expect(updated.getCounter('gp').positive['player-1'], equals(15));
      });

      test('setDenomination regressions: normal increase, normal decrease, zero, idempotent', () {
        final base = const PartyPurse.empty().setDenomination('gp', 100, replicaId: ReplicaId('r1'));
        expect(base.getBalance('gp'), equals(100));
        expect(base.getCounter('gp').value, equals(100));

        // Normal increase
        final increased = base.setDenomination('gp', 150, replicaId: ReplicaId('r1'));
        expect(increased.getCounter('gp').value, equals(150));
        expect(increased.getBalance('gp'), equals(150));

        // Normal decrease
        final decreased = increased.setDenomination('gp', 80, replicaId: ReplicaId('r1'));
        expect(decreased.getCounter('gp').value, equals(80));
        expect(decreased.getBalance('gp'), equals(80));

        // Zero
        final zeroed = decreased.setDenomination('gp', 0, replicaId: ReplicaId('r1'));
        expect(zeroed.getCounter('gp').value, equals(0));
        expect(zeroed.getBalance('gp'), equals(0));

        // Repeated set to same target is idempotent locally
        final repeated = zeroed.setDenomination('gp', 0, replicaId: ReplicaId('r1'));
        expect(identical(repeated, zeroed), isTrue);
      });
    });

    group('F. PartyPurse Legacy Migration — Remove "cloud" Repair Writes', () {
      test('1. counter + matching scalar -> counter unchanged', () {
        final input = {
          'gp': 100,
          'gpCounter': {
            'positive': {'nodeA': 100},
            'negative': <String, int>{},
          },
        };
        final purse = PartyPurse.fromMap(input);
        expect(purse.getCounter('gp').positive, equals({'nodeA': 100}));
        expect(purse.getCounter('gp').negative, isEmpty);
      });

      test('2. counter + mismatching higher scalar -> counter unchanged (no cloud write)', () {
        final input = {
          'gp': 150, // higher than counter
          'gpCounter': {
            'positive': {'nodeA': 100},
            'negative': <String, int>{},
          },
        };
        final purse = PartyPurse.fromMap(input);
        expect(purse.getCounter('gp').value, equals(100));
        expect(purse.getCounter('gp').positive.containsKey('cloud'), isFalse);
      });

      test('3. counter + mismatching lower scalar -> counter unchanged (no cloud write)', () {
        final input = {
          'gp': 50, // lower than counter
          'gpCounter': {
            'positive': {'nodeA': 100},
            'negative': <String, int>{},
          },
        };
        final purse = PartyPurse.fromMap(input);
        expect(purse.getCounter('gp').value, equals(100));
        expect(purse.getCounter('gp').negative.containsKey('cloud'), isFalse);
      });

      test('4. scalar-only legacy value -> deterministic migrated counter with "init"', () {
        final input = {'gp': 250};
        final purse = PartyPurse.fromMap(input);
        expect(purse.getCounter('gp').value, equals(250));
        expect(purse.getCounter('gp').positive, equals({'init': 250}));
      });

      test('5. old saved counter containing "cloud" -> preserved exactly as historical data', () {
        final input = {
          'gpCounter': {
            'positive': {'nodeA': 100, 'cloud': 25},
            'negative': {'cloud': 10},
          },
        };
        final purse = PartyPurse.fromMap(input);
        expect(purse.getCounter('gp').positive['cloud'], equals(25));
        expect(purse.getCounter('gp').negative['cloud'], equals(10));
        expect(purse.getCounter('gp').value, equals(115));
      });

      test('6. round trip does not manufacture additional components', () {
        final original = const PartyPurse.empty().setDenomination('gp', 100, replicaId: ReplicaId('nodeA'));
        final map = original.toMap();
        final restored = PartyPurse.fromMap(map);
        expect(restored.getCounter('gp').positive.keys, equals(['nodeA']));
        expect(restored.getCounter('gp').negative.keys, isEmpty);
      });
    });

    group('G. HLC Deserialization Determinism', () {
      test('fromMap fails loudly when pt/physicalTime is missing or invalid', () {
        expect(() => HybridLogicalClock.fromMap({'node': 'n1'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'node': 'n1', 'pt': 'invalid'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'node': 'n1', 'physicalTime': null}), throwsA(isA<FormatException>()));
      });

      test('missing logical counter defaults deterministically to 0', () {
        final hlc = HybridLogicalClock.fromMap({'node': 'n1', 'pt': 1000});
        expect(hlc.logicalCounter, equals(0));
        expect(hlc.physicalTime, equals(1000));
        expect(hlc.nodeId, equals('n1'));
      });

      test('malformed payload throws deterministically at any point in time', () {
        final malformed = {'node': 'test-node'};
        expect(() => HybridLogicalClock.fromMap(malformed), throwsA(isA<FormatException>()));
      });
    });

    group('H. HLC Ordering Laws', () {
      test('HLC total order laws', () {
        const c1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 1, nodeId: 'nodeA');
        const c2 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 1, nodeId: 'nodeB');
        const c3 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');

        // Reflexivity
        expect(c1.compareTo(c1), equals(0));

        // Antisymmetry
        expect(c1.compareTo(c2) < 0, isTrue);
        expect(c2.compareTo(c1) > 0, isTrue);
        expect(c1.compareTo(c2), equals(-c2.compareTo(c1)));

        // Transitivity: c1 < c2 and c2 < c3 => c1 < c3
        expect(c2.compareTo(c3) < 0, isTrue);
        expect(c1.compareTo(c3) < 0, isTrue);

        // Serialization round trip preserves ordering
        final c1Round = HybridLogicalClock.fromMap(c1.toMap());
        final c2Round = HybridLogicalClock.fromMap(c2.toMap());
        expect(c1Round.compareTo(c2Round), equals(c1.compareTo(c2)));
      });
    });

    group('I. LWW Register Exact-Timestamp Collisions', () {
      test('same timestamp + equal value is idempotent', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const r1 = CrdtLwwRegister<String>(value: 'V1', timestamp: ts);
        const r2 = CrdtLwwRegister<String>(value: 'V1', timestamp: ts);

        expect(r1.merge(r2), equals(r1));
        expect(r2.merge(r1), equals(r2));
      });

      test('same timestamp + different value fails loudly and symmetrically with StateError', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const r1 = CrdtLwwRegister<String>(value: 'V1', timestamp: ts);
        const r2 = CrdtLwwRegister<String>(value: 'V2', timestamp: ts);

        expect(() => r1.merge(r2), throwsA(isA<StateError>()));
        expect(() => r2.merge(r1), throwsA(isA<StateError>()));
      });

      test('distinct timestamps: later timestamp wins', () {
        const ts1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const ts2 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeB');
        const r1 = CrdtLwwRegister<String>(value: 'V1', timestamp: ts1);
        const r2 = CrdtLwwRegister<String>(value: 'V2', timestamp: ts2);

        expect(r1.merge(r2).value, equals('V2'));
        expect(r2.merge(r1).value, equals('V2'));
      });
    });

    group('J & K. OR-Set Exact-Timestamp Add-Wins & Collision Policy', () {
      test('1. equal timestamp add vs tombstone -> add wins', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        final itemSet = const CrdtOrSet<String>.empty().add('item-1', 'Sword', ts);
        final tombSet = const CrdtOrSet<String>.empty().remove('item-1', ts);

        final merged = itemSet.merge(tombSet);
        expect(merged.activeValues, equals(['Sword']));
        expect(merged.tombstones.containsKey('item-1'), isFalse);
      });

      test('2. merge(item, tombstone) == merge(tombstone, item)', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        final itemSet = const CrdtOrSet<String>.empty().add('item-1', 'Shield', ts);
        final tombSet = const CrdtOrSet<String>.empty().remove('item-1', ts);

        final m1 = itemSet.merge(tombSet);
        final m2 = tombSet.merge(itemSet);
        expect(m1, equals(m2));
      });

      test('3. equal timestamp remove against existing item does not defeat the add', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        final itemSet = const CrdtOrSet<String>.empty().add('item-1', 'Bow', ts);
        final afterRemove = itemSet.remove('item-1', ts);

        expect(afterRemove.activeValues, equals(['Bow']));
        expect(afterRemove.tombstones.containsKey('item-1'), isFalse);
      });

      test('4. newer remove wins', () {
        const tsAdd = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const tsRem = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeB');
        final itemSet = const CrdtOrSet<String>.empty().add('item-1', 'Staff', tsAdd);
        final tombSet = const CrdtOrSet<String>.empty().remove('item-1', tsRem);

        final merged = itemSet.merge(tombSet);
        expect(merged.activeValues, isEmpty);
        expect(merged.tombstones['item-1'], equals(tsRem));
      });

      test('5. newer re-add wins', () {
        const tsRem = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const tsAdd = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeB');
        final tombSet = const CrdtOrSet<String>.empty().remove('item-1', tsRem);
        final reAddSet = tombSet.add('item-1', 'Revived Staff', tsAdd);

        expect(reAddSet.activeValues, equals(['Revived Staff']));
        expect(reAddSet.tombstones.containsKey('item-1'), isFalse);
      });

      test('6. no merge result contains logically contradictory active item/tombstone state', () {
        const ts1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        const ts2 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeB');
        final s1 = const CrdtOrSet<String>.empty().add('item-1', 'Dagger', ts1);
        final s2 = const CrdtOrSet<String>.empty().remove('item-1', ts2);

        final merged = s1.merge(s2);
        final contradictory = merged.items.containsKey('item-1') && merged.tombstones.containsKey('item-1');
        expect(contradictory, isFalse);
      });

      test('K. identical timestamp divergent item values fail loudly and symmetrically', () {
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
        final s1 = const CrdtOrSet<String>.empty().add('item-1', 'Potion of Healing', ts);
        final s2 = const CrdtOrSet<String>.empty().add('item-1', 'Potion of Poison', ts);

        expect(() => s1.merge(s2), throwsA(isA<StateError>()));
        expect(() => s2.merge(s1), throwsA(isA<StateError>()));
      });
    });

    group('L. Deterministic Randomized CRDT Lattice Law Tests', () {
      test('PnCounter lattice laws (idempotence, commutativity, associativity) over $iterations iterations', () {
        const effectiveSeed = seed ^ 1;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          PnCounter randomCounter() {
            final pos = <String, int>{};
            final neg = <String, int>{};
            for (var n = 0; n < 3; n++) {
              if (rng.nextBool()) pos['node-$n'] = rng.nextInt(500);
              if (rng.nextBool()) neg['node-$n'] = rng.nextInt(500);
            }
            return PnCounter(positive: pos, negative: neg);
          }

          final a = randomCounter();
          final b = randomCounter();
          final c = randomCounter();

          // Idempotence: a ⊔ a == a
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');

          // Commutativity: a ⊔ b == b ⊔ a
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');

          // Associativity: (a ⊔ b) ⊔ c == a ⊔ (b ⊔ c)
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
        }
      });

      test('CrdtLwwRegister lattice laws over $iterations iterations for valid distinct writes', () {
        const effectiveSeed = seed ^ 2;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          final pt1 = 1000 + rng.nextInt(1000);
          final pt2 = 1000 + rng.nextInt(1000);
          final lc1 = rng.nextInt(10);
          final lc2 = rng.nextInt(10);
          final node1 = 'node-${rng.nextInt(5)}';
          final node2 = 'node-${rng.nextInt(5)}';

          final ts1 = HybridLogicalClock(physicalTime: pt1, logicalCounter: lc1, nodeId: node1);
          final ts2 = HybridLogicalClock(physicalTime: pt2, logicalCounter: lc2, nodeId: node2);

          final val1 = 'val-$pt1-$lc1-$node1';
          final val2 = (ts1 == ts2) ? val1 : 'val-$pt2-$lc2-$node2';

          final r1 = CrdtLwwRegister<String>(value: val1, timestamp: ts1);
          final r2 = CrdtLwwRegister<String>(value: val2, timestamp: ts2);

          // Idempotence
          expect(r1.merge(r1), equals(r1), reason: 'seed: $effectiveSeed, iter: $i, r1: $r1');

          // Commutativity
          expect(r1.merge(r2), equals(r2.merge(r1)),
              reason: 'seed: $effectiveSeed, iter: $i, r1: $r1, r2: $r2');
        }
      });

      test('CrdtOrSet lattice laws (idempotence, commutativity, associativity) over $iterations iterations', () {
        const effectiveSeed = seed ^ 3;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          CrdtOrSet<String> randomSet() {
            var s = const CrdtOrSet<String>.empty();
            for (var k = 0; k < 4; k++) {
              final id = 'item-$k';
              final pt = 1000 + rng.nextInt(500);
              final ts = HybridLogicalClock(physicalTime: pt, logicalCounter: 0, nodeId: 'node-0');
              if (rng.nextBool()) {
                s = s.add(id, 'Payload-$id', ts);
              } else {
                s = s.remove(id, ts);
              }
            }
            return s;
          }

          final a = randomSet();
          final b = randomSet();
          final c = randomSet();

          // Idempotence
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');

          // Commutativity
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');

          // Associativity
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
        }
      });

      test('PartyPurse lattice laws (idempotence, commutativity, associativity) over $iterations iterations', () {
        const effectiveSeed = seed ^ 4;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          PartyPurse randomPurse() {
            final counters = <String, PnCounter>{};
            for (final denom in ['cp', 'sp', 'ep', 'gp', 'pp', 'credits']) {
              final pos = <String, int>{};
              final neg = <String, int>{};
              for (var n = 0; n < 2; n++) {
                if (rng.nextBool()) pos['node-$n'] = rng.nextInt(100);
                if (rng.nextBool()) neg['node-$n'] = rng.nextInt(100);
              }
              counters[denom] = PnCounter(positive: pos, negative: neg);
            }
            return PartyPurse.fromCounters(counters);
          }

          final a = randomPurse();
          final b = randomPurse();
          final c = randomPurse();

          // Idempotence
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');

          // Commutativity
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');

          // Associativity
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
        }
      });
    });

    group('M. Serialization Law Tests', () {
      test('PnCounter round-trip preserves negative mathematical value', () {
        final counter = PnCounter(
          positive: {'nodeA': 50},
          negative: {'nodeB': 80},
        );
        expect(counter.value, equals(-30));
        final roundTrip = PnCounter.fromMap(counter.toMap());
        expect(roundTrip, equals(counter));
        expect(roundTrip.value, equals(-30));
      });

      test('PnCounter round-trip preserves multiple writer components in different insertion orders', () {
        final c1 = PnCounter(
          positive: {'z': 10, 'a': 20},
          negative: {'y': 5, 'b': 15},
        );
        final restored = PnCounter.fromMap(c1.toMap());
        expect(restored, equals(c1));
      });

      test('HLC serialization round-trip', () {
        const hlc = HybridLogicalClock(physicalTime: 1700000000000, logicalCounter: 42, nodeId: 'node-sync-1');
        final roundTrip = HybridLogicalClock.fromMap(hlc.toMap());
        expect(roundTrip, equals(hlc));
      });

      test('CrdtOrSet serialization round-trip', () {
        const t1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'nA');
        const t2 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'nB');
        final set = const CrdtOrSet<String>.empty()
            .add('item-1', 'Sword', t1)
            .remove('item-2', t2);

        final map = set.toMap((v) => v);
        final roundTrip = CrdtOrSet<String>.fromMap(map, (v) => v.toString());
        expect(roundTrip, equals(set));
      });

      test('PartyPurse serialization round-trip preserves negative underlying counters', () {
        final purse = PartyPurse.fromCounters({
          'gp': PnCounter(positive: {'nA': 10}, negative: {'nB': 30}), // value -20
          'credits': PnCounter(positive: {'nA': 500}, negative: const {}),
        });
        expect(purse.getCounter('gp').value, equals(-20));
        expect(purse.getBalance('gp'), equals(0));

        final map = purse.toMap();
        final restored = PartyPurse.fromMap(map);
        expect(restored, equals(purse));
        expect(restored.getCounter('gp').value, equals(-20));
        expect(restored.getBalance('gp'), equals(0));
        expect(restored.getBalance('credits'), equals(500));
      });
    });
  });
}
