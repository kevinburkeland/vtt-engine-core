import 'package:test/test.dart';
import 'package:vtt_engine_core/rules/ruleset_context.dart';

void main() {
  group('RulesetEngine arbitration', () {
    test('RulesetEngine2014 designates potion consumption as ActionCost.action',
        () {
      final engine = RulesetEngine.forVersion(RulesetVersion.v2014);
      expect(engine.potionConsumptionCost, equals(ActionCost.action));
      expect(engine.supportsWeaponMasteries(), isFalse);
    });

    test(
        'RulesetEngine2024 designates potion consumption as ActionCost.bonusAction',
        () {
      final engine = RulesetEngine.forVersion(RulesetVersion.v2024);
      expect(engine.potionConsumptionCost, equals(ActionCost.bonusAction));
      expect(engine.supportsWeaponMasteries(), isTrue);
    });

    test('RulesetEngine2014 exhaustion speed reductions and fatal threshold',
        () {
      final engine = RulesetEngine.forVersion(RulesetVersion.v2014);

      expect(engine.calculateExhaustionD20Penalty(0), equals(0));
      expect(engine.calculateExhaustionD20Penalty(3), equals(0));
      expect(engine.calculateExhaustionSpeedPenalty(1, 30), equals(0));
      expect(engine.calculateExhaustionSpeedPenalty(2, 30), equals(15));
      expect(engine.calculateExhaustionSpeedPenalty(4, 30), equals(15));
      expect(engine.calculateExhaustionSpeedPenalty(2, 40), equals(20));
      expect(engine.calculateExhaustionSpeedPenalty(5, 30), equals(30));
      expect(engine.calculateExhaustionSpeedPenalty(5, 40), equals(40));
      expect(engine.isExhaustionFatal(5), isFalse);
      expect(engine.isExhaustionFatal(6), isTrue);
      expect(engine.isExhaustionFatal(7), isTrue);
    });

    test(
        'RulesetEngine2024 scales d20 penalty linearly by -2 per level and triggers death at level 6',
        () {
      final engine = RulesetEngine.forVersion(RulesetVersion.v2024);

      expect(engine.calculateExhaustionD20Penalty(0), equals(0));
      expect(engine.calculateExhaustionD20Penalty(1), equals(2));
      expect(engine.calculateExhaustionD20Penalty(2), equals(4));
      expect(engine.calculateExhaustionD20Penalty(3), equals(6));
      expect(engine.calculateExhaustionD20Penalty(4), equals(8));
      expect(engine.calculateExhaustionD20Penalty(5), equals(10));
      expect(engine.calculateExhaustionD20Penalty(6), equals(12));

      expect(engine.calculateExhaustionSpeedPenalty(0, 30), equals(0));
      expect(engine.calculateExhaustionSpeedPenalty(1, 30), equals(5));
      expect(engine.calculateExhaustionSpeedPenalty(3, 30), equals(15));
      expect(engine.calculateExhaustionSpeedPenalty(6, 30), equals(30));

      expect(engine.isExhaustionFatal(5), isFalse);
      expect(engine.isExhaustionFatal(6), isTrue);
      expect(engine.isExhaustionFatal(10), isTrue);
    });

    test('RulesetEdition canonical value object parsing and conversions', () {
      expect(RulesetEdition.fromString('2014'), equals(RulesetEdition.dnd2014));
      expect(
          RulesetEdition.fromString('5e-2014'), equals(RulesetEdition.dnd2014));
      expect(
          RulesetEdition.fromString('srd2014'), equals(RulesetEdition.dnd2014));
      expect(
          RulesetEdition.fromString('v2014'), equals(RulesetEdition.dnd2014));

      expect(RulesetEdition.fromString('2024'), equals(RulesetEdition.dnd2024));
      expect(
          RulesetEdition.fromString('5e-2024'), equals(RulesetEdition.dnd2024));
      expect(RulesetEdition.fromString('srd5.2.1'),
          equals(RulesetEdition.dnd2024));
      expect(
          RulesetEdition.fromString('srd5.2'), equals(RulesetEdition.dnd2024));
      expect(
          RulesetEdition.fromString('srd521'), equals(RulesetEdition.dnd2024));
      expect(
          RulesetEdition.fromString('srd52'), equals(RulesetEdition.dnd2024));

      // Bi-directional conversion with RulesetVersion
      expect(RulesetVersion.v2014.toEdition(), equals(RulesetEdition.dnd2014));
      expect(RulesetVersion.v2024.toEdition(), equals(RulesetEdition.dnd2024));
      expect(RulesetVersion.fromEdition(RulesetEdition.dnd2014),
          equals(RulesetVersion.v2014));
      expect(RulesetVersion.fromEdition(RulesetEdition.dnd2024),
          equals(RulesetVersion.v2024));

      // RulesetEngine.forEdition instantiates correct engine
      final engine2014 = RulesetEngine.forEdition(RulesetEdition.dnd2014);
      expect(engine2014.potionConsumptionCost, equals(ActionCost.action));

      final engine2024 = RulesetEngine.forEdition(RulesetEdition.dnd2024);
      expect(engine2024.potionConsumptionCost, equals(ActionCost.bonusAction));
    });
  });
}
