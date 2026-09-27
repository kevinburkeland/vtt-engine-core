import '../currency/i_currency_system.dart';
import '../models/generic_tabletop_primitives.dart';
import 'i_combat_resolver.dart';

/// Pluggable Tabletop Ruleset Module interface.
///
/// Implementations encapsulate system-specific rules mechanics, attribute calculations,
/// resting frameworks, exhaustion states, action economies, and combat resolvers.
abstract interface class IRulesetModule {
  /// Unique machine-readable identifier for the ruleset module (e.g. 'fantasy_module', 'space_opera_module', 'pf2e').
  String get moduleId;

  /// Human-readable title for UI selectors, badges, and headers.
  String get displayName;

  /// Version or edition identifier of the ruleset.
  String get rulesetVersion;

  /// Optional legal / licensing citation for systems reference documents or open game licenses.
  String? get legalCitation => null;

  /// The attribute system governing entity scores and modifiers in this ruleset.
  IAttributeSystem get attributeSystem;

  /// The currency system governing denominations and conversions.
  ICurrencySystem get currencySystem;

  /// Optional factory / mechanic for resolving exhaustion rules (null if ruleset has no exhaustion).
  IExhaustionMechanic? get exhaustionMechanic => null;

  /// Optional factory / mechanic for resolving rests (null if ruleset has no rest recovery system).
  IRestMechanic? get restMechanic => null;

  /// Optional factory / mechanic for resolving action economy costs and budgets.
  IActionEconomy? get actionEconomy => null;

  /// Factory / mechanic for resolving attacks, damage, and vitals modifications.
  ICombatResolver get combatResolver;

  /// Set of default pinned tabletop rules for this ruleset.
  Set<String> get defaultPinnedRules;

  /// Queries whether this ruleset module supports a named mechanical capability
  /// (e.g. 'tactical_mind', 'grit', 'luck').
  bool supportsFeature(String featureKey);

  /// Calculates a derived entity statistic dynamically (e.g. 'defense', 'initiative', 'perception').
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

  /// Check / test penalty (if applicable) at the given exhaustion tier.
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
  /// Resolves rest of the specified rest type or duration (e.g. 'brief', 'extended', 'full').
  RestResult resolveRest({
    required String restType,
    required EntityVitals currentVitals,
    Map<String, int> spentRecoveryResources = const {},
  });
}

/// Abstract Action Economy resolver.
abstract interface class IActionEconomy {
  /// Resolves the action economy cost for consuming a consumable.
  ActionCost getConsumableUsageCost(String consumableType);

  /// Validates whether an action of the given type can be taken with the current budget and conditions.
  bool canTakeAction({
    required String actionType,
    required Set<String> activeConditions,
    required ActionBudget currentBudget,
  });
}
