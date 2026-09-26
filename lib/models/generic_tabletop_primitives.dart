import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);

/// Attribute definition and scoring rules for an agnostic tabletop system.
abstract interface class IAttributeSystem {
  /// Canonical keys for all attributes in the system (e.g. ['strength', 'dexterity', ...]).
  List<String> get attributeKeys;

  /// Short abbreviation for chips, badges, and headers (e.g. 'STR', 'DEX', 'POW', 'REF').
  String getAbbreviation(String key);

  /// Full human-readable display name (e.g. 'Strength', 'Power', 'Reflexes').
  String getDisplayName(String key);

  /// Calculates the effective modifier or check bonus from a raw attribute score.
  int calculateModifier(String key, int score);

  /// Standard array or default baseline attribute scores for the ruleset.
  Map<String, int> get standardArray;
}

/// Generic Trait, Proficiency, or Capability definition.
@immutable
class ITraitDefinition {
  final String id;
  final String name;
  final String
      category; // 'skill', 'feat', 'mastery', 'sense', 'special_quality'
  final String? governedAttribute;
  final Map<String, dynamic> properties;

  const ITraitDefinition({
    required this.id,
    required this.name,
    required this.category,
    this.governedAttribute,
    this.properties = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ITraitDefinition &&
          id == other.id &&
          name == other.name &&
          category == other.category &&
          governedAttribute == other.governedAttribute &&
          _mapEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        category,
        governedAttribute,
        const MapEquality<String, dynamic>().hash(properties),
      );
}

/// Generic Vitals model decoupling HP, Temp HP, Downed, and Dead states.
@immutable
class EntityVitals {
  final int currentHp;
  final int maxHp;
  final int temporaryHp;
  final bool isDowned;
  final bool isDead;
  final Map<String, int>
      auxiliaryPools; // e.g., stamina, mana, death saves, sanity

  const EntityVitals({
    required this.currentHp,
    required this.maxHp,
    this.temporaryHp = 0,
    this.isDowned = false,
    this.isDead = false,
    this.auxiliaryPools = const {},
  });

  EntityVitals copyWith({
    int? currentHp,
    int? maxHp,
    int? temporaryHp,
    bool? isDowned,
    bool? isDead,
    Map<String, int>? auxiliaryPools,
  }) {
    return EntityVitals(
      currentHp: currentHp ?? this.currentHp,
      maxHp: maxHp ?? this.maxHp,
      temporaryHp: temporaryHp ?? this.temporaryHp,
      isDowned: isDowned ?? this.isDowned,
      isDead: isDead ?? this.isDead,
      auxiliaryPools: auxiliaryPools != null
          ? Map.unmodifiable(auxiliaryPools)
          : this.auxiliaryPools,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityVitals &&
          currentHp == other.currentHp &&
          maxHp == other.maxHp &&
          temporaryHp == other.temporaryHp &&
          isDowned == other.isDowned &&
          isDead == other.isDead &&
          _mapEquals(auxiliaryPools, other.auxiliaryPools);

  @override
  int get hashCode => Object.hash(
        currentHp,
        maxHp,
        temporaryHp,
        isDowned,
        isDead,
        const MapEquality<String, int>().hash(auxiliaryPools),
      );
}

/// Vitals modification result from an applied delta.
@immutable
class VitalsModification {
  final EntityVitals updatedVitals;
  final int effectiveDelta;
  final bool triggeredDeath;
  final bool revivedFromDefeat;

  const VitalsModification({
    required this.updatedVitals,
    required this.effectiveDelta,
    this.triggeredDeath = false,
    this.revivedFromDefeat = false,
  });
}

/// Action economy budget tracking.
@immutable
class ActionBudget {
  final int actionsRemaining;
  final int bonusActionsRemaining;
  final int reactionsRemaining;
  final Map<String, int> customActionTokens;

  const ActionBudget({
    this.actionsRemaining = 1,
    this.bonusActionsRemaining = 1,
    this.reactionsRemaining = 1,
    this.customActionTokens = const {},
  });

  ActionBudget copyWith({
    int? actionsRemaining,
    int? bonusActionsRemaining,
    int? reactionsRemaining,
    Map<String, int>? customActionTokens,
  }) {
    return ActionBudget(
      actionsRemaining: actionsRemaining ?? this.actionsRemaining,
      bonusActionsRemaining:
          bonusActionsRemaining ?? this.bonusActionsRemaining,
      reactionsRemaining: reactionsRemaining ?? this.reactionsRemaining,
      customActionTokens: customActionTokens != null
          ? Map.unmodifiable(customActionTokens)
          : this.customActionTokens,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionBudget &&
          actionsRemaining == other.actionsRemaining &&
          bonusActionsRemaining == other.bonusActionsRemaining &&
          reactionsRemaining == other.reactionsRemaining &&
          _mapEquals(customActionTokens, other.customActionTokens);

  @override
  int get hashCode => Object.hash(
        actionsRemaining,
        bonusActionsRemaining,
        reactionsRemaining,
        const MapEquality<String, int>().hash(customActionTokens),
      );
}

enum ActionCost { action, bonusAction, reaction, free, special }

/// Rest resolution output.
@immutable
class RestResult {
  final EntityVitals vitals;
  final Map<String, int> restoredResources;
  final String summary;

  const RestResult({
    required this.vitals,
    this.restoredResources = const {},
    this.summary = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestResult &&
          vitals == other.vitals &&
          summary == other.summary &&
          _mapEquals(restoredResources, other.restoredResources);

  @override
  int get hashCode => Object.hash(
        vitals,
        summary,
        const MapEquality<String, int>().hash(restoredResources),
      );
}

/// Combat rider definition for action side-effects.
@immutable
class CombatRiderDefinition {
  final String id;
  final String name;
  final String riderType; // 'condition', 'drain', 'forced_movement'
  final Map<String, dynamic> params;

  const CombatRiderDefinition({
    required this.id,
    required this.name,
    required this.riderType,
    this.params = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombatRiderDefinition &&
          id == other.id &&
          name == other.name &&
          riderType == other.riderType &&
          _mapEquals(params, other.params);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        riderType,
        const MapEquality<String, dynamic>().hash(params),
      );
}
