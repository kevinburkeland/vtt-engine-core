import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../crdt/crdt_lww_register.dart';
import '../../crdt/hybrid_logical_clock.dart';
import '../../utils/aggregate_join_utils.dart';
import '../../utils/deep_immutable.dart';

const _deepEquality = DeepCollectionEquality();

/// Generic tabletop entity instance representing any game piece, token, character,
/// prop, vehicle, meeple, or map element.
@immutable
class EntityInstance {
  final String instanceId;
  final String? entityDefinitionId;
  final String? entityType;
  final CrdtLwwRegister<String> displayNameRegister;
  final Map<String, dynamic>? position;
  final bool isVisible;
  final Map<String, dynamic> runtimeData;
  final Map<String, dynamic> customProperties;

  String get displayName => displayNameRegister.value;

  EntityInstance({
    required this.instanceId,
    this.entityDefinitionId,
    this.entityType,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    Map<String, dynamic>? position,
    this.isVisible = true,
    Map<String, dynamic> runtimeData = const {},
    Map<String, dynamic> customProperties = const {},
  })  : displayNameRegister = displayNameRegister ??
            (displayNameTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: displayName ?? '',
                    timestamp: displayNameTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: displayName ?? '',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        position = position != null ? deepFreezeMap(position) : null,
        runtimeData = deepFreezeMap(runtimeData),
        customProperties = deepFreezeMap(customProperties);

  const EntityInstance.empty()
      : instanceId = '',
        entityDefinitionId = null,
        entityType = null,
        displayNameRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        position = null,
        isVisible = true,
        runtimeData = const {},
        customProperties = const {};

  EntityInstance copyWith({
    String? instanceId,
    String? entityDefinitionId,
    String? entityType,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    Map<String, dynamic>? position,
    bool? isVisible,
    Map<String, dynamic>? runtimeData,
    Map<String, dynamic>? customProperties,
  }) {
    final CrdtLwwRegister<String> resolvedDisplayNameRegister;
    if (displayNameRegister != null) {
      resolvedDisplayNameRegister = displayNameRegister;
    } else if (displayName != null) {
      if (displayNameTimestamp == null) {
        throw ArgumentError(
          'Updating displayName via copyWith requires an authoritative displayNameTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedDisplayNameRegister = CrdtLwwRegister<String>(
        value: displayName,
        timestamp: displayNameTimestamp,
      );
    } else if (displayNameTimestamp != null) {
      throw ArgumentError(
        'Updating displayNameTimestamp via copyWith requires an authoritative displayName.',
      );
    } else {
      resolvedDisplayNameRegister = this.displayNameRegister;
    }

    return EntityInstance(
      instanceId: instanceId ?? this.instanceId,
      entityDefinitionId: entityDefinitionId ?? this.entityDefinitionId,
      entityType: entityType ?? this.entityType,
      displayNameRegister: resolvedDisplayNameRegister,
      position: position ?? this.position,
      isVisible: isVisible ?? this.isVisible,
      runtimeData: runtimeData != null
          ? Map.unmodifiable(runtimeData)
          : this.runtimeData,
      customProperties: customProperties != null
          ? Map.unmodifiable(customProperties)
          : this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'instanceId': instanceId,
        if (entityDefinitionId != null)
          'entityDefinitionId': entityDefinitionId,
        if (entityType != null) 'entityType': entityType,
        'displayName': displayName,
        'displayNameRegister': {
          'value': displayNameRegister.value,
          'timestamp': displayNameRegister.timestamp.toMap(),
        },
        if (position != null) 'position': position,
        'isVisible': isVisible,
        if (runtimeData.isNotEmpty) 'runtimeData': runtimeData,
        if (customProperties.isNotEmpty)
          'customProperties': customProperties,
      };

  factory EntityInstance.fromMap(Map<String, dynamic> map) {
    final CrdtLwwRegister<String> displayNameReg;
    if (map.containsKey('displayNameRegister')) {
      final rawReg = map['displayNameRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'EntityInstance.fromMap: "displayNameRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'EntityInstance.fromMap: "displayNameRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'EntityInstance.fromMap: "displayNameRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'EntityInstance.fromMap: "displayNameRegister" value cannot be null.',
        );
      }
      displayNameReg = CrdtLwwRegister<String>(
        value: rawVal.toString(),
        timestamp: timestamp,
      );
    } else {
      displayNameReg = CrdtLwwRegister<String>(
        value: map['displayName']?.toString() ?? '',
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    return EntityInstance(
      instanceId: map['instanceId']?.toString() ?? '',
      entityDefinitionId: map['entityDefinitionId']?.toString(),
      entityType: map['entityType']?.toString(),
      displayNameRegister: displayNameReg,
      position: map['position'] != null
          ? Map<String, dynamic>.from(map['position'] as Map)
          : null,
      isVisible: map['isVisible'] != false,
      runtimeData: Map<String, dynamic>.from(map['runtimeData'] as Map? ?? {}),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  /// Pure canonical aggregate join of two [EntityInstance] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  static EntityInstance join(EntityInstance a, EntityInstance b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedInstanceId = joinImmutableId(
      a.instanceId,
      b.instanceId,
      fieldName: 'EntityInstance.instanceId',
    );

    final mergedDefId = joinNullableString(
      a.entityDefinitionId,
      b.entityDefinitionId,
      fieldName: 'EntityInstance.entityDefinitionId',
    );

    final mergedType = joinNullableString(
      a.entityType,
      b.entityType,
      fieldName: 'EntityInstance.entityType',
    );

    final mergedDisplayName = a.displayNameRegister.merge(b.displayNameRegister);

    final mergedPosition = joinNullableMap(
      a.position,
      b.position,
      context: 'EntityInstance.position',
    );

    if (a.isVisible != b.isVisible) {
      throw StateError(
        'EntityInstance isVisible mismatch for "${a.instanceId}": '
        '${a.isVisible} vs ${b.isVisible}.',
      );
    }

    final mergedRuntimeData = joinCustomProperties(
      a.runtimeData,
      b.runtimeData,
      context: 'EntityInstance.runtimeData',
    );

    final mergedCustomProperties = joinCustomProperties(
      a.customProperties,
      b.customProperties,
      context: 'EntityInstance.customProperties',
    );

    return EntityInstance(
      instanceId: mergedInstanceId,
      entityDefinitionId: mergedDefId,
      entityType: mergedType,
      displayNameRegister: mergedDisplayName,
      position: mergedPosition,
      isVisible: a.isVisible,
      runtimeData: mergedRuntimeData,
      customProperties: mergedCustomProperties,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  EntityInstance merge(EntityInstance other) => EntityInstance.join(this, other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityInstance &&
          runtimeType == other.runtimeType &&
          instanceId == other.instanceId &&
          entityDefinitionId == other.entityDefinitionId &&
          entityType == other.entityType &&
          displayNameRegister == other.displayNameRegister &&
          _deepEquality.equals(position, other.position) &&
          isVisible == other.isVisible &&
          _deepEquality.equals(runtimeData, other.runtimeData) &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        instanceId,
        entityDefinitionId,
        entityType,
        displayNameRegister,
        _deepEquality.hash(position),
        isVisible,
        _deepEquality.hash(runtimeData),
        _deepEquality.hash(customProperties),
      );
}
