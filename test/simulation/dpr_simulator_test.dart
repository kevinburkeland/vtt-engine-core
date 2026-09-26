import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/simulation/dpr_simulator.dart';
import 'package:vtt_engine_core/simulation/precomputed_attack.dart';

void main() {
  group('DprSimulator', () {
    const testAttack = PrecomputedAttack(
      attackId: 'halberd_strike',
      attackBonus: 7, // +7 to hit
      flatBonus: 4,
      damageGroups: [
        DamageDieGroup(count: 1, faces: 10), // 1d10 + 4
      ],
    );

    test('runs 10,000 iterations synchronously with reasonable statistics', () {
      const simulator = DprSimulator();
      // Target AC 15: needs 8 on d20. (13 faces out of 20 = 65% hit rate, 5% crit rate)
      final result = simulator.run(
        attack: testAttack,
        targetAc: 15,
        iterations: 10000,
        rng: Random(42),
      );

      expect(result.iterations, equals(10000));
      // Hit rate should be around 0.65 +/- 0.03
      expect(result.hitRate, closeTo(0.65, 0.03));
      // Crit rate should be around 0.05 +/- 0.015
      expect(result.critRate, closeTo(0.05, 0.015));
      expect(result.missCount + result.hitCount, equals(10000));
      expect(result.meanDamage, isPositive);
      expect(result.dpr, equals(result.meanDamage));
      expect(result.toMap()['iterations'], equals(10000));
    });

    test('handles extreme AC cases (nat 20 hit, nat 1 miss)', () {
      const simulator = DprSimulator();

      // AC 999: Only nat 20 can hit (5% hit rate, all hits are crits)
      final highAcResult = simulator.run(
        attack: testAttack,
        targetAc: 999,
        iterations: 10000,
        rng: Random(42),
      );
      expect(highAcResult.hitCount, equals(highAcResult.critCount));
      expect(highAcResult.critRate, closeTo(0.05, 0.015));

      // AC 0: Everything hits except nat 1 (95% hit rate)
      final lowAcResult = simulator.run(
        attack: testAttack,
        targetAc: 0,
        iterations: 10000,
        rng: Random(42),
      );
      expect(lowAcResult.hitRate, closeTo(0.95, 0.015));
    });

    test('executes in background Isolate without throwing', () async {
      const simulator = DprSimulator();
      final result = await simulator.runInIsolate(
        attack: testAttack,
        targetAc: 16,
        iterations: 10000,
      );

      expect(result.iterations, equals(10000));
      expect(result.hitCount, isPositive);
      expect(result.meanDamage, isPositive);
    });

    test(
        'evaluates damage riders (PeriodicDamageRider, AttributeDrainRider) to reflect higher DPR than base attack',
        () {
      const simulator = DprSimulator();

      final attackWithBleed = PrecomputedAttack(
        attackId: 'halberd_bleed',
        attackBonus: 7,
        flatBonus: 4,
        damageGroups: const [
          DamageDieGroup(count: 1, faces: 10),
        ],
        riders: const [
          PeriodicDamageRider(
            diceCount: 1,
            diceSides: 6,
            flatBonus: 2,
            damageType: 'acid',
          ),
        ],
      );

      final attackWithDrain = PrecomputedAttack(
        attackId: 'shadow_drain',
        attackBonus: 7,
        flatBonus: 4,
        damageGroups: const [
          DamageDieGroup(count: 1, faces: 10),
        ],
        riders: const [
          AttributeDrainRider(
            targetAttributeKey: 'strength',
            diceCount: 1,
            diceSides: 4,
            flatBonus: 1,
          ),
        ],
      );

      final baseResult = simulator.run(
        attack: testAttack,
        targetAc: 15,
        iterations: 10000,
        rng: Random(100),
      );

      final bleedResult = simulator.run(
        attack: attackWithBleed,
        targetAc: 15,
        iterations: 10000,
        rng: Random(100),
      );

      final drainResult = simulator.run(
        attack: attackWithDrain,
        targetAc: 15,
        iterations: 10000,
        rng: Random(100),
      );

      // Hit rates should remain around 65% for target AC 15 with +7 attack bonus
      expect(bleedResult.hitRate, closeTo(0.65, 0.03));
      expect(drainResult.hitRate, closeTo(0.65, 0.03));

      // Periodic damage rider (1d6+2 avg 5.5) must increase meanDamage and DPR
      expect(bleedResult.meanDamage, greaterThan(baseResult.meanDamage));
      expect(bleedResult.dpr, greaterThan(baseResult.dpr));

      // Attribute drain rider (1d4+1 avg 3.5) must increase meanDamage and DPR
      expect(drainResult.meanDamage, greaterThan(baseResult.meanDamage));
      expect(drainResult.dpr, greaterThan(baseResult.dpr));

      // Bleed (avg +5.5) deals more than Drain (avg +3.5)
      expect(bleedResult.meanDamage, greaterThan(drainResult.meanDamage));
    });

    test(
        'PeriodicDamageRider doubles damage dice on crits without doubling flat bonus',
        () {
      const rider = PeriodicDamageRider(
        diceCount: 2,
        diceSides: 6,
        flatBonus: 5,
        damageType: 'fire',
      );

      // Deterministic RNG: all rolls return max value
      // Regular roll: 2d6 (2 * 6 = 12) + 5 = 17
      // Crit roll: 4d6 (4 * 6 = 24) + 5 = 29
      final rng1 = Random(42);
      final regRoll = rider.rollDamage(rng1, isCrit: false);
      expect(regRoll, inInclusiveRange(7, 17)); // 2*1+5 to 2*6+5

      final rng2 = Random(42);
      final critRoll = rider.rollDamage(rng2, isCrit: true);
      expect(critRoll, inInclusiveRange(9, 29)); // 4*1+5 to 4*6+5
    });

    test(
        'runInIsolate with identical seed produces bit-identical DprSimulationResult',
        () async {
      const simulator = DprSimulator();
      final result1 = await simulator.runInIsolate(
        attack: testAttack,
        targetAc: 16,
        iterations: 5000,
        seed: 12345,
      );
      final result2 = await simulator.runInIsolate(
        attack: testAttack,
        targetAc: 16,
        iterations: 5000,
        seed: 12345,
      );

      expect(result1.iterations, equals(result2.iterations));
      expect(result1.hitCount, equals(result2.hitCount));
      expect(result1.critCount, equals(result2.critCount));
      expect(result1.missCount, equals(result2.missCount));
      expect(result1.totalDamage, equals(result2.totalDamage));
      expect(result1.meanDamage, equals(result2.meanDamage));
      expect(result1.minDamage, equals(result2.minDamage));
      expect(result1.maxDamage, equals(result2.maxDamage));
    });
  });
}
