import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_equality.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

void main() {
  group('CrdtLwwRegister Genesis Tie Laws & Canonical Ordering', () {
    const genesis = HybridLogicalClock.genesis;

    test('Five example pairs are commutative at genesis with identical value & runtime type', () {
      final pairs = <(Object?, Object?)>[
        (null, 'null'),
        (1, '1'),
        (true, 'true'),
        ([1], '[1]'),
        ({'a': 1}, '{"a":1}'),
      ];

      for (final (a, b) in pairs) {
        final regA = CrdtLwwRegister<Object?>(value: a, timestamp: genesis);
        final regB = CrdtLwwRegister<Object?>(value: b, timestamp: genesis);

        final ab = regA.merge(regB);
        final ba = regB.merge(regA);

        expect(ab.timestamp, equals(genesis));
        expect(ba.timestamp, equals(genesis));
        expect(ab.value, equals(ba.value), reason: 'Failed value commutativity for pair ($a, $b)');
        expect(ab.value.runtimeType, equals(ba.value.runtimeType),
            reason: 'Failed runtimeType commutativity for pair ($a, $b)');
      }
    });

    test('String-order regression: 500 seeded random string pairs match plain String.compareTo', () {
      final rand = Random(1337);

      String randomString(Random r) {
        const chars = 'abcdefghijklmnopqrstuvwxyz0123456789-_ /:{}[]"';
        final len = r.nextInt(15);
        return String.fromCharCodes(
          Iterable.generate(len, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
        );
      }

      for (int i = 0; i < 500; i++) {
        final s1 = randomString(rand);
        final s2 = randomString(rand);

        final r1 = CrdtLwwRegister<String>(value: s1, timestamp: genesis);
        final r2 = CrdtLwwRegister<String>(value: s2, timestamp: genesis);

        final m12 = r1.merge(r2);
        final m21 = r2.merge(r1);

        expect(m12.value, equals(m21.value), reason: 'Iteration $i: string merge not commutative');
        final expected = s1.compareTo(s2) >= 0 ? s1 : s2;
        expect(m12.value, equals(expected), reason: 'Iteration $i: string merge did not match String.compareTo');
      }
    });

    test('1,000 seeded random property tests over mixed JSON-like values (depth <= 3)', () {
      final rand = Random(4242);

      const trickyStrings = [
        'null',
        '1',
        'true',
        'false',
        '',
        '[1]',
        '{"a":1}',
        '0',
        '-1',
        '1.0',
        '[]',
        '{}',
      ];

      Object? generateValue(Random r, int depth) {
        if (depth <= 0) {
          final choice = r.nextInt(6);
          switch (choice) {
            case 0:
              return null;
            case 1:
              return r.nextBool();
            case 2:
              return r.nextInt(20) - 10;
            case 3:
              return (r.nextInt(20) - 10) * 0.5;
            case 4:
              return trickyStrings[r.nextInt(trickyStrings.length)];
            default:
              return 'str_${r.nextInt(50)}';
          }
        }

        final choice = r.nextInt(8);
        switch (choice) {
          case 0:
            return null;
          case 1:
            return r.nextBool();
          case 2:
            return r.nextInt(20) - 10;
          case 3:
            return (r.nextInt(20) - 10) * 0.5;
          case 4:
            return trickyStrings[r.nextInt(trickyStrings.length)];
          case 5:
            final len = r.nextInt(4);
            return List<Object?>.generate(len, (_) => generateValue(r, depth - 1));
          case 6:
            final len = r.nextInt(3);
            const keys = ['a', 'b', 'c', 'null', '1'];
            final map = <String, Object?>{};
            for (int k = 0; k < len; k++) {
              map[keys[r.nextInt(keys.length)]] = generateValue(r, depth - 1);
            }
            return map;
          default:
            return 'str_${r.nextInt(50)}';
        }
      }

      for (int i = 0; i < 1000; i++) {
        final valA = generateValue(rand, 3);
        final valB = generateValue(rand, 3);
        final valC = generateValue(rand, 3);

        final rA = CrdtLwwRegister<Object?>(value: valA, timestamp: genesis);
        final rB = CrdtLwwRegister<Object?>(value: valB, timestamp: genesis);
        final rC = CrdtLwwRegister<Object?>(value: valC, timestamp: genesis);

        // 1. Idempotence: merge(A, A) == A
        expect(rA.merge(rA).value, equals(rA.value), reason: 'Iteration $i: idempotence failed for A');
        expect(rB.merge(rB).value, equals(rB.value), reason: 'Iteration $i: idempotence failed for B');
        expect(rC.merge(rC).value, equals(rC.value), reason: 'Iteration $i: idempotence failed for C');

        // 2. Commutativity: merge(A, B) == merge(B, A) (or both throw StateError)
        Object? valAB;
        Object? valBA;
        bool threwAB = false;
        bool threwBA = false;

        try {
          valAB = rA.merge(rB).value;
        } on StateError {
          threwAB = true;
        }

        try {
          valBA = rB.merge(rA).value;
        } on StateError {
          threwBA = true;
        }

        expect(threwAB, equals(threwBA), reason: 'Iteration $i: symmetric error handling mismatch');
        if (!threwAB) {
          expect(crdtPayloadEquals(valAB, valBA), isTrue,
              reason: 'Iteration $i: commutativity failed: $valAB vs $valBA');
          // Result must be one of the inputs
          final isOneOfInputs = crdtPayloadEquals(valAB, valA) || crdtPayloadEquals(valAB, valB);
          expect(isOneOfInputs, isTrue, reason: 'Iteration $i: result was not one of the inputs');
        }

        // 3. Associativity: merge(merge(A, B), C) == merge(A, merge(B, C))
        if (!threwAB) {
          final rAB = rA.merge(rB);
          Object? valAbC;
          Object? valABc;
          bool threwAbC = false;
          bool threwABc = false;

          try {
            valAbC = rAB.merge(rC).value;
          } on StateError {
            threwAbC = true;
          }

          try {
            final rBC = rB.merge(rC);
            valABc = rA.merge(rBC).value;
          } on StateError {
            threwABc = true;
          }

          expect(threwAbC, equals(threwABc), reason: 'Iteration $i: associativity throw mismatch');
          if (!threwAbC) {
            expect(crdtPayloadEquals(valAbC, valABc), isTrue,
                reason: 'Iteration $i: associativity value mismatch: $valAbC vs $valABc');
          }
        }
      }
    });

    test('Control: divergent tie at non-zero timestamp still throws StateError', () {
      const nonZero = HybridLogicalClock(physicalTime: 100, logicalCounter: 0, nodeId: 'nodeA');
      const rA = CrdtLwwRegister<String>(value: 'A', timestamp: nonZero);
      const rB = CrdtLwwRegister<String>(value: 'B', timestamp: nonZero);

      expect(() => rA.merge(rB), throwsA(isA<StateError>()));
      expect(() => rB.merge(rA), throwsA(isA<StateError>()));
    });

    test('Control: tie at genesis with structurally equal values (keys in different order) returns without throwing', () {
      final r1 = CrdtLwwRegister<Map<String, dynamic>>(
        value: const {'a': 1, 'b': 2},
        timestamp: genesis,
      );
      final r2 = CrdtLwwRegister<Map<String, dynamic>>(
        value: const {'b': 2, 'a': 1},
        timestamp: genesis,
      );

      final merged1 = r1.merge(r2);
      final merged2 = r2.merge(r1);

      expect(merged1.value, equals(r1.value));
      expect(merged2.value, equals(r2.value));
    });
  });
}
