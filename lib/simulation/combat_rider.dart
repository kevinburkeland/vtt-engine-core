import 'dart:math';
import 'package:meta/meta.dart';
import '../models/condition.dart';

/// Pure domain Abstract Syntax Tree (AST) representing an effect rider attached
/// to a precomputed combat action.
///
/// Fully decoupled from Flutter, regex parsers, and system-specific enums for zero-allocation
/// execution within Monte Carlo simulation loops.
@immutable
sealed class CombatEffectRider {
  const CombatEffectRider();
}

/// Applies an [ArenaCondition] to the target, optionally contingent upon a saving throw.
@immutable
class ConditionRider extends CombatEffectRider {
  final ArenaCondition condition;
  final bool requiresSave;
  final int? saveDc;
  final String? saveAttributeKey;

  const ConditionRider({
    required this.condition,
    this.requiresSave = false,
    this.saveDc,
    this.saveAttributeKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditionRider &&
          runtimeType == other.runtimeType &&
          condition == other.condition &&
          requiresSave == other.requiresSave &&
          saveDc == other.saveDc &&
          saveAttributeKey == other.saveAttributeKey;

  @override
  int get hashCode =>
      Object.hash(condition, requiresSave, saveDc, saveAttributeKey);
}

/// Drains an attribute score (e.g. Physique or Stamina).
/// If [deathAtZero] is true, the target dies immediately if reduced to 0.
@immutable
class AttributeDrainRider extends CombatEffectRider {
  final String targetAttributeKey;
  final int diceCount;
  final int diceSides;
  final int flatBonus;
  final bool deathAtZero;

  const AttributeDrainRider({
    required this.targetAttributeKey,
    this.diceCount = 0,
    this.diceSides = 0,
    this.flatBonus = 0,
    this.deathAtZero = true,
  });

  int rollDrain(Random rng) {
    var total = flatBonus;
    for (var i = 0; i < diceCount; i++) {
      total += rng.nextInt(diceSides) + 1;
    }
    return total;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributeDrainRider &&
          runtimeType == other.runtimeType &&
          targetAttributeKey == other.targetAttributeKey &&
          diceCount == other.diceCount &&
          diceSides == other.diceSides &&
          flatBonus == other.flatBonus &&
          deathAtZero == other.deathAtZero;

  @override
  int get hashCode => Object.hash(
      targetAttributeKey, diceCount, diceSides, flatBonus, deathAtZero);
}

/// Reduces target's maximum hit points.
/// If [reductionEqualsDamage] is true, reduction equals damage taken from attack.
@immutable
class MaxHpReductionRider extends CombatEffectRider {
  final bool reductionEqualsDamage;
  final int? flatReduction;
  final bool deathAtZero;

  const MaxHpReductionRider({
    this.reductionEqualsDamage = true,
    this.flatReduction,
    this.deathAtZero = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaxHpReductionRider &&
          runtimeType == other.runtimeType &&
          reductionEqualsDamage == other.reductionEqualsDamage &&
          flatReduction == other.flatReduction &&
          deathAtZero == other.deathAtZero;

  @override
  int get hashCode =>
      Object.hash(reductionEqualsDamage, flatReduction, deathAtZero);
}

/// Forces target movement (e.g. reeling 25 ft straight toward the attacker).
@immutable
class ForcedMovementRider extends CombatEffectRider {
  final int pullDistanceFeet;
  final bool toMeleeReach;

  const ForcedMovementRider({
    required this.pullDistanceFeet,
    this.toMeleeReach = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForcedMovementRider &&
          runtimeType == other.runtimeType &&
          pullDistanceFeet == other.pullDistanceFeet &&
          toMeleeReach == other.toMeleeReach;

  @override
  int get hashCode => Object.hash(pullDistanceFeet, toMeleeReach);
}

/// Prevents the target from regaining hit points for a specified duration or until cured.
@immutable
class HealingSupressionRider extends CombatEffectRider {
  final Duration duration;
  final bool cureViaRemoveCurse;

  const HealingSupressionRider({
    this.duration = const Duration(hours: 24),
    this.cureViaRemoveCurse = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealingSupressionRider &&
          runtimeType == other.runtimeType &&
          duration == other.duration &&
          cureViaRemoveCurse == other.cureViaRemoveCurse;

  @override
  int get hashCode => Object.hash(duration, cureViaRemoveCurse);
}

/// Deals ongoing damage at start/end of target's turn.
@immutable
class PeriodicDamageRider extends CombatEffectRider {
  final int diceCount;
  final int diceSides;
  final int flatBonus;
  final String damageType;
  final bool onTurnStart;

  const PeriodicDamageRider({
    required this.diceCount,
    required this.diceSides,
    this.flatBonus = 0,
    required this.damageType,
    this.onTurnStart = true,
  });

  int rollDamage(Random rng, {bool isCrit = false}) {
    var total = flatBonus;
    final totalDice = isCrit ? diceCount * 2 : diceCount;
    for (var i = 0; i < totalDice; i++) {
      total += rng.nextInt(diceSides) + 1;
    }
    return total;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeriodicDamageRider &&
          runtimeType == other.runtimeType &&
          diceCount == other.diceCount &&
          diceSides == other.diceSides &&
          flatBonus == other.flatBonus &&
          damageType == other.damageType &&
          onTurnStart == other.onTurnStart;

  @override
  int get hashCode =>
      Object.hash(diceCount, diceSides, flatBonus, damageType, onTurnStart);
}
