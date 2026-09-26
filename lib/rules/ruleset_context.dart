import 'ruleset_edition.dart';
export 'ruleset_edition.dart';

/// Canonical RulesetEdition alias for backward compatibility.
typedef RulesetVersion = RulesetEdition;

enum ActionCost { action, bonusAction, reaction, free }

abstract class RulesetEngine {
  final RulesetEdition edition;
  const RulesetEngine(this.edition);

  /// Backwards-compatible alias for [edition].
  RulesetEdition get version => edition;

  factory RulesetEngine.forEdition(RulesetEdition edition) {
    switch (edition) {
      case RulesetEdition.dnd2014:
        return const RulesetEngine2014();
      case RulesetEdition.dnd2024:
        return const RulesetEngine2024();
    }
  }

  factory RulesetEngine.forVersion(RulesetEdition version) =>
      RulesetEngine.forEdition(version);

  ActionCost get potionConsumptionCost;
  int calculateExhaustionD20Penalty(int level);
  int calculateExhaustionSpeedPenalty(int level, int baseSpeed);
  bool isExhaustionFatal(int level);
  bool supportsWeaponMasteries();
}

class RulesetEngine2014 extends RulesetEngine {
  const RulesetEngine2014() : super(RulesetEdition.dnd2014);

  @override
  ActionCost get potionConsumptionCost => ActionCost.action;

  @override
  int calculateExhaustionD20Penalty(int level) => 0;

  @override
  int calculateExhaustionSpeedPenalty(int level, int baseSpeed) =>
      level >= 5 ? baseSpeed : (level >= 2 ? (baseSpeed ~/ 2) : 0);

  @override
  bool isExhaustionFatal(int level) => level >= 6;

  @override
  bool supportsWeaponMasteries() => false;
}

class RulesetEngine2024 extends RulesetEngine {
  const RulesetEngine2024() : super(RulesetEdition.dnd2024);

  @override
  ActionCost get potionConsumptionCost => ActionCost.bonusAction;

  @override
  int calculateExhaustionD20Penalty(int level) => (level.clamp(0, 6)) * 2;

  @override
  int calculateExhaustionSpeedPenalty(int level, int baseSpeed) =>
      (level.clamp(0, 6)) * 5;

  @override
  bool isExhaustionFatal(int level) => level >= 6;

  @override
  bool supportsWeaponMasteries() => true;
}
