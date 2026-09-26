import '../currency/i_currency_system.dart';
import '../models/generic_tabletop_primitives.dart';
import 'i_combat_resolver.dart';

/// Pluggable Tabletop Ruleset Module interface.
///
/// Implementations encapsulate all system-specific rules mechanics, attribute calculations,
/// resting frameworks, exhaustion states, action economies, and combat resolvers.
abstract interface class IRulesetModule {
  /// Unique machine-readable identifier for the ruleset module (e.g. 'dnd5e_2024', 'dnd5e_2014', 'pf2e').
  String get moduleId;

  /// Human-readable title for UI selectors, badges, and headers.
  String get displayName;

  /// Version or edition identifier of the ruleset.
  String get rulesetVersion;

  /// Legal systems reference document citation.
  String get srdCitation;

  /// The attribute system governing entity scores and modifiers in this ruleset.
  IAttributeSystem get attributeSystem;

  /// The currency system governing denominations and conversions.
  ICurrencySystem get currencySystem;

  /// Factory / mechanic for resolving exhaustion rules.
  IExhaustionMechanic get exhaustionMechanic;

  /// Factory / mechanic for resolving short and long rests.
  IRestMechanic get restMechanic;

  /// Factory / mechanic for resolving action economy costs and budgets.
  IActionEconomy get actionEconomy;

  /// Factory / mechanic for resolving attacks, damage, and vitals modifications.
  ICombatResolver get combatResolver;

  /// Set of default pinned tabletop rules for this ruleset.
  Set<String> get defaultPinnedRules;

  /// Queries whether this ruleset module supports a named mechanical capability
  /// (e.g. 'weapon_masteries', 'tactical_mind', 'inspiration', 'death_saves').
  bool supportsFeature(String featureKey);

  /// Calculates a derived entity statistic dynamically (e.g. 'ac', 'initiative', 'passive_perception').
  int calculateDerivedStat({
    required dynamic character,
    required String statKey,
    Map<String, dynamic> context = const {},
  });
}

/// Abstract Exhaustion Mechanics resolver.
abstract interface class IExhaustionMechanic {
  /// Maximum number of exhaustion tiers permitted before fatality.
  int get maxExhaustionTiers;

  /// D20 test penalty (if applicable) at the given exhaustion tier.
  int calculateD20Penalty(int tier);

  /// Movement speed reduction at the given exhaustion tier.
  int calculateSpeedPenalty(int tier, int baseSpeed);

  /// Whether the specified exhaustion tier results in death.
  bool isFatal(int tier);

  /// Descriptive text summarizing the mechanical penalties of the given tier.
  String describeTierEffects(int tier);
}

/// Abstract Resting Mechanics resolver.
abstract interface class IRestMechanic {
  /// Resolves a short or field rest, applying spent recovery resources.
  RestResult resolveShortRest({
    required EntityVitals currentVitals,
    required Map<String, int> spentRecoveryResources,
  });

  /// Resolves a long or extended rest, restoring vitals and standard pools.
  RestResult resolveLongRest({
    required EntityVitals currentVitals,
  });
}

/// Abstract Action Economy resolver.
abstract interface class IActionEconomy {
  /// Resolves the action economy cost for consuming a consumable (e.g. potion: Action in 2014 vs Bonus Action in 2024).
  ActionCost getConsumableUsageCost(String consumableType);

  /// Validates whether an action of the given type can be taken with the current budget and conditions.
  bool canTakeAction({
    required String actionType,
    required Set<String> activeConditions,
    required ActionBudget currentBudget,
  });
}
