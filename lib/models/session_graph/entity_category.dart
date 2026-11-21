import 'package:meta/meta.dart';

/// Pure ruleset-agnostic categorical classification of entity links or tokens.
@immutable
class EntityCategory {
  final String key;
  final String displayName;

  const EntityCategory(this.key, [String? displayName])
      : displayName = displayName ?? key;

  static const EntityCategory generic = EntityCategory('generic', 'Generic');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityCategory && key == other.key);

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}
