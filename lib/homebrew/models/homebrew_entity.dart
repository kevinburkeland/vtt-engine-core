import 'package:collection/collection.dart';
import '../../utils/deep_immutable.dart';
import 'package:meta/meta.dart';
import '../value_objects/ruleset_version.dart';

/// Pure Domain Entity representing a validated homebrew element.
///
/// Fully decoupled from Flutter runtime and persister details.
@immutable
class HomebrewEntity {
  final String id;
  final String name;
  final String entityType;
  final RulesetVersion ruleset;
  final Map<String, dynamic> rawPayload;
  final Map<String, dynamic> normalizedData;
  final Map<String, dynamic> unparsedPayload;

  HomebrewEntity({
    required this.id,
    required this.name,
    required this.entityType,
    required this.ruleset,
    Map<String, dynamic> rawPayload = const {},
    Map<String, dynamic> normalizedData = const {},
    Map<String, dynamic> unparsedPayload = const {},
  })  : rawPayload = deepFreezeMap(rawPayload),
        normalizedData = deepFreezeMap(normalizedData),
        unparsedPayload = deepFreezeMap(unparsedPayload);

  const HomebrewEntity.empty()
      : id = '',
        name = '',
        entityType = '',
        ruleset = RulesetVersion.homebrew,
        rawPayload = const {},
        normalizedData = const {},
        unparsedPayload = const {};

  HomebrewEntity copyWith({
    String? id,
    String? name,
    String? entityType,
    RulesetVersion? ruleset,
    Map<String, dynamic>? rawPayload,
    Map<String, dynamic>? normalizedData,
    Map<String, dynamic>? unparsedPayload,
  }) {
    return HomebrewEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      entityType: entityType ?? this.entityType,
      ruleset: ruleset ?? this.ruleset,
      rawPayload: rawPayload ?? this.rawPayload,
      normalizedData: normalizedData ?? this.normalizedData,
      unparsedPayload: unparsedPayload ?? this.unparsedPayload,
    );
  }

  static const _deepEquality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomebrewEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          entityType == other.entityType &&
          ruleset == other.ruleset &&
          _deepEquality.equals(rawPayload, other.rawPayload) &&
          _deepEquality.equals(normalizedData, other.normalizedData) &&
          _deepEquality.equals(unparsedPayload, other.unparsedPayload);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        entityType,
        ruleset,
        _deepEquality.hash(rawPayload),
        _deepEquality.hash(normalizedData),
        _deepEquality.hash(unparsedPayload),
      );

  @override
  String toString() =>
      'HomebrewEntity(id: $id, name: "$name", type: $entityType, ruleset: ${ruleset.name})';
}
