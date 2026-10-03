import 'package:meta/meta.dart';

/// Pure Dart immutable value object representing the unique identity of one
/// independently executing CRDT writer/runtime.
///
/// ### Architectural Invariant: Active Writer Identity
/// A [ReplicaId] uniquely identifies an **active executing runtime/writer** that
/// originates state-based CRDT mutations (such as PN-counters and HLC timestamps).
///
/// It is **NOT**:
/// - a campaign identity
/// - a user identity
/// - a durable browser-installation or device identity
/// - a room identity
/// - a transport fallback string
/// - a generic node-name string
///
/// ### Multi-Process / Multi-Tab Concurrency
/// Durable storage identity (such as a database or device installation ID) must NOT
/// be reused as an active [ReplicaId]. For state-based PN-counters, each component
/// vector represents a single-writer monotonic stream. If two concurrent browser
/// tabs or processes were to share the same writer identity, their concurrent
/// updates would be collapsed via lattice join (`max`), silently dropping mutations.
///
/// Therefore:
/// - Durable installation/device identity identifies storage/installation context.
/// - [ReplicaId] identifies an active, independently executing CRDT writer instance.
/// - Two concurrent runtimes sharing the same storage MUST have distinct [ReplicaId]s.
/// - A historical component ID in serialized state is data, not authority to write that component again.
///
/// Invariant: Must not be empty, whitespace-only, or the literal 'local'.
@immutable
class ReplicaId implements Comparable<ReplicaId> {
  final String value;

  ReplicaId(String raw) : value = _validate(raw);

  static String _validate(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(
          raw, 'raw', 'ReplicaId cannot be empty or whitespace.');
    }
    if (clean.toLowerCase() == 'local') {
      throw ArgumentError.value(
          raw, 'raw', 'ReplicaId cannot be the literal "local".');
    }
    return clean;
  }

  @override
  int compareTo(ReplicaId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ReplicaId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
