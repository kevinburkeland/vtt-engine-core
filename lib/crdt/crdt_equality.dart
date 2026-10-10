import 'package:collection/collection.dart';

/// Canonical structural equality comparer for replicated CRDT payloads.
/// Treats JSON-like Maps, Lists, and Sets structurally while preserving
/// domain object operator == and primitive equality semantics.
/// Map and Set key ordering is unordered; List ordering remains significant.
const DeepCollectionEquality crdtPayloadEquality = DeepCollectionEquality();

/// Evaluates whether two CRDT payloads are structurally equivalent.
bool crdtPayloadEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  return crdtPayloadEquality.equals(a, b);
}

/// Generates a deterministic hash code for a CRDT payload consistent with [crdtPayloadEquals].
int crdtPayloadHash(dynamic a) {
  return crdtPayloadEquality.hash(a);
}
