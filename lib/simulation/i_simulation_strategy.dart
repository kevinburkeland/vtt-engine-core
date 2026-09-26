import 'dart:math';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) =>
    const ListEquality().equals(a, b);

/// Structured outcome of a single simulation iteration step.
@immutable
class SimulationStepOutcome {
  final bool isSuccess;
  final bool isCritical;
  final double
      magnitude; // Damage, healing, degrees of success, or effect intensity
  final int resourceCost;
  final List<String> logs;

  const SimulationStepOutcome({
    required this.isSuccess,
    required this.isCritical,
    required this.magnitude,
    this.resourceCost = 0,
    this.logs = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimulationStepOutcome &&
          isSuccess == other.isSuccess &&
          isCritical == other.isCritical &&
          magnitude == other.magnitude &&
          resourceCost == other.resourceCost &&
          _listEquals(logs, other.logs);

  @override
  int get hashCode => Object.hash(
        isSuccess,
        isCritical,
        magnitude,
        resourceCost,
        const ListEquality<String>().hash(logs),
      );
}

/// Abstract strategy contract defining one simulation iteration step for an arbitrary tabletop mechanic.
abstract interface class ISimulationStrategy<TAction, TTarget> {
  String get strategyId;

  /// Simulates a single action attempt against target defenses using the provided RNG.
  SimulationStepOutcome simulateStep({
    required TAction action,
    required TTarget target,
    required Random rng,
  });
}

/// Aggregated statistical summary resulting from an agnostic Monte Carlo simulation run.
@immutable
class MonteCarloSummary {
  final int iterations;
  final int successCount;
  final int critCount;
  final int failureCount;
  final double totalMagnitude;
  final double meanMagnitude;
  final double minMagnitude;
  final double maxMagnitude;

  const MonteCarloSummary({
    required this.iterations,
    required this.successCount,
    required this.critCount,
    required this.failureCount,
    required this.totalMagnitude,
    required this.meanMagnitude,
    required this.minMagnitude,
    required this.maxMagnitude,
  });

  double get successRate => iterations > 0 ? successCount / iterations : 0.0;
  double get critRate => iterations > 0 ? critCount / iterations : 0.0;
  double get failureRate => iterations > 0 ? failureCount / iterations : 0.0;

  Map<String, dynamic> toMap() => {
        'iterations': iterations,
        'successCount': successCount,
        'critCount': critCount,
        'failureCount': failureCount,
        'totalMagnitude': totalMagnitude,
        'meanMagnitude': meanMagnitude,
        'minMagnitude': minMagnitude,
        'maxMagnitude': maxMagnitude,
        'successRate': successRate,
        'critRate': critRate,
        'failureRate': failureRate,
      };
}

/// Generalized, ruleset-agnostic Monte Carlo simulation runner with O(1) intermediate heap allocation.
class MonteCarloSimulator<TAction, TTarget> {
  final ISimulationStrategy<TAction, TTarget> strategy;

  const MonteCarloSimulator(this.strategy);

  MonteCarloSummary run({
    required TAction action,
    required TTarget target,
    int iterations = 10000,
    Random? rng,
  }) {
    final random = rng ?? Random();
    var successes = 0;
    var crits = 0;
    var failures = 0;
    var totalMag = 0.0;
    var minMag = 999999999.0;
    var maxMag = 0.0;

    for (var i = 0; i < iterations; i++) {
      final step = strategy.simulateStep(
        action: action,
        target: target,
        rng: random,
      );

      if (step.isCritical) {
        crits++;
      }

      if (step.isSuccess) {
        successes++;
      } else {
        failures++;
      }

      final mag = step.magnitude;
      totalMag += mag;
      if (mag < minMag) minMag = mag;
      if (mag > maxMag) maxMag = mag;
    }

    if (iterations == 0 || minMag == 999999999.0) {
      minMag = 0.0;
    }

    return MonteCarloSummary(
      iterations: iterations,
      successCount: successes,
      critCount: crits,
      failureCount: failures,
      totalMagnitude: totalMag,
      meanMagnitude: iterations > 0 ? totalMag / iterations : 0.0,
      minMagnitude: minMag,
      maxMagnitude: maxMag,
    );
  }
}
