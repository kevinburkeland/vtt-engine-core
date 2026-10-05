import 'dart:math' as math;
import 'package:meta/meta.dart';
import 'replica_id.dart';

/// Pure Dart CvRDT implementing a Positive-Negative Counter (PN-Counter).
///
/// Maintains two grow-only vectors:
/// - [positive]: Map of writer component ID -> total positive increments (deposits).
/// - [negative]: Map of writer component ID -> total negative decrements (withdrawals).
///
/// Merging two counters takes component-wise maximums for both positive and negative vectors.
/// The net counter value is mathematically signed: [positiveSum] - [negativeSum].
/// Component totals within [positive] and [negative] must be non-negative (>= 0).
///
/// Invariant: Active mutation APIs require a strongly-typed [ReplicaId] identifying the
/// active runtime writer. Historical serialized component maps may contain arbitrary string
/// keys (e.g. legacy 'init', 'cloud', historical UUIDs) which remain valid immutable history.
///
/// STRICT DDD INVARIANT: Zero Flutter imports in `lib/domain/`.
@immutable
class PnCounter {
  final Map<String, int> positive;
  final Map<String, int> negative;

  PnCounter({
    Map<String, int> positive = const {},
    Map<String, int> negative = const {},
  })  : positive = _validateAndFreeze(positive),
        negative = _validateAndFreeze(negative);

  const PnCounter.empty()
      : positive = const {},
        negative = const {};

  /// Factory creating an initial PN-counter with a starting balance on a given replica.
  /// Represents signed values accurately:
  /// - initialValue > 0: positive component
  /// - initialValue < 0: negative component
  /// - initialValue == 0: empty counter
  factory PnCounter.withInitialValue(int initialValue,
      {required ReplicaId replicaId}) {
    if (initialValue > 0) {
      return PnCounter(
        positive: {replicaId.value: initialValue},
        negative: const {},
      );
    } else if (initialValue < 0) {
      return PnCounter(
        positive: const {},
        negative: {replicaId.value: initialValue.abs()},
      );
    }
    return const PnCounter.empty();
  }

  static Map<String, int> _validateAndFreeze(Map<String, int> source) {
    for (final entry in source.entries) {
      if (entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'PN-counter component totals must be non-negative (>= 0)',
        );
      }
    }
    return Map.unmodifiable(Map<String, int>.from(source));
  }

  /// Total sum of all positive increments across all nodes.
  int get positiveSum => positive.values.fold(0, (sum, val) => sum + val);

  /// Total sum of all negative decrements across all nodes.
  int get negativeSum => negative.values.fold(0, (sum, val) => sum + val);

  /// Current net mathematical value of the counter (signed: positiveSum - negativeSum).
  int get value => positiveSum - negativeSum;

  /// Effective non-negative domain interpretation (clamped at 0 for display/currency).
  int get effectiveNonNegativeValue => math.max(0, value);

  /// Alias for [effectiveNonNegativeValue].
  int get nonNegativeValue => effectiveNonNegativeValue;

  /// Increments the counter by [amount] for [replicaId].
  PnCounter increment(int amount, {required ReplicaId replicaId}) {
    if (amount <= 0) return this;
    final currentPos = positive[replicaId.value] ?? 0;
    final updatedPos = Map<String, int>.from(positive);
    updatedPos[replicaId.value] = currentPos + amount;

    return PnCounter(
      positive: updatedPos,
      negative: negative,
    );
  }

  /// Decrements the counter by [amount] for [replicaId].
  PnCounter decrement(int amount, {required ReplicaId replicaId}) {
    if (amount <= 0) return this;
    final currentNeg = negative[replicaId.value] ?? 0;
    final updatedNeg = Map<String, int>.from(negative);
    updatedNeg[replicaId.value] = currentNeg + amount;

    return PnCounter(
      positive: positive,
      negative: updatedNeg,
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
      positive: mergedPos,
      negative: mergedNeg,
    );
  }

  /// Converts this PN-Counter to a serializable map.
  Map<String, dynamic> toMap() {
    return {
      'positive': Map<String, int>.from(positive),
      'negative': Map<String, int>.from(negative),
    };
  }

  /// Reconstitutes a PN-Counter from a map.
  /// Fails loudly with [FormatException] if any component total is negative (< 0).
  factory PnCounter.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PnCounter.empty();

    final rawPos = map['positive'];
    final pos = <String, int>{};
    if (rawPos is Map) {
      for (final entry in rawPos.entries) {
        final keyStr = entry.key.toString();
        final dynamic rawVal = entry.value;
        final int val;
        if (rawVal is num) {
          val = rawVal.toInt();
        } else if (rawVal != null) {
          final parsed = int.tryParse(rawVal.toString());
          if (parsed == null) {
            throw FormatException('Malformed non-integer component value in PnCounter positive map: $rawVal for key $keyStr');
          }
          val = parsed;
        } else {
          continue;
        }
        if (val < 0) {
          throw FormatException(
            'Malformed serialized PnCounter: component total must be non-negative (>= 0), got $val for key $keyStr in positive map',
          );
        }
        pos[keyStr] = val;
      }
    }

    final rawNeg = map['negative'];
    final neg = <String, int>{};
    if (rawNeg is Map) {
      for (final entry in rawNeg.entries) {
        final keyStr = entry.key.toString();
        final dynamic rawVal = entry.value;
        final int val;
        if (rawVal is num) {
          val = rawVal.toInt();
        } else if (rawVal != null) {
          final parsed = int.tryParse(rawVal.toString());
          if (parsed == null) {
            throw FormatException('Malformed non-integer component value in PnCounter negative map: $rawVal for key $keyStr');
          }
          val = parsed;
        } else {
          continue;
        }
        if (val < 0) {
          throw FormatException(
            'Malformed serialized PnCounter: component total must be non-negative (>= 0), got $val for key $keyStr in negative map',
          );
        }
        neg[keyStr] = val;
      }
    }

    return PnCounter(
      positive: pos,
      negative: neg,
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
        Object.hashAllUnordered(
            positive.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(
            negative.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'PnCounter(value: $value, P: $positive, N: $negative)';
}
