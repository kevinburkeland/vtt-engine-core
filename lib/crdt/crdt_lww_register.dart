import 'package:meta/meta.dart';
import 'crdt_equality.dart';
import 'hybrid_logical_clock.dart';

/// Last-Write-Wins (LWW) Register CRDT primitive for single-value fields
/// (e.g. HP, Initiative). Uses [HybridLogicalClock] timestamps to deterministically
/// reconcile concurrent updates.
///
/// Merges follow standard LWW lattice join. When two registers possess exact identical
/// timestamps:
/// - If values match (structurally for JSON-like payloads), the merge is idempotent and returns the value.
/// - If values diverge, this represents an invariant violation/invalid collision and fails
///   loudly and symmetrically with a [StateError].
///
/// IMPORTANT: The type [T] MUST be a deeply immutable value object, collection, or primitive.
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
  /// is strictly after the local timestamp. Fails loudly on identical timestamp collisions
  /// with divergent values.
  CrdtLwwRegister<T> merge(CrdtLwwRegister<T> remote) {
    if (timestamp == remote.timestamp) {
      if (crdtPayloadEquals(value, remote.value)) {
        return this;
      }
      throw StateError(
        'CRDT Collision: CrdtLwwRegister merge detected identical timestamp '
        '$timestamp with divergent values: "$value" vs "${remote.value}".',
      );
    }
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
          timestamp == other.timestamp &&
          crdtPayloadEquals(value, other.value);

  @override
  int get hashCode => crdtPayloadHash(value) ^ timestamp.hashCode;

  @override
  String toString() => 'CrdtLwwRegister(value: $value, ts: $timestamp)';
}
