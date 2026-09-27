import 'dart:math';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../models/generic_tabletop_primitives.dart';

bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);
bool _setEquals<T>(Set<T>? a, Set<T>? b) => const SetEquality().equals(a, b);

/// Abstract attack declaration decoupled from system-specific calculations.
@immutable
class AttackIntent {
  final int attackBonus;
  final String damageExpression;
  final String damageType;
  final int critThreshold;
  final List<CombatRiderDefinition> riders;
  final Map<String, dynamic> metadata;

  const AttackIntent({
    required this.attackBonus,
    required this.damageExpression,
    this.damageType = 'untyped',
    this.critThreshold = 20,
    this.riders = const [],
    this.metadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttackIntent &&
          attackBonus == other.attackBonus &&
          damageExpression == other.damageExpression &&
          damageType == other.damageType &&
          critThreshold == other.critThreshold &&
          const ListEquality<CombatRiderDefinition>()
              .equals(riders, other.riders) &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        attackBonus,
        damageExpression,
        damageType,
        critThreshold,
        const ListEquality<CombatRiderDefinition>().hash(riders),
        const MapEquality<String, dynamic>().hash(metadata),
      );
}

/// Abstract target defense profile decoupled from specific rulesets.
@immutable
class TargetDefenseProfile {
  final int targetDefenseRating; // e.g. Target defense value or dodge rating
  final Set<String> resistances;
  final Set<String> vulnerabilities;
  final Set<String> immunities;
  final Set<String> activeConditions;
  final Map<String, dynamic> metadata;

  const TargetDefenseProfile({
    required this.targetDefenseRating,
    this.resistances = const {},
    this.vulnerabilities = const {},
    this.immunities = const {},
    this.activeConditions = const {},
    this.metadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetDefenseProfile &&
          targetDefenseRating == other.targetDefenseRating &&
          _setEquals(resistances, other.resistances) &&
          _setEquals(vulnerabilities, other.vulnerabilities) &&
          _setEquals(immunities, other.immunities) &&
          _setEquals(activeConditions, other.activeConditions) &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        targetDefenseRating,
        const SetEquality<String>().hash(resistances),
        const SetEquality<String>().hash(vulnerabilities),
        const SetEquality<String>().hash(immunities),
        const SetEquality<String>().hash(activeConditions),
        const MapEquality<String, dynamic>().hash(metadata),
      );
}

enum AttackOutcomeType { miss, hit, criticalHit, criticalMiss }

/// Generic structured resolution of an attack roll and its rider effects.
@immutable
class AttackResolution {
  final AttackOutcomeType outcome;
  final int naturalRoll;
  final int totalToHit;
  final int damageDealt;
  final List<String> triggeredRiderLogs;

  const AttackResolution({
    required this.outcome,
    required this.naturalRoll,
    required this.totalToHit,
    required this.damageDealt,
    this.triggeredRiderLogs = const [],
  });

  bool get isHit =>
      outcome == AttackOutcomeType.hit ||
      outcome == AttackOutcomeType.criticalHit;

  bool get isCrit => outcome == AttackOutcomeType.criticalHit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttackResolution &&
          outcome == other.outcome &&
          naturalRoll == other.naturalRoll &&
          totalToHit == other.totalToHit &&
          damageDealt == other.damageDealt &&
          const ListEquality<String>()
              .equals(triggeredRiderLogs, other.triggeredRiderLogs);

  @override
  int get hashCode => Object.hash(
        outcome,
        naturalRoll,
        totalToHit,
        damageDealt,
        const ListEquality<String>().hash(triggeredRiderLogs),
      );
}

/// Abstract Combat Resolver port decoupled from system-specific rules math.
abstract interface class ICombatResolver {
  /// Evaluates an attack roll against target defense with the provided RNG stream.
  AttackResolution resolveAttack({
    required AttackIntent attack,
    required TargetDefenseProfile defense,
    required Random rng,
  });

  /// Evaluates a damage expression (e.g. '1d8+3' or flat scalar).
  int rollDamage({
    required String damageExpression,
    required bool isCrit,
    required Random rng,
  });

  /// Evaluates changes to entity vitals under the ruleset (damage, healing, downed, death).
  VitalsModification resolveVitalsChange({
    required EntityVitals currentVitals,
    required int delta,
    bool allowRevive = false,
  });
}
