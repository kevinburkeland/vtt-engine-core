import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'generic_tabletop_primitives.dart';
import 'core_types.dart';
import '../utils/deep_immutable.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) =>
    const ListEquality().equals(a, b);
bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);

/// Base contract for all identifiable domain entities.
abstract class DomainEntity {
  const DomainEntity();

  EntityId get id;
  String get name;
  EntityType get entityType;
  RulesetVersion get ruleset => id.ruleset;
  String get slug => id.slug;
  Map<String, dynamic> get customProperties;
  Map<String, dynamic> toMap();
}

/// Typed Lazy Pointer for Cross-Entity References.
typedef EntityRef<T extends DomainEntity> = EntityReference<T>;

/// Modern Dart Record representation for resolved or pending entity lookups.
typedef EntityLookup<T extends DomainEntity> = ({
  T? entity,
  String slug,
  EntityType refType,
  RulesetVersion? rulesetPreferred,
  String displayName,
  bool isResolved,
});

extension EntityLookupExtension<T extends DomainEntity> on EntityLookup<T> {
  String get resolvedName => entity?.name ?? displayName;
  T get requiredEntity {
    if (entity == null) {
      throw StateError('Unresolved entity lookup for $refType: $slug');
    }
    return entity!;
  }
}

@immutable
class EntityReference<T extends DomainEntity> {
  final EntityType refType;
  final String slug;
  final RulesetVersion? rulesetPreferred;
  final String displayName;
  final List<dynamic> grantedSkills;
  final Map<String, dynamic> customProperties;

  /// Optional pluggable hook for external compendium lookups when resolving traits.
  static ITraitDefinition? Function(String slug)? externalTraitResolver;

  EntityReference({
    required this.refType,
    required this.slug,
    required this.displayName,
    this.rulesetPreferred,
    List<dynamic>? grantedSkills,
    Map<String, dynamic>? customProperties,
  })  : grantedSkills = deepFreezeList(grantedSkills),
        customProperties = deepFreezeMap(customProperties);

  const EntityReference.empty({
    required this.refType,
    required this.slug,
    required this.displayName,
    this.rulesetPreferred,
  })  : grantedSkills = const [],
        customProperties = const {};

  /// Converts this entity reference into an agnostic trait definition, resolving
  /// metadata from available compendiums if needed.
  ITraitDefinition toTraitDefinition() {
    final externalDef = externalTraitResolver?.call(slug);
    final props = <String, dynamic>{
      if (externalDef?.properties['prerequisite'] != null)
        'prerequisite': externalDef!.properties['prerequisite'],
      ...?externalDef?.properties,
      ...customProperties,
    };
    return ITraitDefinition(
      id: slug,
      name: displayName.isNotEmpty
          ? displayName
          : (externalDef?.name ?? slug),
      category: refType.name,
      properties: props,
    );
  }

  Map<String, dynamic> toMap() => {
        'refType': refType.name,
        'slug': slug,
        'rulesetPreferred': rulesetPreferred?.name,
        'displayName': displayName,
        'grantedSkills':
            grantedSkills.map((s) => s is Enum ? s.name : s.toString()).toList(),
        if (customProperties.isNotEmpty) 'customProperties': customProperties,
      };

  factory EntityReference.fromMap(Map<String, dynamic> map) {
    final refTypeStr = map['refType']?.toString() ?? 'custom';
    final refType = EntityType(refTypeStr);

    RulesetVersion? ruleset;
    if (map['rulesetPreferred'] != null) {
      final rStr = map['rulesetPreferred'].toString();
      ruleset = RulesetVersion.values.firstWhere(
        (r) => r.name == rStr,
        orElse: () => RulesetVersion.homebrew,
      );
    }

    final rawSkills = map['grantedSkills'] as List?;
    final skills = (rawSkills ?? []).map((s) => s.toString()).toList();

    final customProps = map['customProperties'] is Map
        ? Map<String, dynamic>.from(map['customProperties'] as Map)
        : const <String, dynamic>{};

    return EntityReference<T>(
      refType: refType,
      slug: map['slug']?.toString() ?? '',
      displayName:
          map['displayName']?.toString() ?? map['slug']?.toString() ?? '',
      rulesetPreferred: ruleset,
      grantedSkills: skills,
      customProperties: customProps,
    );
  }

  EntityReference<T> copyWith({
    EntityType? refType,
    String? slug,
    RulesetVersion? rulesetPreferred,
    String? displayName,
    List<dynamic>? grantedSkills,
    Map<String, dynamic>? customProperties,
  }) {
    return EntityReference<T>(
      refType: refType ?? this.refType,
      slug: slug ?? this.slug,
      rulesetPreferred: rulesetPreferred ?? this.rulesetPreferred,
      displayName: displayName ?? this.displayName,
      grantedSkills: grantedSkills ?? this.grantedSkills,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  EntityReference<U> cast<U extends DomainEntity>() => EntityReference<U>(
        refType: refType,
        slug: slug,
        rulesetPreferred: rulesetPreferred,
        displayName: displayName,
        grantedSkills: grantedSkills,
        customProperties: customProperties,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityReference<T> &&
          runtimeType == other.runtimeType &&
          refType == other.refType &&
          slug == other.slug &&
          rulesetPreferred == other.rulesetPreferred &&
          displayName == other.displayName &&
          _listEquals(grantedSkills, other.grantedSkills) &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      refType.hashCode ^
      slug.hashCode ^
      rulesetPreferred.hashCode ^
      displayName.hashCode ^
      Object.hashAll(grantedSkills) ^
      Object.hashAll(customProperties.keys) ^
      Object.hashAll(customProperties.values);

  @override
  String toString() => 'Ref<$refType>($slug, pref: $rulesetPreferred)';
}

/// Null-Object Stub returned when a pointer cannot be resolved in the active stack.
class UnresolvedReference implements DomainEntity {
  @override
  final EntityId id;
  @override
  final String name;
  @override
  final EntityType entityType;
  final String reason;
  @override
  final Map<String, dynamic> customProperties;

  UnresolvedReference({
    required String slug,
    required this.entityType,
    this.reason = 'Entity not found in active priority stack',
    this.customProperties = const {},
  })  : id = EntityId(slug: slug, ruleset: RulesetVersion.homebrew),
        name = '[Missing ${entityType.name}: $slug]';

  @override
  RulesetVersion get ruleset => id.ruleset;
  @override
  String get slug => id.slug;

  @override
  Map<String, dynamic> toMap() => {
        'id': id.toMap(),
        'name': name,
        'entityType': entityType.name,
        'reason': reason,
        'customProperties': customProperties,
      };
}

/// Strongly typed result container for dynamic reference resolution.
@immutable
class ResolutionResult<T extends DomainEntity> {
  final T? entity;
  final UnresolvedReference? unresolved;

  const ResolutionResult.success(T this.entity) : unresolved = null;
  const ResolutionResult.missing(UnresolvedReference this.unresolved)
      : entity = null;

  bool get isResolved => entity != null;
  String get displayName => isResolved ? entity!.name : unresolved!.name;
  DomainEntity get value => isResolved ? entity! : unresolved!;
}
