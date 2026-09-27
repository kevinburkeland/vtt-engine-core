import 'package:meta/meta.dart';
import 'core_types.dart';
import 'entity_reference.dart';

/// Generic Tabletop Item Domain Model for ruleset-agnostic inventory and items.
@immutable
class GenericItem extends DomainEntity {
  @override
  final EntityId id;
  @override
  final String name;
  final String itemType;
  final String descriptionMarkdown;
  @override
  final Map<String, dynamic> customProperties;

  const GenericItem({
    required this.id,
    required this.name,
    this.itemType = 'Item',
    this.descriptionMarkdown = '',
    this.customProperties = const {},
  });

  @override
  EntityType get entityType => EntityType.item;

  @override
  Map<String, dynamic> toMap() => {
        'id': id.toMap(),
        'name': name,
        'itemType': itemType,
        'descriptionMarkdown': descriptionMarkdown,
        'customProperties': customProperties,
      };

  factory GenericItem.fromMap(Map<String, dynamic> map) {
    return GenericItem(
      id: EntityId.fromMap(Map<String, dynamic>.from(map['id'] as Map? ?? {})),
      name: map['name']?.toString() ?? '',
      itemType: map['itemType']?.toString() ?? 'Item',
      descriptionMarkdown: map['descriptionMarkdown']?.toString() ?? '',
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  GenericItem copyWith({
    EntityId? id,
    String? name,
    String? itemType,
    String? descriptionMarkdown,
    Map<String, dynamic>? customProperties,
  }) {
    return GenericItem(
      id: id ?? this.id,
      name: name ?? this.name,
      itemType: itemType ?? this.itemType,
      descriptionMarkdown: descriptionMarkdown ?? this.descriptionMarkdown,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericItem &&
          id == other.id &&
          name == other.name &&
          itemType == other.itemType &&
          descriptionMarkdown == other.descriptionMarkdown;

  @override
  int get hashCode => Object.hash(id, name, itemType, descriptionMarkdown);
}
