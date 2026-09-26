import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/simulation/i_simulation_strategy.dart';

/// Mock Percentile (d100) Strategy (Percentile System roll-under)
class D100RollUnderStrategy implements ISimulationStrategy<int, int> {
  const D100RollUnderStrategy();

  @override
  String get strategyId => 'd100_roll_under';

  @override
  SimulationStepOutcome simulateStep({
    required int action, // Skill rating (e.g. 60)
    required int target, // Difficulty threshold modifier (e.g. 0)
    required Random rng,
  }) {
    final roll = rng.nextInt(100) + 1;
    final effectiveSkill = max(1, action - target);
    final isCrit = roll == 1 || roll <= (effectiveSkill ~/ 5);
    final isSuccess = roll <= effectiveSkill;

    return SimulationStepOutcome(
      isSuccess: isSuccess,
      isCritical: isCrit,
      magnitude: isSuccess ? (isCrit ? 2.0 : 1.0) : 0.0,
    );
  }
}

/// Mock Dice Pool Strategy (D6 Dice Pool System: count d6 >= 5)
class DicePoolHitsStrategy implements ISimulationStrategy<int, int> {
  const DicePoolHitsStrategy();

  @override
  String get strategyId => 'dice_pool_hits';

  @override
  SimulationStepOutcome simulateStep({
    required int action, // Pool size (e.g. 8 dice)
    required int target, // Threshold hits required (e.g. 3)
    required Random rng,
  }) {
    var hits = 0;
    for (var i = 0; i < action; i++) {
      final die = rng.nextInt(6) + 1;
      if (die >= 5) hits++;
    }

    final isSuccess = hits >= target;
    final isCrit = hits >= target + 2;

    return SimulationStepOutcome(
      isSuccess: isSuccess,
      isCritical: isCrit,
      magnitude: hits.toDouble(),
    );
  }
}

void main() {
  group('Agnostic Monte Carlo Simulator Core Tests', () {
    test('simulates d100 percentile roll-under mechanics accurately', () {
      const strategy = D100RollUnderStrategy();
      const simulator = MonteCarloSimulator<int, int>(strategy);

      // Skill 60 should have roughly 60% success rate across 10,000 runs
      final summary = simulator.run(
        action: 60,
        target: 0,
        iterations: 5000,
        rng: Random(42),
      );

      expect(summary.iterations, equals(5000));
      expect(summary.successRate, closeTo(0.60, 0.03));
      expect(summary.critRate, greaterThan(0.05));
    });

    test('simulates dice pool mechanics accurately', () {
      const strategy = DicePoolHitsStrategy();
      const simulator = MonteCarloSimulator<int, int>(strategy);

      // 6 dice pool: expected average hits is 6 * (1/3) = 2.0 hits
      final summary = simulator.run(
        action: 6,
        target: 2,
        iterations: 5000,
        rng: Random(42),
      );

      expect(summary.iterations, equals(5000));
      expect(summary.meanMagnitude, closeTo(2.0, 0.1));
      expect(summary.maxMagnitude, lessThanOrEqualTo(6.0));
      expect(summary.minMagnitude, greaterThanOrEqualTo(0.0));
    });
  });
}
