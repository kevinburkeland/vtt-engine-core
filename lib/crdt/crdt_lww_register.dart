import 'package:meta/meta.dart';
import 'crdt_equality.dart';
import 'hybrid_logical_clock.dart';

/// Last-Write-Wins (LWW) Register CRDT primitive for single-value fields
/// (e.g. HP, Initiative). Uses [HybridLogicalClock] timestamps to deterministically
/// reconcile concurrent updates.
///
/// Merges follow standard LWW lattice join. When two registers possess exact identical
/// timestamps:
/// - If values match (structurally for JSON-like payloads), the merge is idempotent and returns this register.
/// - At the zero timestamp only (`timestamp.physicalTime == 0`), a tie between divergent values
///   resolves deterministically using a canonical, type-tagged total order.
///   Two String values compare by plain string order, and null sorts above every String.
///   If two divergent values produce identical canonical encodings, or a value cannot be
///   canonically encoded, merge throws [StateError] symmetrically from both orders.
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
  /// a tie between divergent values resolves deterministically using a canonical type-tagged
  /// total order on the encoded value.
  /// Ties at any non-zero timestamp keep throwing [StateError] on collision.
  CrdtLwwRegister<T> merge(CrdtLwwRegister<T> remote) {
    if (timestamp == remote.timestamp) {
      if (crdtPayloadEquals(value, remote.value)) {
        return this;
      }
      if (timestamp.physicalTime == 0) {
        final localEnc = _encodeValue(value);
        final remoteEnc = _encodeValue(remote.value);
        if (localEnc == remoteEnc) {
          throw StateError(
            'CRDT Collision: CrdtLwwRegister merge detected identical canonical encoding '
            'for divergent values at physical time 0: "$value" vs "${remote.value}".',
          );
        }
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

  static String _encodeValue(Object? val) {
    try {
      return _encodeCanonical(val);
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError(
        'CRDT Collision: value cannot be canonically encoded for tie-breaking: $val ($e)',
      );
    }
  }

  static String _encodeCanonical(Object? val) {
    if (val == null) return 'z:null';
    if (val is String) return 's:$val';
    if (val is bool) return 'b:$val';
    if (val is num) {
      if (val.isNaN) {
        throw StateError(
          'CRDT Collision: NaN cannot be canonically encoded for tie-breaking.',
        );
      }
      return 'n:$val';
    }
    if (val is List) {
      final b = StringBuffer('l:');
      for (final item in val) {
        final enc = _encodeCanonical(item);
        b.write('${enc.length}:$enc;');
      }
      return b.toString();
    }
    if (val is Map) {
      final b = StringBuffer('m:');
      final sortedKeys = val.keys.map((k) => k.toString()).toList()..sort();
      for (final k in sortedKeys) {
        final enc = _encodeCanonical(val[k]);
        b.write('${k.length}:$k=${enc.length}:$enc;');
      }
      return b.toString();
    }
    // Attempt object-via-toMap
    try {
      // ignore: avoid_dynamic_calls
      final dynamic m = (val as dynamic).toMap();
      if (m is Map) {
        final b = StringBuffer('o:');
        final sortedKeys = m.keys.map((k) => k.toString()).toList()..sort();
        for (final k in sortedKeys) {
          final enc = _encodeCanonical(m[k]);
          b.write('${k.length}:$k=${enc.length}:$enc;');
        }
        return b.toString();
      }
    } catch (_) {
      // Fall through to throw StateError
    }
    throw StateError(
      'CRDT Collision: Type ${val.runtimeType} cannot be canonically encoded for tie-breaking.',
    );
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
