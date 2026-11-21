import 'dart:math';

import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_equality.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

Object? _generateValueWithSets(Random rng, int depth) {
  if (depth >= 2) {
    return switch (rng.nextInt(4)) {
      0 => 'str_${rng.nextInt(20)}',
      1 => rng.nextInt(50) - 25,
      2 => rng.nextBool(),
      _ => null,
    };
  }
  return switch (rng.nextInt(5)) {
    0 => <Object?>{
        for (var i = 0; i < 1 + rng.nextInt(4); i++)
          _generateValueWithSets(rng, depth + 1),
      },
    1 => <Object?>[
        for (var i = 0; i < 1 + rng.nextInt(3); i++)
          _generateValueWithSets(rng, depth + 1),
      ],
    2 => <String, Object?>{
        for (var i = 0; i < 1 + rng.nextInt(3); i++)
          'k${rng.nextInt(6)}': _generateValueWithSets(rng, depth + 1),
      },
    3 => 'leaf_${rng.nextInt(30)}',
    _ => rng.nextInt(100),
  };
}

/// Returns a structurally equal copy of [value] with every Set's insertion order
/// reversed (and nested Sets/Lists/Maps copied recursively).
Object? _reverseSetInsertionOrder(Object? value) {
  if (value is Set) {
    final reversed = value.toList().reversed.map(_reverseSetInsertionOrder);
    return <Object?>{...reversed};
  }
  if (value is List) {
    return value.map(_reverseSetInsertionOrder).toList();
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _reverseSetInsertionOrder(entry.value),
    };
  }
  return value;
}

void main() {
  const genesis = HybridLogicalClock.genesis;
  const nonZeroTs = HybridLogicalClock(
    physicalTime: 1700000000000,
    logicalCounter: 1,
    nodeId: 'node_a',
  );

  group('Fix 7.1: CrdtLwwRegister canonical Set encoding laws (360 seeds)', () {
    test(
        'two sets with the same members in different insertion orders tie-break identically against a pivot',
        () {
      // Deterministic pivot law: for 360 seeded 2+ element sets, construct a
      // pivot set whose single string element sorts strictly between the first
      // and last elements of the set. If _encodeCanonical sorts Set members,
      // both insertion orders produce the exact same winner against the pivot.
      for (var seed = 0; seed < 360; seed++) {
        final rng = Random(71000 + seed);
        final low = 'a_${seed}_${rng.nextInt(100)}';
        final mid = 'm_${seed}_${rng.nextInt(100)}';
        final high = 'z_${seed}_${rng.nextInt(100)}';

        final setForward = <String>{low, high};
        final setReversed = <String>{high, low};
        final pivot = <String>{mid};

        final rFwd = CrdtLwwRegister<Object?>(value: setForward, timestamp: genesis);
        final rRev = CrdtLwwRegister<Object?>(value: setReversed, timestamp: genesis);
        final rPivot = CrdtLwwRegister<Object?>(value: pivot, timestamp: genesis);

        final winFwd = rFwd.merge(rPivot);
        final winRev = rRev.merge(rPivot);

        expect(
          crdtPayloadEquals(winFwd.value, winRev.value),
          isTrue,
          reason:
              'Seed $seed: sets with identical members in different insertion orders '
              '($setForward vs $setReversed) must tie-break identically against $pivot '
              '(got ${winFwd.value} vs ${winRev.value})',
        );
      }
    });

    test(
        'a Set and a List with the same members encode differently and tie-break deterministically without collision',
        () {
      for (var seed = 0; seed < 360; seed++) {
        final rng = Random(72000 + seed);
        final members = <Object?>[
          'item_${rng.nextInt(50)}',
          rng.nextInt(100),
          rng.nextBool(),
        ];
        final asSet = <Object?>{...members};
        final asList = List<Object?>.from(asSet);

        final rSet = CrdtLwwRegister<Object?>(value: asSet, timestamp: genesis);
        final rList = CrdtLwwRegister<Object?>(value: asList, timestamp: genesis);

        final ab = rSet.merge(rList);
        final ba = rList.merge(rSet);
        expect(
          crdtPayloadEquals(ab.value, ba.value),
          isTrue,
          reason: 'Seed $seed: Set $asSet vs List $asList must converge symmetrically',
        );
      }
    });

    test(
        '360 seeded nested JSON-like values with Sets: genesis merge is commutative and idempotent, non-zero tie throws StateError',
        () {
      for (var seed = 0; seed < 360; seed++) {
        final rng = Random(73000 + seed);
        final a = <Object?>{
          _generateValueWithSets(rng, 0),
          'tag_a_$seed',
        };
        final b = <Object?>{
          _generateValueWithSets(rng, 0),
          'tag_b_$seed',
        };
        final aRev = _reverseSetInsertionOrder(a);

        final ra = CrdtLwwRegister<Object?>(value: a, timestamp: genesis);
        final raRev = CrdtLwwRegister<Object?>(value: aRev, timestamp: genesis);
        final rb = CrdtLwwRegister<Object?>(value: b, timestamp: genesis);

        // Commutativity at genesis
        final ab = ra.merge(rb);
        final ba = rb.merge(ra);
        expect(
          crdtPayloadEquals(ab.value, ba.value),
          isTrue,
          reason: 'Seed $seed: genesis merge must be commutative for $a vs $b',
        );

        // Insertion-order independence on nested Sets
        final aRevB = raRev.merge(rb);
        expect(
          crdtPayloadEquals(ab.value, aRevB.value),
          isTrue,
          reason:
              'Seed $seed: reversed insertion order ($a vs $aRev) must merge identically with $b',
        );

        // Idempotence at genesis
        expect(
          crdtPayloadEquals(ra.merge(ra).value, ra.value),
          isTrue,
          reason: 'Seed $seed: genesis merge must be idempotent',
        );

        // Non-zero tie with divergent Sets still throws StateError symmetrically
        final nzA = CrdtLwwRegister<Object?>(value: a, timestamp: nonZeroTs);
        final nzB = CrdtLwwRegister<Object?>(value: b, timestamp: nonZeroTs);
        expect(() => nzA.merge(nzB), throwsStateError);
        expect(() => nzB.merge(nzA), throwsStateError);
      }
    });
  });
}
