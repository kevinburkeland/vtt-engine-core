import 'package:test/test.dart';
import 'package:vtt_engine_core/models/weapon_mastery.dart';
import 'package:vtt_engine_core/rules/ruleset_context.dart';

void main() {
  group('Weapon Mastery', () {
    test('enum properties expose display names and summaries', () {
      expect(WeaponMasteryProperty.values.length, equals(8));
      expect(WeaponMasteryProperty.cleave.displayName, equals('Cleave'));
      expect(WeaponMasteryProperty.graze.displayName, equals('Graze'));
      expect(WeaponMasteryProperty.nick.displayName, equals('Nick'));
      expect(WeaponMasteryProperty.push.displayName, equals('Push'));
      expect(WeaponMasteryProperty.sap.displayName, equals('Sap'));
      expect(WeaponMasteryProperty.slow.displayName, equals('Slow'));
      expect(WeaponMasteryProperty.topple.displayName, equals('Topple'));
      expect(WeaponMasteryProperty.vex.displayName, equals('Vex'));

      for (final prop in WeaponMasteryProperty.values) {
        expect(prop.summaryDescription.isNotEmpty, isTrue);
      }
    });

    test('validates ruleset 2014 disallows weapon mastery', () {
      final eligible = WeaponMasteryValidator.isEligible(
        ruleset: RulesetVersion.v2014,
        hasWeaponMasteryFeature: true,
        isProficientWithWeapon: true,
        hasMasteryUnlockedForWeapon: true,
      );
      expect(eligible, isFalse);

      final reason = WeaponMasteryValidator.getEligibilityFailureReason(
        ruleset: RulesetVersion.v2014,
        hasWeaponMasteryFeature: true,
        isProficientWithWeapon: true,
        hasMasteryUnlockedForWeapon: true,
      );
      expect(reason, contains('2024 SRD 5.2.1'));
    });

    test('validates prerequisite requirements on 2024 ruleset', () {
      // Missing weapon mastery class feature
      expect(
        WeaponMasteryValidator.isEligible(
          ruleset: RulesetVersion.v2024,
          hasWeaponMasteryFeature: false,
          isProficientWithWeapon: true,
          hasMasteryUnlockedForWeapon: true,
        ),
        isFalse,
      );

      // Missing weapon proficiency
      expect(
        WeaponMasteryValidator.isEligible(
          ruleset: RulesetVersion.v2024,
          hasWeaponMasteryFeature: true,
          isProficientWithWeapon: false,
          hasMasteryUnlockedForWeapon: true,
        ),
        isFalse,
      );

      // Mastery not unlocked for specific weapon
      expect(
        WeaponMasteryValidator.isEligible(
          ruleset: RulesetVersion.v2024,
          hasWeaponMasteryFeature: true,
          isProficientWithWeapon: true,
          hasMasteryUnlockedForWeapon: false,
        ),
        isFalse,
      );

      // All requirements met
      expect(
        WeaponMasteryValidator.isEligible(
          ruleset: RulesetVersion.v2024,
          hasWeaponMasteryFeature: true,
          isProficientWithWeapon: true,
          hasMasteryUnlockedForWeapon: true,
        ),
        isTrue,
      );

      expect(
        WeaponMasteryValidator.getEligibilityFailureReason(
          ruleset: RulesetVersion.v2024,
          hasWeaponMasteryFeature: true,
          isProficientWithWeapon: true,
          hasMasteryUnlockedForWeapon: true,
        ),
        isNull,
      );
    });
  });
}
