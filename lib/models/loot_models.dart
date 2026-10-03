import 'package:meta/meta.dart';
import 'character_models.dart';
import 'party_purse.dart';

/// Classification of loot storage containers
enum LootContainerType {
  chest,
  corpse,
  merchant,
  roomPool,
  cache;

  String get displayName => switch (this) {
        LootContainerType.chest => 'Chest',
        LootContainerType.corpse => 'Lootable Remains',
        LootContainerType.merchant => 'Merchant Inventory',
        LootContainerType.roomPool => 'Room Loot Pool',
        LootContainerType.cache => 'Hidden Cache',
      };
}

/// Standalone Loot Container, Merchant Inventory, or Room-Level Loot Pool
@immutable
class LootContainer {
  final String containerId;
  final String name;
  final LootContainerType type;
  final bool isLocked;
  final double? capacityWeightLbs;
  final List<InventoryItemInstance> items;
  final PartyPurse purse;
  final Map<String, dynamic> permissions;
  final Map<String, dynamic> customProperties;

  LootContainer({
    required this.containerId,
    required this.name,
    this.type = LootContainerType.chest,
    this.isLocked = false,
    this.capacityWeightLbs,
    List<InventoryItemInstance> items = const [],
    this.purse = const PartyPurse.empty(),
    Map<String, dynamic> permissions = const {},
    Map<String, dynamic> customProperties = const {},
  })  : items = List.unmodifiable(items),
        permissions =
            Map.unmodifiable(Map<String, dynamic>.from(permissions)),
        customProperties =
            Map.unmodifiable(Map<String, dynamic>.from(customProperties));

  const LootContainer.empty()
      : containerId = '',
        name = '',
        type = LootContainerType.chest,
        isLocked = false,
        capacityWeightLbs = null,
        items = const [],
        purse = const PartyPurse.empty(),
        permissions = const {},
        customProperties = const {};

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  bool get isEmpty => items.isEmpty && purse.isEmpty;

  LootContainer copyWith({
    String? containerId,
    String? name,
    LootContainerType? type,
    bool? isLocked,
    double? capacityWeightLbs,
    List<InventoryItemInstance>? items,
    PartyPurse? purse,
    Map<String, dynamic>? permissions,
    Map<String, dynamic>? customProperties,
  }) {
    return LootContainer(
      containerId: containerId ?? this.containerId,
      name: name ?? this.name,
      type: type ?? this.type,
      isLocked: isLocked ?? this.isLocked,
      capacityWeightLbs: capacityWeightLbs ?? this.capacityWeightLbs,
      items:
          items != null ? List<InventoryItemInstance>.from(items) : this.items,
      purse: purse ?? this.purse,
      permissions: permissions != null
          ? Map<String, dynamic>.from(permissions)
          : this.permissions,
      customProperties: customProperties != null
          ? Map<String, dynamic>.from(customProperties)
          : this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'containerId': containerId,
        'name': name,
        'type': type.name,
        'isLocked': isLocked,
        'capacityWeightLbs': capacityWeightLbs,
        'items': items.map((i) => i.toMap()).toList(),
        'purse': purse.toMap(),
        'permissions': permissions,
        'customProperties': customProperties,
      };

  factory LootContainer.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type']?.toString() ?? 'chest';
    final type = LootContainerType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => LootContainerType.chest,
    );

    return LootContainer(
      containerId: map['containerId']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Chest',
      type: type,
      isLocked: map['isLocked'] == true,
      capacityWeightLbs: (map['capacityWeightLbs'] as num?)?.toDouble(),
      items: (map['items'] as List? ?? [])
          .whereType<Map>()
          .map((i) =>
              InventoryItemInstance.fromMap(Map<String, dynamic>.from(i)))
          .toList(),
      purse: map['purse'] != null
          ? PartyPurse.fromMap(
              Map<String, dynamic>.from(map['purse'] as Map? ?? {}))
          : const PartyPurse.empty(),
      permissions: Map<String, dynamic>.from(map['permissions'] as Map? ?? {}),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }
}
