/// Pure-Dart recursive defensive-copying utility for JSON-like dynamic values
/// participating in replicated state.
///
/// Recursively handles:
/// - [Map]: returns an unmodifiable Map with recursively deep-frozen entries.
/// - [List]: returns an unmodifiable List with recursively deep-frozen elements.
/// - [Set]: returns an unmodifiable Set with recursively deep-frozen elements.
///
/// Leaves (primitives, strings, numbers, booleans, enums, null, and immutable value objects)
/// are returned as-is.
///
/// NOTE: Arbitrary user-defined mutable objects must not be stored directly into
/// dynamic metadata fields without serialization to Maps/Lists or encapsulation
/// in an immutable value type. Arbitrary unknown mutable objects cannot be
/// deep-frozen by this helper and are retained as-is with a documented warning.
dynamic deepFreezeValue(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    return deepFreezeMap(value);
  }
  if (value is List) {
    return deepFreezeList(value);
  }
  if (value is Set) {
    return deepFreezeSet(value);
  }
  return value;
}

/// Recursively defensively copies a [Map] and its nested collections,
/// returning an unmodifiable [Map<String, dynamic>].
Map<String, dynamic> deepFreezeMap(Map<dynamic, dynamic>? map) {
  if (map == null || map.isEmpty) return const <String, dynamic>{};
  final copy = <String, dynamic>{};
  for (final entry in map.entries) {
    copy[entry.key.toString()] = deepFreezeValue(entry.value);
  }
  return Map<String, dynamic>.unmodifiable(copy);
}

/// Recursively defensively copies an iterable/list and its nested collections,
/// returning an unmodifiable [List<dynamic>].
List<dynamic> deepFreezeList(Iterable<dynamic>? list) {
  if (list == null || list.isEmpty) return const <dynamic>[];
  final copy = <dynamic>[];
  for (final item in list) {
    copy.add(deepFreezeValue(item));
  }
  return List<dynamic>.unmodifiable(copy);
}

/// Recursively defensively copies an iterable/set and its nested collections,
/// returning an unmodifiable [Set<dynamic>].
Set<dynamic> deepFreezeSet(Iterable<dynamic>? set) {
  if (set == null || set.isEmpty) return const <dynamic>{};
  final copy = <dynamic>{};
  for (final item in set) {
    copy.add(deepFreezeValue(item));
  }
  return Set<dynamic>.unmodifiable(copy);
}
