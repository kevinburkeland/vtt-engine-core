import 'dart:convert';
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
/// - At the zero timestamp only (`timestamp.physicalTime == 0`), a tie between different values
///   resolves by a deterministic total order on the encoded value.
/// - At any non-zero timestamp, divergent values represent an invariant violation/invalid collision
///   and fail loudly and symmetrically with a [StateError].
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
  /// is strictly after the local timestamp.
  ///
  /// Documented compatibility rule: At the zero timestamp only (`timestamp.physicalTime == 0`),
  /// a tie between different values resolves by a deterministic total order on the encoded value.
  /// Ties at any non-zero timestamp keep throwing [StateError] on collision.
  CrdtLwwRegister<T> merge(CrdtLwwRegister<T> remote) {
    if (timestamp == remote.timestamp) {
      if (crdtPayloadEquals(value, remote.value)) {
        return this;
      }
      if (timestamp.physicalTime == 0) {
        final localEnc = _encodeValue(value);
        final remoteEnc = _encodeValue(remote.value);
        final cmp = localEnc.compareTo(remoteEnc);
        if (cmp < 0) {
          return remote;
        } else {
          return this;
        }
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

  static String _encodeValue(dynamic val) {
    if (val == null) return 'null';
    if (val is String) return val;
    if (val is num || val is bool) return val.toString();
    try {
      return json.encode(_canonicalize(val));
    } catch (_) {
      return val.toString();
    }
  }

  static Object? _canonicalize(dynamic v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is List) return v.map(_canonicalize).toList();
    if (v is Map) {
      final sortedKeys = v.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final k in sortedKeys) k: _canonicalize(v[k]),
      };
    }
    try {
      // ignore: avoid_dynamic_calls
      final dynamic m = (v as dynamic).toMap();
      return _canonicalize(m);
    } catch (_) {
      return v.toString();
    }
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
