import 'package:meta/meta.dart';

/// Pure Dart immutable value object representing a durable, unique CRDT replica identity.
///
/// Invariant: Must not be empty, whitespace-only, or the literal 'local'.
@immutable
class ReplicaId implements Comparable<ReplicaId> {
  final String value;

  ReplicaId(String raw) : value = _validate(raw);

  /// Unchecked constructor for internal serialization or constant fixtures where
  /// the string has already been validated.
  const ReplicaId.unsafe(this.value);

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
