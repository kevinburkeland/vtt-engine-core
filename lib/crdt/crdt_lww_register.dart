import 'package:meta/meta.dart';
import 'hybrid_logical_clock.dart';

/// Last-Write-Wins (LWW) Register CRDT primitive for single-value fields
/// (e.g. HP, Initiative). Uses [HybridLogicalClock] timestamps to deterministically
/// reconcile concurrent updates.
///
/// IMPORTANT: The type [T] MUST be a deeply immutable value object or primitive.
/// Mutating [T] internally bypasses the HLC timestamp and breaks distributed consensus.
@immutable
class CrdtLwwRegister<T> {
  final T value;
  final HybridLogicalClock timestamp;

  const CrdtLwwRegister({
    required this.value,
    required this.timestamp,
  });

  /// Returns a new register instance with the updated value and timestamp.
  CrdtLwwRegister<T> set(T newValue, HybridLogicalClock newTimestamp) {
    return CrdtLwwRegister(value: newValue, timestamp: newTimestamp);
  }

  /// Merges with a remote register, adopting the remote value if its timestamp
  /// is strictly after the local timestamp.
  CrdtLwwRegister<T> merge(CrdtLwwRegister<T> remote) {
    if (remote.timestamp.isAfter(timestamp)) {
      return remote;
    }
    return this;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrdtLwwRegister<T> &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          timestamp == other.timestamp;

  @override
  int get hashCode => value.hashCode ^ timestamp.hashCode;

  @override
  String toString() => 'CrdtLwwRegister(value: $value, ts: $timestamp)';
}
