import 'dart:math' as math;
import 'package:meta/meta.dart';

/// Pure Dart CvRDT implementing a Positive-Negative Counter (PN-Counter).
///
/// Maintains two grow-only vectors:
/// - [positive]: Map of nodeId -> total positive increments (deposits).
/// - [negative]: Map of nodeId -> total negative decrements (withdrawals).
///
/// Merging two counters takes component-wise maximums for both positive and negative vectors.
/// The net counter value is clamped at zero ($\ge 0$) to model tabletop currency balances.
///
/// STRICT DDD INVARIANT: Zero Flutter imports in `lib/domain/`.
@immutable
class PnCounter {
  final Map<String, int> positive;
  final Map<String, int> negative;

  const PnCounter({
    this.positive = const <String, int>{},
    this.negative = const <String, int>{},
  });

  /// Factory creating an initial PN-counter with a starting balance on a given node.
  factory PnCounter.withInitialValue(int initialValue,
      {String nodeId = 'local'}) {
    final clamped = math.max(0, initialValue);
    if (clamped == 0) {
      return const PnCounter();
    }
    return PnCounter(
      positive: {nodeId: clamped},
      negative: const {},
    );
  }

  /// Total sum of all positive increments across all nodes.
  int get positiveSum => positive.values.fold(0, (sum, val) => sum + val);

  /// Total sum of all negative decrements across all nodes.
  int get negativeSum => negative.values.fold(0, (sum, val) => sum + val);

  /// Current net value of the counter, guaranteed non-negative ($\ge 0$).
  int get value => math.max(0, positiveSum - negativeSum);

  /// Increments the counter by [amount] for [nodeId].
  PnCounter increment(int amount, {String nodeId = 'local'}) {
    if (amount <= 0) return this;
    final currentPos = positive[nodeId] ?? 0;
    final updatedPos = Map<String, int>.from(positive);
    updatedPos[nodeId] = currentPos + amount;

    return PnCounter(
      positive: Map.unmodifiable(updatedPos),
      negative: negative,
    );
  }

  /// Decrements the counter by [amount] for [nodeId].
  PnCounter decrement(int amount, {String nodeId = 'local'}) {
    if (amount <= 0) return this;
    final currentNeg = negative[nodeId] ?? 0;
    final updatedNeg = Map<String, int>.from(negative);
    updatedNeg[nodeId] = currentNeg + amount;

    return PnCounter(
      positive: positive,
      negative: Map.unmodifiable(updatedNeg),
    );
  }

  /// Merges this PN-Counter with [other] using state-based CRDT lattice join (component-wise max).
  PnCounter merge(PnCounter other) {
    if (identical(this, other)) return this;

    final allPosKeys = {...positive.keys, ...other.positive.keys};
    final mergedPos = <String, int>{};
    for (final key in allPosKeys) {
      final v1 = positive[key] ?? 0;
      final v2 = other.positive[key] ?? 0;
      mergedPos[key] = math.max(v1, v2);
    }

    final allNegKeys = {...negative.keys, ...other.negative.keys};
    final mergedNeg = <String, int>{};
    for (final key in allNegKeys) {
      final v1 = negative[key] ?? 0;
      final v2 = other.negative[key] ?? 0;
      mergedNeg[key] = math.max(v1, v2);
    }

    return PnCounter(
      positive: Map.unmodifiable(mergedPos),
      negative: Map.unmodifiable(mergedNeg),
    );
  }

  /// Converts this PN-Counter to a serializable map.
  Map<String, dynamic> toMap() {
    return {
      'positive': positive,
      'negative': negative,
    };
  }

  /// Reconstitutes a PN-Counter from a map.
  factory PnCounter.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PnCounter();

    final rawPos = map['positive'];
    final pos = <String, int>{};
    if (rawPos is Map) {
      for (final entry in rawPos.entries) {
        if (entry.value is num) {
          pos[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    final rawNeg = map['negative'];
    final neg = <String, int>{};
    if (rawNeg is Map) {
      for (final entry in rawNeg.entries) {
        if (entry.value is num) {
          neg[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    return PnCounter(
      positive: Map.unmodifiable(pos),
      negative: Map.unmodifiable(neg),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PnCounter) return false;

    if (positive.length != other.positive.length ||
        negative.length != other.negative.length) {
      return false;
    }

    for (final entry in positive.entries) {
      if (other.positive[entry.key] != entry.value) return false;
    }
    for (final entry in negative.entries) {
      if (other.negative[entry.key] != entry.value) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(
            positive.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            negative.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'PnCounter(value: $value, P: $positive, N: $negative)';
}
