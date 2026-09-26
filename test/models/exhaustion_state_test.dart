import 'package:test/test.dart';
import 'package:vtt_engine_core/models/exhaustion_state.dart';
import 'package:vtt_engine_core/rules/ruleset_context.dart';

void main() {
  group('ExhaustionState', () {
    test('calculates 2024 linear penalties correctly', () {
      const state = ExhaustionState(level: 3, ruleset: RulesetVersion.v2024);

      expect(state.clampedLevel, equals(3));
      expect(state.d20Penalty, equals(6));
      expect(state.speedReduction(), equals(15));
      expect(state.speedReduction(30), equals(15));
      expect(state.speedReduction(40), equals(15));
      expect(state.isDead, isFalse);
      expect(state.activeEffectsDescription.first,
          contains('D20 Test Penalty: -6'));
    });

    test('calculates 2014 cumulative tier descriptions correctly', () {
      const state = ExhaustionState(level: 3, ruleset: RulesetVersion.v2014);

      expect(state.clampedLevel, equals(3));
      expect(state.d20Penalty, equals(0));
      expect(state.speedReduction(), equals(15));
      expect(state.speedReduction(30), equals(15));
      expect(state.speedReduction(40), equals(20));
      expect(state.isDead, isFalse);
      expect(state.activeEffectsDescription,
          contains('Disadvantage on ability checks'));
      expect(state.activeEffectsDescription, contains('Speed halved'));
      expect(state.activeEffectsDescription,
          contains('Disadvantage on attack rolls and saving throws'));
      expect(state.activeEffectsDescription.length, equals(3));
    });

    test('handles level 6 death on both rulesets', () {
      const state2014 =
          ExhaustionState(level: 6, ruleset: RulesetVersion.v2014);
      const state2024 =
          ExhaustionState(level: 6, ruleset: RulesetVersion.v2024);

      expect(state2014.isDead, isTrue);
      expect(state2024.isDead, isTrue);
      expect(state2014.activeEffectsDescription.last, equals('Death'));
      expect(state2024.activeEffectsDescription.first, equals('Death'));
    });

    test('increment, decrement, and reset helpers behave predictably', () {
      var state =
          const ExhaustionState(level: 0, ruleset: RulesetVersion.v2024);
      expect(state.clampedLevel, equals(0));

      state = state.increment();
      expect(state.clampedLevel, equals(1));

      state = state.increment().increment().increment();
      expect(state.clampedLevel, equals(4));

      state = state.decrement();
      expect(state.clampedLevel, equals(3));

      state = state.reset();
      expect(state.clampedLevel, equals(0));
    });
  });
}
