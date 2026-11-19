import 'dart:math';

import 'package:test/test.dart';
import 'package:vtt_engine_core/simulation/combat_rider.dart';

void main() {
  group('CombatEffectRider', () {
    test('PeriodicDamageRider rolls dice and doubles dice on crit without doubling flat bonus', () {
      const rider = PeriodicDamageRider(
        diceCount: 2,
        diceSides: 6,
        flatBonus: 3,
        damageType: 'burn',
        onTurnStart: false,
      );

      final normalRng = Random(42);
      final critRng = Random(42);
      for (var i = 0; i < 100; i++) {
        final normal = rider.rollDamage(normalRng, isCrit: false);
        expect(normal, inInclusiveRange(2 + 3, 12 + 3));
        final crit = rider.rollDamage(critRng, isCrit: true);
        expect(crit, inInclusiveRange(4 + 3, 24 + 3));
      }

      const same = PeriodicDamageRider(
        diceCount: 2,
        diceSides: 6,
        flatBonus: 3,
        damageType: 'burn',
        onTurnStart: false,
      );
      const diff = PeriodicDamageRider(
        diceCount: 1,
        diceSides: 6,
        flatBonus: 3,
        damageType: 'burn',
        onTurnStart: false,
      );
      expect(rider, equals(same));
      expect(rider.hashCode, equals(same.hashCode));
      expect(rider, isNot(equals(diff)));
    });

    test('AttributeDrainRider rolls within bounds and compares by value', () {
      const rider = AttributeDrainRider(
        targetAttributeKey: 'might',
        diceCount: 1,
        diceSides: 4,
        flatBonus: 1,
        deathAtZero: true,
      );
      final rng = Random(7);
      for (var i = 0; i < 50; i++) {
        expect(rider.rollDrain(rng), inInclusiveRange(2, 5));
      }

      const same = AttributeDrainRider(
        targetAttributeKey: 'might',
        diceCount: 1,
        diceSides: 4,
        flatBonus: 1,
        deathAtZero: true,
      );
      expect(rider, equals(same));
      expect(rider.hashCode, equals(same.hashCode));
    });

    test('ConditionRider, MaxHpReductionRider, ForcedMovementRider, and HealingSupressionRider value equality', () {
      const cond1 = ConditionRider(condition: 'stunned', requiresSave: true, saveDc: 14, saveAttributeKey: 'grit');
      const cond2 = ConditionRider(condition: 'stunned', requiresSave: true, saveDc: 14, saveAttributeKey: 'grit');
      expect(cond1, equals(cond2));
      expect(cond1.hashCode, equals(cond2.hashCode));

      const hp1 = MaxHpReductionRider(reductionEqualsDamage: false, flatReduction: 5, deathAtZero: false);
      const hp2 = MaxHpReductionRider(reductionEqualsDamage: false, flatReduction: 5, deathAtZero: false);
      expect(hp1, equals(hp2));
      expect(hp1.hashCode, equals(hp2.hashCode));

      const move1 = ForcedMovementRider(pullDistanceFeet: 15, toMeleeReach: true);
      const move2 = ForcedMovementRider(pullDistanceFeet: 15, toMeleeReach: true);
      expect(move1, equals(move2));
      expect(move1.hashCode, equals(move2.hashCode));

      const heal1 = HealingSupressionRider(duration: Duration(hours: 1), cureViaRemoveCurse: false);
      const heal2 = HealingSupressionRider(duration: Duration(hours: 1), cureViaRemoveCurse: false);
      expect(heal1, equals(heal2));
      expect(heal1.hashCode, equals(heal2.hashCode));
    });
  });
}
