import 'package:meta/meta.dart';
import '../homebrew/value_objects/ruleset_version.dart';
export '../homebrew/value_objects/ruleset_version.dart';

/// Generic Extensible Entity Type Classification.
@immutable
class EntityType {
  final String key;
  const EntityType(this.key);

  static const EntityType character = EntityType('character');
  static const EntityType item = EntityType('item');
  static const EntityType custom = EntityType('custom');

  String get name => key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityType && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// Standardized Duration Types for generic tabletop activation and effects.
enum DurationType {
  instantaneous,
  rounds,
  timed,
  permanent,
  special,
}

/// Composite Entity Identifier supporting multi-ruleset coexistence.
@immutable
class EntityId {
  final String slug;
  final RulesetVersion ruleset;

  const EntityId({
    required this.slug,
    required this.ruleset,
  });

  Map<String, dynamic> toMap() => {
        'slug': slug,
        'ruleset': ruleset.name,
      };

  factory EntityId.fromMap(Map<String, dynamic> map) {
    final rulesetStr = map['ruleset']?.toString() ?? 'homebrew';
    final ruleset = RulesetVersion.values.firstWhere(
      (r) => r.name == rulesetStr,
      orElse: () => RulesetVersion.homebrew,
    );
    return EntityId(
      slug: map['slug']?.toString() ?? '',
      ruleset: ruleset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityId &&
          runtimeType == other.runtimeType &&
          slug == other.slug &&
          ruleset == other.ruleset;

  @override
  int get hashCode => slug.hashCode ^ ruleset.hashCode;

  @override
  String toString() => '$slug (${ruleset.name})';
}
