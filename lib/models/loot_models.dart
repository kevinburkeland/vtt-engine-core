import 'package:collection/collection.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/hybrid_logical_clock.dart';
import '../utils/deep_immutable.dart';
import '../utils/aggregate_join_utils.dart';
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
  final CrdtLwwRegister<String> nameRegister;
  final LootContainerType type;
  final bool isLocked;
  final double? capacityWeightLbs;
  final List<InventoryItemInstance> items;
  final PartyPurse purse;
  final Map<String, dynamic> permissions;
  final Map<String, dynamic> customProperties;

  String get name => nameRegister.value;

  LootContainer({
    required this.containerId,
    String? name,
    CrdtLwwRegister<String>? nameRegister,
    HybridLogicalClock? nameTimestamp,
    this.type = LootContainerType.chest,
    this.isLocked = false,
    this.capacityWeightLbs,
    List<InventoryItemInstance> items = const [],
    this.purse = const PartyPurse.empty(),
    Map<String, dynamic> permissions = const {},
    Map<String, dynamic> customProperties = const {},
  })  : nameRegister = nameRegister ??
            (nameTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: name ?? 'Chest',
                    timestamp: nameTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: name ?? 'Chest',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        items = List<InventoryItemInstance>.unmodifiable(items),
        permissions = deepFreezeMap(permissions),
        customProperties = deepFreezeMap(customProperties);

  const LootContainer.empty()
      : containerId = '',
        nameRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
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
    CrdtLwwRegister<String>? nameRegister,
    HybridLogicalClock? nameTimestamp,
    LootContainerType? type,
    bool? isLocked,
    double? capacityWeightLbs,
    List<InventoryItemInstance>? items,
    PartyPurse? purse,
    Map<String, dynamic>? permissions,
    Map<String, dynamic>? customProperties,
  }) {
    final CrdtLwwRegister<String> resolvedNameRegister;
    if (nameRegister != null) {
      resolvedNameRegister = nameRegister;
    } else if (name != null) {
      if (nameTimestamp == null) {
        throw ArgumentError(
          'Updating name via copyWith requires an authoritative nameTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNameRegister = CrdtLwwRegister<String>(
        value: name,
        timestamp: nameTimestamp,
      );
    } else if (nameTimestamp != null) {
      throw ArgumentError(
        'Updating nameTimestamp via copyWith requires an authoritative name.',
      );
    } else {
      resolvedNameRegister = this.nameRegister;
    }

    return LootContainer(
      containerId: containerId ?? this.containerId,
      nameRegister: resolvedNameRegister,
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
        'nameRegister': {
          'value': nameRegister.value,
          'timestamp': nameRegister.timestamp.toMap(),
        },
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

    final CrdtLwwRegister<String> nameReg;
    if (map.containsKey('nameRegister')) {
      final rawReg = map['nameRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'LootContainer.fromMap: "nameRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'LootContainer.fromMap: "nameRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'LootContainer.fromMap: "nameRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'LootContainer.fromMap: "nameRegister" value cannot be null.',
        );
      }
      nameReg = CrdtLwwRegister<String>(
        value: rawVal.toString(),
        timestamp: timestamp,
      );
    } else {
      nameReg = CrdtLwwRegister<String>(
        value: map['name']?.toString() ?? 'Chest',
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    return LootContainer(
      containerId: map['containerId']?.toString() ?? '',
      nameRegister: nameReg,
      type: type,
      isLocked: map['isLocked'] == true,
      capacityWeightLbs: (map['capacityWeightLbs'] as num?)?.toDouble(),
      items: (map['items'] as List? ?? [])
          .whereType<Map<dynamic, dynamic>>()
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

  /// Pure canonical aggregate join of two [LootContainer] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  /// Incompatible immutable properties or divergent unversioned fields fail loudly and symmetrically.
  static LootContainer join(LootContainer a, LootContainer b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedId = joinImmutableId(
      a.containerId,
      b.containerId,
      fieldName: 'LootContainer.containerId',
    );

    if (a.type != b.type) {
      throw StateError(
        'LootContainer type mismatch for "${a.containerId}": '
        '${a.type} vs ${b.type}.',
      );
    }

    if (a.isLocked != b.isLocked) {
      throw StateError(
        'LootContainer isLocked mismatch for "${a.containerId}": '
        '${a.isLocked} vs ${b.isLocked}.',
      );
    }

    if (a.capacityWeightLbs != b.capacityWeightLbs) {
      if (a.capacityWeightLbs != null && b.capacityWeightLbs != null) {
        throw StateError(
          'LootContainer capacityWeightLbs mismatch for "${a.containerId}": '
          '${a.capacityWeightLbs} vs ${b.capacityWeightLbs}.',
        );
      }
    }
    final mergedCapacity = a.capacityWeightLbs ?? b.capacityWeightLbs;

    final mergedName = a.nameRegister.merge(b.nameRegister);

    final itemsMapA = <String, InventoryItemInstance>{};
    for (final i in a.items) {
      itemsMapA[i.instanceId] = i;
    }
    final itemsMapB = <String, InventoryItemInstance>{};
    for (final i in b.items) {
      itemsMapB[i.instanceId] = i;
    }

    final allItemIds = <String>{...itemsMapA.keys, ...itemsMapB.keys}.toList()..sort();
    final mergedItems = <InventoryItemInstance>[];
    for (final id in allItemIds) {
      final itemA = itemsMapA[id];
      final itemB = itemsMapB[id];
      if (itemA != null && itemB != null) {
        if (itemA != itemB) {
          throw StateError(
            'Divergent InventoryItemInstance under same instanceId "$id" in container "${a.containerId}".',
          );
        }
        mergedItems.add(itemA);
      } else if (itemA != null) {
        mergedItems.add(itemA);
      } else if (itemB != null) {
        mergedItems.add(itemB);
      }
    }

    final mergedPurse = a.purse.merge(b.purse);

    final mergedPermissions = joinCustomProperties(
      a.permissions,
      b.permissions,
      context: 'LootContainer.permissions',
    );

    final mergedCustomProperties = joinCustomProperties(
      a.customProperties,
      b.customProperties,
      context: 'LootContainer.customProperties',
    );

    return LootContainer(
      containerId: mergedId,
      nameRegister: mergedName,
      type: a.type,
      isLocked: a.isLocked,
      capacityWeightLbs: mergedCapacity,
      items: mergedItems,
      purse: mergedPurse,
      permissions: mergedPermissions,
      customProperties: mergedCustomProperties,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  LootContainer merge(LootContainer other) => LootContainer.join(this, other);

  static const _deepEquality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LootContainer &&
          runtimeType == other.runtimeType &&
          containerId == other.containerId &&
          nameRegister == other.nameRegister &&
          type == other.type &&
          isLocked == other.isLocked &&
          capacityWeightLbs == other.capacityWeightLbs &&
          _deepEquality.equals(items, other.items) &&
          purse == other.purse &&
          _deepEquality.equals(permissions, other.permissions) &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        containerId,
        nameRegister,
        type,
        isLocked,
        capacityWeightLbs,
        _deepEquality.hash(items),
        purse,
        _deepEquality.hash(permissions),
        _deepEquality.hash(customProperties),
      );
}
