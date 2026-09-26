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

  const HomebrewEntity({
    required this.id,
    required this.name,
    required this.entityType,
    required this.ruleset,
    this.rawPayload = const {},
    this.normalizedData = const {},
    this.unparsedPayload = const {},
  });

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomebrewEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          entityType == other.entityType &&
          ruleset == other.ruleset;

  @override
  int get hashCode => Object.hash(id, name, entityType, ruleset);

  @override
  String toString() =>
      'HomebrewEntity(id: $id, name: "$name", type: $entityType, ruleset: ${ruleset.name})';
}
