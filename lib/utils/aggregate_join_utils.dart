import 'package:collection/collection.dart';
import 'deep_immutable.dart';

const _deepEquality = DeepCollectionEquality();

/// Merges two unversioned strings symmetrically.
///
/// If both strings are identical, returns the string.
/// If one is empty and the other is non-empty, returns the non-empty string.
/// If both are non-empty and differ, throws [StateError] failing loudly and symmetrically.
String joinUnversionedString(
  String a,
  String b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  throw StateError(
    'Divergent unversioned scalar field "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically validates and merges two immutable identifiers.
///
/// If both identifiers match, returns the identifier.
/// If one is empty and the other is non-empty, returns the non-empty identifier.
/// If both are non-empty and differ, throws [StateError] failing loudly and symmetrically.
String joinImmutableId(
  String a,
  String b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  throw StateError(
    'Immutable identity field mismatch for "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically merges two nullable unversioned strings.
String? joinNullableString(
  String? a,
  String? b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a == null || a.isEmpty) return b;
  if (b == null || b.isEmpty) return a;
  throw StateError(
    'Divergent unversioned nullable scalar field "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically merges two JSON-like maps (e.g. `customProperties`, `permissions`, `runtimeData`)
/// with per-key ownership semantics.
///
/// Disjoint keys union deterministically with canonical sorted key ordering.
/// Same key with deep structural equality preserves the value.
/// Same key with divergent values without causal metadata fails loudly and symmetrically.
Map<String, dynamic> joinCustomProperties(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String context,
}) {
  if (identical(a, b)) return a;
  if (_deepEquality.equals(a, b)) return a;

  final allKeys = {...a.keys, ...b.keys}.toList()..sort();
  final result = <String, dynamic>{};
  for (final key in allKeys) {
    if (a.containsKey(key) && b.containsKey(key)) {
      final valA = a[key];
      final valB = b[key];
      if (!_deepEquality.equals(valA, valB)) {
        throw StateError(
          'Divergent unversioned value for key "$key" in $context: '
          '"$valA" vs "$valB".',
        );
      }
      result[key] = valA;
    } else if (a.containsKey(key)) {
      result[key] = a[key];
    } else {
      result[key] = b[key];
    }
  }
  return deepFreezeMap(result);
}

/// Symmetrically merges two nullable maps.
Map<String, dynamic>? joinNullableMap(
  Map<String, dynamic>? a,
  Map<String, dynamic>? b, {
  required String context,
}) {
  if (a == null && b == null) return null;
  if (a == null) return b != null ? deepFreezeMap(b) : null;
  if (b == null) return deepFreezeMap(a);
  return joinCustomProperties(a, b, context: context);
}
