/// Pure-Dart recursive defensive-copying utility for JSON-like dynamic values
/// participating in replicated state.
///
/// Recursively handles:
/// - [Map]: returns an unmodifiable Map with recursively deep-frozen entries.
/// - [List]: returns an unmodifiable List with recursively deep-frozen elements,
///   preserving common element types (e.g. List<String>) when possible.
/// - [Set]: returns an unmodifiable Set with recursively deep-frozen elements,
///   preserving common element types (e.g. Set<String>) when possible.
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
/// returning an unmodifiable [List<dynamic>] (or typed [List<T>] when homogeneous).
List<dynamic> deepFreezeList(Iterable<dynamic>? list) {
  if (list == null || list.isEmpty) {
    if (list is List<String>) return const <String>[];
    if (list is List<int>) return const <int>[];
    if (list is List<double>) return const <double>[];
    if (list is List<num>) return const <num>[];
    if (list is List<bool>) return const <bool>[];
    return const <dynamic>[];
  }
  final copy = <dynamic>[];
  for (final item in list) {
    copy.add(deepFreezeValue(item));
  }
  if (list is List<String> || copy.every((e) => e is String)) {
    return List<String>.unmodifiable(copy.cast<String>());
  }
  if (list is List<num> && list is! List<int> && list is! List<double>) {
    return List<num>.unmodifiable(copy.cast<num>());
  }
  if (list is List<int> || copy.every((e) => e is int)) {
    return List<int>.unmodifiable(copy.cast<int>());
  }
  if (list is List<double> || copy.every((e) => e is double)) {
    return List<double>.unmodifiable(copy.cast<double>());
  }
  if (list is List<num> || copy.every((e) => e is num)) {
    return List<num>.unmodifiable(copy.cast<num>());
  }
  if (list is List<bool> || copy.every((e) => e is bool)) {
    return List<bool>.unmodifiable(copy.cast<bool>());
  }
  return List<dynamic>.unmodifiable(copy);
}

/// Recursively defensively copies an iterable/set and its nested collections,
/// returning an unmodifiable [Set<dynamic>] (or typed [Set<T>] when homogeneous).
Set<dynamic> deepFreezeSet(Iterable<dynamic>? set) {
  if (set == null || set.isEmpty) {
    if (set is Set<String>) return const <String>{};
    if (set is Set<int>) return const <int>{};
    if (set is Set<double>) return const <double>{};
    if (set is Set<num>) return const <num>{};
    if (set is Set<bool>) return const <bool>{};
    return const <dynamic>{};
  }
  final copy = <dynamic>{};
  for (final item in set) {
    copy.add(deepFreezeValue(item));
  }
  if (set is Set<String> || copy.every((e) => e is String)) {
    return Set<String>.unmodifiable(copy.cast<String>());
  }
  if (set is Set<num> && set is! Set<int> && set is! Set<double>) {
    return Set<num>.unmodifiable(copy.cast<num>());
  }
  if (set is Set<int> || copy.every((e) => e is int)) {
    return Set<int>.unmodifiable(copy.cast<int>());
  }
  if (set is Set<double> || copy.every((e) => e is double)) {
    return Set<double>.unmodifiable(copy.cast<double>());
  }
  if (set is Set<num> || copy.every((e) => e is num)) {
    return Set<num>.unmodifiable(copy.cast<num>());
  }
  if (set is Set<bool> || copy.every((e) => e is bool)) {
    return Set<bool>.unmodifiable(copy.cast<bool>());
  }
  return Set<dynamic>.unmodifiable(copy);
}
