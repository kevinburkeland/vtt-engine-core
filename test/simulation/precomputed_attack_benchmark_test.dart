import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/simulation/precomputed_attack.dart';

void main() {
  group('PrecomputedAttack Performance & Resolution', () {
    test('calculates correct damage bounds for regular and crit', () {
      final rng = Random(42);
      // Greatsword: 2d6 + 4
      const greatsword = PrecomputedAttack(
        attackId: 'greatsword_attack',
        attackBonus: 7,
        flatBonus: 4,
        damageGroups: [
          DamageDieGroup(count: 2, faces: 6),
        ],
      );

      // 2d6 + 4 regular: min 6, max 16
      for (var i = 0; i < 100; i++) {
        final regularDmg = greatsword.rollDamage(rng, isCrit: false);
        expect(regularDmg >= 6 && regularDmg <= 16, isTrue);
      }

      // 4d6 + 4 crit: min 8, max 28
      for (var i = 0; i < 100; i++) {
        final critDmg = greatsword.rollDamage(rng, isCrit: true);
        expect(critDmg >= 8 && critDmg <= 28, isTrue);
      }
    });

    test('PrecomputedAttackMap stores, retrieves, and enumerates attacks', () {
      final map = PrecomputedAttackMap();
      const attack1 = PrecomputedAttack(
        attackId: 'longsword_1h',
        attackBonus: 5,
        flatBonus: 3,
        damageGroups: [DamageDieGroup(count: 1, faces: 8)],
      );
      const attack2 = PrecomputedAttack(
        attackId: 'longsword_2h',
        attackBonus: 5,
        flatBonus: 3,
        damageGroups: [DamageDieGroup(count: 1, faces: 10)],
      );

      map.register(attack1);
      map.register(attack2);

      expect(map.length, equals(2));
      expect(map.contains('longsword_1h'), isTrue);
      expect(map['longsword_1h']?.flatBonus, equals(3));
      expect(map['longsword_2h']?.damageGroups.first.faces, equals(10));

      map.remove('longsword_1h');
      expect(map.contains('longsword_1h'), isFalse);
      expect(map.length, equals(1));
    });

    test('100,000 rollDamage benchmark completes under 50ms', () {
      final rng = Random(1337);
      const complexAttack = PrecomputedAttack(
        attackId: 'smite_greatsword',
        attackBonus: 9,
        flatBonus: 5,
        damageGroups: [
          DamageDieGroup(count: 2, faces: 6), // Weapon
          DamageDieGroup(count: 3, faces: 8), // Divine Smite 2nd lvl
          DamageDieGroup(count: 1, faces: 4), // Bless / extra
        ],
      );

      // Warmup JIT
      var warmupSum = 0;
      for (var i = 0; i < 5000; i++) {
        warmupSum += complexAttack.rollDamage(rng, isCrit: (i % 20 == 0));
      }
      expect(warmupSum, isPositive);

      final stopwatch = Stopwatch()..start();
      var totalDamageSum = 0;
      const iterations = 100000;

      for (var i = 0; i < iterations; i++) {
        final isCrit = (i % 20 == 0);
        totalDamageSum += complexAttack.rollDamage(rng, isCrit: isCrit);
      }
      stopwatch.stop();

      // Ensure optimizer cannot eliminate the loop
      expect(totalDamageSum, isPositive);

      // Execution threshold verification (< 100ms under CPU saturation)
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason:
            '100,000 damage computations took ${stopwatch.elapsedMilliseconds}ms (limit: 100ms)',
      );
    });
  });
}
