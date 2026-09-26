import '../rules/ruleset_context.dart';

enum WeaponMasteryProperty {
  cleave,
  graze,
  nick,
  push,
  sap,
  slow,
  topple,
  vex,
}

extension WeaponMasteryPropertyDetails on WeaponMasteryProperty {
  String get displayName {
    switch (this) {
      case WeaponMasteryProperty.cleave:
        return 'Cleave';
      case WeaponMasteryProperty.graze:
        return 'Graze';
      case WeaponMasteryProperty.nick:
        return 'Nick';
      case WeaponMasteryProperty.push:
        return 'Push';
      case WeaponMasteryProperty.sap:
        return 'Sap';
      case WeaponMasteryProperty.slow:
        return 'Slow';
      case WeaponMasteryProperty.topple:
        return 'Topple';
      case WeaponMasteryProperty.vex:
        return 'Vex';
    }
  }

  String get summaryDescription {
    switch (this) {
      case WeaponMasteryProperty.cleave:
        return 'Make a second melee attack against an adjacent creature within 5 ft on hit.';
      case WeaponMasteryProperty.graze:
        return 'Deal ability modifier damage on a miss.';
      case WeaponMasteryProperty.nick:
        return 'Make the extra Light weapon attack as part of the Attack action instead of a bonus action.';
      case WeaponMasteryProperty.push:
        return 'Push a Large or smaller creature up to 10 feet straight away on hit.';
      case WeaponMasteryProperty.sap:
        return 'Target has Disadvantage on its next attack roll before the start of your next turn on hit.';
      case WeaponMasteryProperty.slow:
        return 'Reduce target speed by 10 feet until the start of your next turn on hit.';
      case WeaponMasteryProperty.topple:
        return 'Target must succeed on a Constitution save (DC 8 + Prof + Ability) or fall Prone on hit.';
      case WeaponMasteryProperty.vex:
        return 'Gain Advantage on your next attack roll against the target before the end of your next turn on hit.';
    }
  }
}

class WeaponMasteryValidator {
  const WeaponMasteryValidator._();

  static bool isEligible({
    required RulesetVersion ruleset,
    required bool hasWeaponMasteryFeature,
    required bool isProficientWithWeapon,
    required bool hasMasteryUnlockedForWeapon,
  }) {
    final engine = RulesetEngine.forVersion(ruleset);
    if (!engine.supportsWeaponMasteries()) {
      return false;
    }

    return hasWeaponMasteryFeature &&
        isProficientWithWeapon &&
        hasMasteryUnlockedForWeapon;
  }

  static String? getEligibilityFailureReason({
    required RulesetVersion ruleset,
    required bool hasWeaponMasteryFeature,
    required bool isProficientWithWeapon,
    required bool hasMasteryUnlockedForWeapon,
  }) {
    final engine = RulesetEngine.forVersion(ruleset);
    if (!engine.supportsWeaponMasteries()) {
      return 'Weapon masteries are only supported in 2024 SRD 5.2.1 ruleset.';
    }
    if (!hasWeaponMasteryFeature) {
      return 'Character lacks the Weapon Mastery feature.';
    }
    if (!isProficientWithWeapon) {
      return 'Character is not proficient with this weapon.';
    }
    if (!hasMasteryUnlockedForWeapon) {
      return 'Mastery is not unlocked for this specific weapon.';
    }
    return null;
  }
}
