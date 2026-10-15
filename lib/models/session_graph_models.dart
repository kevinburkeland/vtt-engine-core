

import '../utils/deep_immutable.dart';
import '../utils/aggregate_join_utils.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import 'loot_models.dart';
import 'entity_link_crdt_set.dart';
export 'entity_link_crdt_set.dart';

const _deepEquality = DeepCollectionEquality();

String _resolveMinionId(dynamic m) {
  if (m == null) return '';
  if (m is Map) return (m['id'] ?? '').toString();
  try {
    return ((m as dynamic).id ?? '').toString();
  } catch (_) {
    return '';
  }
}

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

/// Contextual pointer linking characters, tokens, objects, or zones to a room or graph node
@immutable
class RoomEntityLink {
  static const Object _sentinel = Object();

  final dynamic refType;
  final String entityId;
  final CrdtLwwRegister<String> displayNameRegister;
  final CrdtLwwRegister<String?> notesRegister;
  final Map<String, dynamic>? position; // e.g. {"x": 2, "y": 5}
  final bool isIsolatedClone; // If true, runtime modifications don't mutate parent template
  final Map<String, dynamic>? cloneRuntimeData;
  final HybridLogicalClock incarnationTimestamp;

  String get displayName => displayNameRegister.value;
  String? get notes => notesRegister.value;

  RoomEntityLink({
    this.refType = const EntityCategory('generic', 'Generic'),
    required this.entityId,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    String? notes,
    CrdtLwwRegister<String?>? notesRegister,
    HybridLogicalClock? notesTimestamp,
    Map<String, dynamic>? position,
    this.isIsolatedClone = false,
    Map<String, dynamic>? cloneRuntimeData,
    HybridLogicalClock? incarnationTimestamp,
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
        notesRegister = notesRegister ??
            (notesTimestamp != null
                ? CrdtLwwRegister<String?>(
                    value: notes,
                    timestamp: notesTimestamp,
                  )
                : CrdtLwwRegister<String?>(
                    value: notes,
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        position = position != null ? deepFreezeMap(position) : null,
        cloneRuntimeData =
            cloneRuntimeData != null ? deepFreezeMap(cloneRuntimeData) : null,
        incarnationTimestamp = incarnationTimestamp ??
            displayNameRegister?.timestamp ??
            displayNameTimestamp ??
            notesRegister?.timestamp ??
            notesTimestamp ??
            const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            );

  const RoomEntityLink.empty()
      : refType = const EntityCategory('generic', 'Generic'),
        entityId = '',
        displayNameRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        notesRegister = const CrdtLwwRegister<String?>(
          value: null,
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        position = null,
        isIsolatedClone = false,
        cloneRuntimeData = null,
        incarnationTimestamp = const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        );

  RoomEntityLink copyWith({
    dynamic refType,
    String? entityId,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    Object? notes = _sentinel,
    CrdtLwwRegister<String?>? notesRegister,
    HybridLogicalClock? notesTimestamp,
    bool clearNotes = false,
    Map<String, dynamic>? position,
    bool? isIsolatedClone,
    Map<String, dynamic>? cloneRuntimeData,
    HybridLogicalClock? incarnationTimestamp,
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
    } else {
      resolvedDisplayNameRegister = this.displayNameRegister;
    }

    final CrdtLwwRegister<String?> resolvedNotesRegister;
    if (notesRegister != null) {
      resolvedNotesRegister = notesRegister;
    } else if (clearNotes || (notes != _sentinel && notes == null)) {
      if (notesTimestamp == null) {
        throw ArgumentError(
          'Clearing notes via copyWith requires an authoritative notesTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNotesRegister = CrdtLwwRegister<String?>(
        value: null,
        timestamp: notesTimestamp,
      );
    } else if (notes != _sentinel && notes is String) {
      if (notesTimestamp == null) {
        throw ArgumentError(
          'Updating notes via copyWith requires an authoritative notesTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNotesRegister = CrdtLwwRegister<String?>(
        value: notes,
        timestamp: notesTimestamp,
      );
    } else {
      resolvedNotesRegister = this.notesRegister;
    }

    return RoomEntityLink(
      refType: refType ?? this.refType,
      entityId: entityId ?? this.entityId,
      displayNameRegister: resolvedDisplayNameRegister,
      notesRegister: resolvedNotesRegister,
      position: position ?? this.position,
      isIsolatedClone: isIsolatedClone ?? this.isIsolatedClone,
      cloneRuntimeData: cloneRuntimeData ?? this.cloneRuntimeData,
      incarnationTimestamp: incarnationTimestamp ?? this.incarnationTimestamp,
    );
  }

  /// Canonicalizes supported [refType] representations (EntityCategory, Enum, String)
  /// into a consistent string key for serialization, equality, and hashing.
  static String canonicalRefTypeKey(dynamic refType) {
    if (refType is EntityCategory) {
      return refType.key;
    } else if (refType is Enum) {
      return refType.name;
    } else if (refType is String) {
      return refType;
    } else if (refType == null) {
      return 'generic';
    } else {
      throw ArgumentError.value(
        refType,
        'refType',
        'Unsupported RoomEntityLink refType. Expected EntityCategory, Enum, or String.',
      );
    }
  }

  /// Returns the canonical string identifier of [refType].
  String get canonicalRefType => canonicalRefTypeKey(refType);

  Map<String, dynamic> toMap() => {
        'refType': canonicalRefTypeKey(refType),
        'entityId': entityId,
        'displayName': displayName,
        'displayNameRegister': {
          'value': displayNameRegister.value,
          'timestamp': displayNameRegister.timestamp.toMap(),
        },
        if (notes != null) 'notes': notes,
        'notesRegister': {
          'value': notesRegister.value,
          'timestamp': notesRegister.timestamp.toMap(),
        },
        'incarnationTimestamp': incarnationTimestamp.toMap(),
        if (position != null) 'position': position,
        if (isIsolatedClone) 'isIsolatedClone': true,
        if (cloneRuntimeData != null) 'cloneRuntimeData': cloneRuntimeData,
      };

  factory RoomEntityLink.fromMap(Map<String, dynamic> map,
      {dynamic Function(String)? refTypeResolver}) {
    final typeStr = map['refType']?.toString() ?? 'generic';
    final resolvedRefType = refTypeResolver != null
        ? refTypeResolver(typeStr)
        : EntityCategory(typeStr, typeStr);

    final CrdtLwwRegister<String> displayNameReg;
    if (map.containsKey('displayNameRegister')) {
      final rawReg = map['displayNameRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" value cannot be null.',
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

    final CrdtLwwRegister<String?> notesReg;
    if (map.containsKey('notesRegister')) {
      final rawReg = map['notesRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "notesRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "notesRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "notesRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      notesReg = CrdtLwwRegister<String?>(
        value: rawVal?.toString(),
        timestamp: timestamp,
      );
    } else {
      notesReg = CrdtLwwRegister<String?>(
        value: map['notes']?.toString(),
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    final HybridLogicalClock incarnationTs;
    if (map.containsKey('incarnationTimestamp')) {
      final rawInc = map['incarnationTimestamp'];
      if (rawInc is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "incarnationTimestamp" must be a Map, got ${rawInc.runtimeType}',
        );
      }
      incarnationTs = HybridLogicalClock.fromMap(rawInc);
    } else {
      final maxTs = displayNameReg.timestamp.isAfter(notesReg.timestamp)
          ? displayNameReg.timestamp
          : notesReg.timestamp;
      incarnationTs = maxTs.physicalTime > 0
          ? maxTs
          : const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            );
    }

    return RoomEntityLink(
      refType: resolvedRefType,
      entityId: map['entityId']?.toString() ?? '',
      displayNameRegister: displayNameReg,
      notesRegister: notesReg,
      position: map['position'] != null
          ? Map<String, dynamic>.from(map['position'] as Map)
          : null,
      isIsolatedClone: map['isIsolatedClone'] == true,
      cloneRuntimeData: map['cloneRuntimeData'] != null
          ? Map<String, dynamic>.from(map['cloneRuntimeData'] as Map)
          : null,
      incarnationTimestamp: incarnationTs,
    );
  }

  /// Pure canonical aggregate join of two [RoomEntityLink] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  static RoomEntityLink join(RoomEntityLink a, RoomEntityLink b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedEntityId = joinImmutableId(
      a.entityId,
      b.entityId,
      fieldName: 'RoomEntityLink.entityId',
    );

    if (canonicalRefTypeKey(a.refType) != canonicalRefTypeKey(b.refType)) {
      throw StateError(
        'RoomEntityLink refType mismatch for "${a.entityId}": '
        '"${a.canonicalRefType}" vs "${b.canonicalRefType}".',
      );
    }

    if (a.isIsolatedClone != b.isIsolatedClone) {
      throw StateError(
        'RoomEntityLink isIsolatedClone mismatch for "${a.entityId}": '
        '${a.isIsolatedClone} vs ${b.isIsolatedClone}.',
      );
    }

    // Incarnation boundary: pre-removal nested fields cannot leak across incarnations.
    if (a.incarnationTimestamp != b.incarnationTimestamp) {
      if (a.incarnationTimestamp.isAfter(b.incarnationTimestamp)) {
        return a;
      } else {
        return b;
      }
    }

    final mergedDisplayName = a.displayNameRegister.merge(b.displayNameRegister);
    final mergedNotes = a.notesRegister.merge(b.notesRegister);

    final mergedPosition = joinNullableMap(
      a.position,
      b.position,
      context: 'RoomEntityLink.position',
    );

    final mergedCloneRuntimeData = joinNullableMap(
      a.cloneRuntimeData,
      b.cloneRuntimeData,
      context: 'RoomEntityLink.cloneRuntimeData',
    );

    return RoomEntityLink(
      refType: a.refType,
      entityId: mergedEntityId,
      displayNameRegister: mergedDisplayName,
      notesRegister: mergedNotes,
      position: mergedPosition,
      isIsolatedClone: a.isIsolatedClone,
      cloneRuntimeData: mergedCloneRuntimeData,
      incarnationTimestamp: a.incarnationTimestamp,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  RoomEntityLink merge(RoomEntityLink other) => RoomEntityLink.join(this, other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomEntityLink &&
          runtimeType == other.runtimeType &&
          canonicalRefTypeKey(refType) == canonicalRefTypeKey(other.refType) &&
          entityId == other.entityId &&
          displayNameRegister == other.displayNameRegister &&
          notesRegister == other.notesRegister &&
          incarnationTimestamp == other.incarnationTimestamp &&
          _deepEquality.equals(position, other.position) &&
          isIsolatedClone == other.isIsolatedClone &&
          _deepEquality.equals(cloneRuntimeData, other.cloneRuntimeData);

  @override
  int get hashCode => Object.hash(
        canonicalRefTypeKey(refType),
        entityId,
        displayNameRegister,
        notesRegister,
        incarnationTimestamp,
        _deepEquality.hash(position),
        isIsolatedClone,
        _deepEquality.hash(cloneRuntimeData),
      );
}

/// Dynamic Combat and Turn-Tracker Participant in an active room encounter.
/// Decoupled from mandatory HP, defense, initiative, and death assumptions.
@immutable
class EncounterParticipant {
  final String participantId;
  final RoomEntityLink entityLink;
  final int? initiativeScore;
  final int? initiativeTieBreaker;
  final int? currentHp;
  final int? maxHp;
  final int? tempHp;
  final int? defense;
  final List<String> activeConditions;
  final bool? isDefeated;
  final bool? isDead;
  final bool isActiveTurn;
  final Map<String, dynamic> customProperties;

  int? get defenseRating => defense;

  EncounterParticipant({
    required this.participantId,
    required this.entityLink,
    this.initiativeScore,
    this.initiativeTieBreaker,
    this.currentHp,
    this.maxHp,
    this.tempHp,
    this.defense,
    List<String> activeConditions = const [],
    this.isDefeated,
    this.isDead,
    this.isActiveTurn = false,
    Map<String, dynamic> customProperties = const {},
  })  : activeConditions = List.unmodifiable(activeConditions),
        customProperties = deepFreezeMap(customProperties);

  const EncounterParticipant.empty()
      : participantId = '',
        entityLink = const RoomEntityLink.empty(),
        initiativeScore = null,
        initiativeTieBreaker = null,
        currentHp = null,
        maxHp = null,
        tempHp = null,
        defense = null,
        activeConditions = const [],
        isDefeated = null,
        isDead = null,
        isActiveTurn = false,
        customProperties = const {};

  EncounterParticipant copyWith({
    String? participantId,
    RoomEntityLink? entityLink,
    int? initiativeScore,
    int? initiativeTieBreaker,
    dynamic hitPoints,
    int? currentHp,
    int? maxHp,
    int? tempHp,
    int? defense,
    List<String>? activeConditions,
    bool? isDefeated,
    bool? isDead,
    bool? isActiveTurn,
    Map<String, dynamic>? customProperties,
  }) {
    int? hpCurrent;
    int? hpMax;
    int? hpTemp;
    bool? hpDead;
    if (hitPoints != null) {
      try {
        hpCurrent = (hitPoints as dynamic).currentHp as int?;
        hpMax = (hitPoints as dynamic).maxHp as int?;
        hpTemp = (hitPoints as dynamic).tempHp as int?;
        hpDead = (hitPoints as dynamic).isDead as bool?;
      } catch (_) {}
    }

    return EncounterParticipant(
      participantId: participantId ?? this.participantId,
      entityLink: entityLink ?? this.entityLink,
      initiativeScore: initiativeScore ?? this.initiativeScore,
      initiativeTieBreaker: initiativeTieBreaker ?? this.initiativeTieBreaker,
      currentHp: hpCurrent ?? currentHp ?? this.currentHp,
      maxHp: hpMax ?? maxHp ?? this.maxHp,
      tempHp: hpTemp ?? tempHp ?? this.tempHp,
      defense: defense ?? this.defense,
      activeConditions: activeConditions ?? this.activeConditions,
      isDefeated: isDefeated ?? this.isDefeated,
      isDead: hpDead ?? isDead ?? this.isDead,
      isActiveTurn: isActiveTurn ?? this.isActiveTurn,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'participantId': participantId,
        'entityLink': entityLink.toMap(),
        if (initiativeScore != null) 'initiativeScore': initiativeScore,
        if (initiativeTieBreaker != null)
          'initiativeTieBreaker': initiativeTieBreaker,
        if (currentHp != null) 'currentHp': currentHp,
        if (maxHp != null) 'maxHp': maxHp,
        if (tempHp != null) 'tempHp': tempHp,
        if (defense != null) 'defense': defense,
        'activeConditions': activeConditions,
        if (isDefeated != null) 'isDefeated': isDefeated,
        if (isDead != null) 'isDead': isDead,
        'isActiveTurn': isActiveTurn,
        if (customProperties.isNotEmpty)
          'customProperties': customProperties,
      };

  factory EncounterParticipant.fromMap(Map<String, dynamic> map) {
    int? cur = (map['currentHp'] as num?)?.toInt();
    int? max = (map['maxHp'] as num?)?.toInt();
    int? temp = (map['tempHp'] as num?)?.toInt();
    bool? isDead = map['isDead'] as bool?;
    if (map['hitPoints'] is Map) {
      final hpMap = map['hitPoints'] as Map;
      cur ??= (hpMap['currentHp'] as num?)?.toInt();
      max ??= (hpMap['maxHp'] as num?)?.toInt();
      temp ??= (hpMap['tempHp'] as num?)?.toInt();
      isDead ??= hpMap['isDead'] as bool?;
    }

    return EncounterParticipant(
      participantId: map['participantId']?.toString() ?? '',
      entityLink: RoomEntityLink.fromMap(
          Map<String, dynamic>.from(map['entityLink'] as Map? ?? {})),
      initiativeScore: (map['initiativeScore'] as num?)?.toInt(),
      initiativeTieBreaker: (map['initiativeTieBreaker'] as num?)?.toInt(),
      currentHp: cur,
      maxHp: max,
      tempHp: temp,
      defense: (map['defense'] as num?)?.toInt() ??
          (map['defenseRating'] as num?)?.toInt() ??
          (map['ac'] as num?)?.toInt(),
      activeConditions:
          (map['activeConditions'] as List? ?? []).whereType<String>().toList(),
      isDefeated: map['isDefeated'] is bool ? map['isDefeated'] as bool : null,
      isDead: isDead ?? (map['isDead'] is bool ? map['isDead'] as bool : null),
      isActiveTurn: map['isActiveTurn'] == true,
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncounterParticipant &&
          runtimeType == other.runtimeType &&
          participantId == other.participantId &&
          entityLink == other.entityLink &&
          initiativeScore == other.initiativeScore &&
          initiativeTieBreaker == other.initiativeTieBreaker &&
          currentHp == other.currentHp &&
          maxHp == other.maxHp &&
          tempHp == other.tempHp &&
          defense == other.defense &&
          _deepEquality.equals(activeConditions, other.activeConditions) &&
          isDefeated == other.isDefeated &&
          isDead == other.isDead &&
          isActiveTurn == other.isActiveTurn &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        participantId,
        entityLink,
        initiativeScore,
        initiativeTieBreaker,
        currentHp,
        maxHp,
        tempHp,
        defense,
        _deepEquality.hash(activeConditions),
        isDefeated,
        isDead,
        isActiveTurn,
        _deepEquality.hash(customProperties),
      );
}

/// Root Node Representation of a dynamic Dungeon Room or Session Graph State.
@immutable
class RoomNodeState {
  static const Object _sentinel = Object();

  final String roomId;
  final String roomCode;
  final CrdtLwwRegister<String> titleRegister;
  final CrdtLwwRegister<String> descriptionRegister;
  final EntityLinkCrdtSet entityLinksCrdt;
  final List<EntityInstance> entityInstances;
  final List<LootContainer> containers;
  final CrdtOrSet<EncounterParticipant> activeEncounter;
  final CrdtOrSet<dynamic> activeMinions;
  final Map<String, dynamic> customProperties;



  String get title => titleRegister.value;
  String get description => descriptionRegister.value;

  List<RoomEntityLink> get entityLinks => entityLinksCrdt.activeValues;
  List<EncounterParticipant> get activeEncounterList =>
      activeEncounter.activeValues;
  List<dynamic> get activeMinionsList => activeMinions.activeValues;

  RoomNodeState({
    required this.roomId,
    required this.roomCode,
    String? title,
    CrdtLwwRegister<String>? titleRegister,
    HybridLogicalClock? titleTimestamp,
    String? description,
    CrdtLwwRegister<String>? descriptionRegister,
    HybridLogicalClock? descriptionTimestamp,
    List<RoomEntityLink>? entityLinks,
    Object? entityLinksCrdt = _sentinel,
    List<EntityInstance> entityInstances = const [],
    List<LootContainer> containers = const [],
    this.activeEncounter = const CrdtOrSet<EncounterParticipant>.empty(),
    this.activeMinions = const CrdtOrSet<dynamic>.empty(),
    Map<String, dynamic> customProperties = const {},
  })  : titleRegister = titleRegister ??
            (titleTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: title ?? '',
                    timestamp: titleTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: title ?? '',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        descriptionRegister = descriptionRegister ??
            (descriptionTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: description ?? '',
                    timestamp: descriptionTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: description ?? '',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        entityLinksCrdt = identical(entityLinksCrdt, _sentinel)
            ? (entityLinks != null && entityLinks.isNotEmpty
                ? _buildInitialLinksCrdt(entityLinks)
                : const EntityLinkCrdtSet.empty())
            : (entityLinksCrdt == null
                ? throw ArgumentError('RoomNodeState: entityLinksCrdt cannot be null.')
                : (entityLinksCrdt is EntityLinkCrdtSet
                    ? entityLinksCrdt
                    : throw ArgumentError(
                        'RoomNodeState: invalid entityLinksCrdt type "'
                        '${entityLinksCrdt.runtimeType}". Expected EntityLinkCrdtSet. '
                        'Use RoomNodeState.fromLegacyCrdtOrSet for legacy CrdtOrSet migration.',
                      ))),
        entityInstances = List.unmodifiable(entityInstances),
        containers = List.unmodifiable(containers),
        customProperties = deepFreezeMap(customProperties);

  const RoomNodeState.empty()
      : roomId = '',
        roomCode = '',
        titleRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        descriptionRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        entityLinksCrdt = const EntityLinkCrdtSet.empty(),
        entityInstances = const [],
        containers = const [],
        activeEncounter = const CrdtOrSet<EncounterParticipant>.empty(),
        activeMinions = const CrdtOrSet<dynamic>.empty(),
        customProperties = const {};

  /// Explicit compatibility/migration boundary converting legacy [CrdtOrSet<RoomEntityLink>]
  /// to [EntityLinkCrdtSet] for [RoomNodeState].
  factory RoomNodeState.fromLegacyCrdtOrSet({
    required String roomId,
    required String roomCode,
    String? title,
    CrdtLwwRegister<String>? titleRegister,
    HybridLogicalClock? titleTimestamp,
    String? description,
    CrdtLwwRegister<String>? descriptionRegister,
    HybridLogicalClock? descriptionTimestamp,
    required CrdtOrSet<RoomEntityLink> entityLinksCrdt,
    List<EntityInstance> entityInstances = const [],
    List<LootContainer> containers = const [],
    CrdtOrSet<EncounterParticipant> activeEncounter =
        const CrdtOrSet<EncounterParticipant>.empty(),
    CrdtOrSet<dynamic> activeMinions = const CrdtOrSet<dynamic>.empty(),
    Map<String, dynamic> customProperties = const {},
  }) {
    return RoomNodeState(
      roomId: roomId,
      roomCode: roomCode,
      title: title,
      titleRegister: titleRegister,
      titleTimestamp: titleTimestamp,
      description: description,
      descriptionRegister: descriptionRegister,
      descriptionTimestamp: descriptionTimestamp,
      entityLinksCrdt: EntityLinkCrdtSet.fromCrdtOrSet(entityLinksCrdt),
      entityInstances: entityInstances,
      containers: containers,
      activeEncounter: activeEncounter,
      activeMinions: activeMinions,
      customProperties: customProperties,
    );
  }

  static EntityLinkCrdtSet _buildInitialLinksCrdt(
      List<RoomEntityLink> links) {
    final Map<String, RoomEntityLink> deduplicated = {};
    for (final l in links) {
      final existing = deduplicated[l.entityId];
      if (existing == null) {
        deduplicated[l.entityId] = l;
      } else {
        if (l.incarnationTimestamp.isAfter(existing.incarnationTimestamp)) {
          deduplicated[l.entityId] = l;
        } else if (existing.incarnationTimestamp.isAfter(l.incarnationTimestamp)) {
          // Existing link has strictly higher generation; keep it.
        } else {
          if (existing == l) {
            // Identical payload; duplicate is a no-op.
          } else {
            throw FormatException(
              'RoomNodeState: duplicate entity link ID "${l.entityId}" '
              'with divergent payload in same generation.',
            );
          }
        }
      }
    }
    EntityLinkCrdtSet current = const EntityLinkCrdtSet.empty();
    for (final l in deduplicated.values) {
      final ts = l.incarnationTimestamp.physicalTime > 0
          ? l.incarnationTimestamp
          : const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            );
      current = current.createOrReadd(l.entityId, l, ts);
    }
    return current;
  }

  factory RoomNodeState.fromLists({
    required String roomId,
    required String roomCode,
    String? title,
    CrdtLwwRegister<String>? titleRegister,
    String? description,
    CrdtLwwRegister<String>? descriptionRegister,
    List<RoomEntityLink> entityLinks = const [],
    Object? entityLinksCrdt = _sentinel,
    List<EntityInstance> entityInstances = const [],
    List<LootContainer> containers = const [],
    Iterable<EncounterParticipant>? activeEncounter,
    Iterable<dynamic>? activeMinions,
    Map<String, dynamic> customProperties = const {},
  }) {
    final effectiveEncounter = activeEncounter != null
        ? const CrdtOrSet<EncounterParticipant>.empty()
            .addBatch(activeEncounter.map(
            (e) => (
              id: e.participantId,
              item: e,
              timestamp: const HybridLogicalClock(
                physicalTime: 0,
                logicalCounter: 0,
                nodeId: 'genesis',
              ),
            ),
          ))
        : const CrdtOrSet<EncounterParticipant>.empty();

    final effectiveMinions = activeMinions != null
        ? const CrdtOrSet<dynamic>.empty().addBatch(activeMinions.map(
            (m) => (
              id: _resolveMinionId(m),
              item: deepFreezeValue(m),
              timestamp: const HybridLogicalClock(
                physicalTime: 0,
                logicalCounter: 0,
                nodeId: 'genesis',
              ),
            ),
          ))
        : const CrdtOrSet<dynamic>.empty();

    return RoomNodeState(
      roomId: roomId,
      roomCode: roomCode,
      title: title,
      titleRegister: titleRegister,
      description: description,
      descriptionRegister: descriptionRegister,
      entityLinks: entityLinks,
      entityLinksCrdt: entityLinksCrdt,
      entityInstances: entityInstances,
      containers: containers,
      activeEncounter: effectiveEncounter,
      activeMinions: effectiveMinions,
      customProperties: customProperties,
    );
  }

  RoomNodeState copyWith({
    String? roomId,
    String? roomCode,
    String? title,
    CrdtLwwRegister<String>? titleRegister,
    HybridLogicalClock? titleTimestamp,
    String? description,
    CrdtLwwRegister<String>? descriptionRegister,
    HybridLogicalClock? descriptionTimestamp,
    List<RoomEntityLink>? entityLinks,
    Object? entityLinksCrdt = _sentinel,
    List<EntityInstance>? entityInstances,
    List<LootContainer>? containers,
    CrdtOrSet<EncounterParticipant>? activeEncounter,
    CrdtOrSet<dynamic>? activeMinions,
    Map<String, dynamic>? customProperties,
  }) {
    final CrdtLwwRegister<String> resolvedTitleRegister;
    if (titleRegister != null) {
      resolvedTitleRegister = titleRegister;
    } else if (title != null) {
      if (titleTimestamp == null) {
        throw ArgumentError(
          'Updating title via copyWith requires an authoritative titleTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedTitleRegister = CrdtLwwRegister<String>(
        value: title,
        timestamp: titleTimestamp,
      );
    } else {
      resolvedTitleRegister = this.titleRegister;
    }

    final CrdtLwwRegister<String> resolvedDescRegister;
    if (descriptionRegister != null) {
      resolvedDescRegister = descriptionRegister;
    } else if (description != null) {
      if (descriptionTimestamp == null) {
        throw ArgumentError(
          'Updating description via copyWith requires an authoritative descriptionTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedDescRegister = CrdtLwwRegister<String>(
        value: description,
        timestamp: descriptionTimestamp,
      );
    } else {
      resolvedDescRegister = this.descriptionRegister;
    }

    final EntityLinkCrdtSet effectiveLinks;
    if (identical(entityLinksCrdt, _sentinel)) {
      effectiveLinks = entityLinks != null
          ? _buildInitialLinksCrdt(entityLinks)
          : this.entityLinksCrdt;
    } else if (entityLinksCrdt == null) {
      throw ArgumentError('RoomNodeState.copyWith: entityLinksCrdt cannot be null.');
    } else if (entityLinksCrdt is EntityLinkCrdtSet) {
      effectiveLinks = entityLinksCrdt;
    } else {
      throw ArgumentError(
        'RoomNodeState.copyWith: invalid entityLinksCrdt type "'
        '${entityLinksCrdt.runtimeType}". Expected EntityLinkCrdtSet.',
      );
    }

    return RoomNodeState(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      titleRegister: resolvedTitleRegister,
      descriptionRegister: resolvedDescRegister,
      entityLinksCrdt: effectiveLinks,
      entityInstances: entityInstances ?? this.entityInstances,
      containers: containers ?? this.containers,
      activeEncounter: activeEncounter ?? this.activeEncounter,
      activeMinions: activeMinions ?? this.activeMinions,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'roomId': roomId,
        'roomCode': roomCode,
        'title': title,
        'titleRegister': {
          'value': titleRegister.value,
          'timestamp': titleRegister.timestamp.toMap(),
        },
        'description': description,
        'descriptionRegister': {
          'value': descriptionRegister.value,
          'timestamp': descriptionRegister.timestamp.toMap(),
        },
        'entityLinks': entityLinks.map((e) => e.toMap()).toList(),
        'entityLinks_format': 2,
        'entityLinks_crdt': entityLinksCrdt.toMap((e) => e.toMap()),
        if (entityInstances.isNotEmpty)
          'entityInstances': entityInstances.map((e) => e.toMap()).toList(),
        'containers': containers.map((c) => c.toMap()).toList(),
        'activeEncounter':
            activeEncounter.activeValues.map((e) => e.toMap()).toList(),
        'activeEncounter_crdt': activeEncounter.toMap((e) => e.toMap()),
        'activeMinions': activeMinions.activeValues
            .map((m) => m is Map ? m : (m as dynamic).toMap())
            .toList(),
        'activeMinions_crdt': activeMinions
            .toMap((m) => m is Map ? m : (m as dynamic).toMap()),
        if (customProperties.isNotEmpty)
          'customProperties': customProperties,
      };

  factory RoomNodeState.fromMap(Map<String, dynamic> map,
      {required dynamic Function(Map<String, dynamic>) minionParser}) {
    final parser = minionParser;

    final CrdtLwwRegister<String> titleReg;
    if (map.containsKey('titleRegister')) {
      final rawTitleReg = map['titleRegister'];
      if (rawTitleReg is! Map) {
        throw FormatException(
          'RoomNodeState.fromMap: "titleRegister" must be a Map, got ${rawTitleReg.runtimeType}',
        );
      }
      final rawTs = rawTitleReg['timestamp'] ?? rawTitleReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomNodeState.fromMap: "titleRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawTitleReg.containsKey('value') && !rawTitleReg.containsKey('v')) {
        throw const FormatException(
          'RoomNodeState.fromMap: "titleRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawTitleReg.containsKey('value') ? rawTitleReg['value'] : rawTitleReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'RoomNodeState.fromMap: "titleRegister" value cannot be null.',
        );
      }
      titleReg = CrdtLwwRegister<String>(
        value: rawVal.toString(),
        timestamp: timestamp,
      );
    } else {
      titleReg = CrdtLwwRegister<String>(
        value: map['title']?.toString() ?? '',
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    final CrdtLwwRegister<String> descReg;
    if (map.containsKey('descriptionRegister')) {
      final rawDescReg = map['descriptionRegister'];
      if (rawDescReg is! Map) {
        throw FormatException(
          'RoomNodeState.fromMap: "descriptionRegister" must be a Map, got ${rawDescReg.runtimeType}',
        );
      }
      final rawTs = rawDescReg['timestamp'] ?? rawDescReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomNodeState.fromMap: "descriptionRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawDescReg.containsKey('value') && !rawDescReg.containsKey('v')) {
        throw const FormatException(
          'RoomNodeState.fromMap: "descriptionRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawDescReg.containsKey('value') ? rawDescReg['value'] : rawDescReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'RoomNodeState.fromMap: "descriptionRegister" value cannot be null.',
        );
      }
      descReg = CrdtLwwRegister<String>(
        value: rawVal.toString(),
        timestamp: timestamp,
      );
    } else {
      descReg = CrdtLwwRegister<String>(
        value: map['description']?.toString() ?? '',
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    final int? entityLinksFormat = (map['entityLinks_format'] as num?)?.toInt();
    EntityLinkCrdtSet linksSet =
        const EntityLinkCrdtSet.empty();
    if (map.containsKey('entityLinks_crdt')) {
      final rawCrdt = map['entityLinks_crdt'];
      if (rawCrdt is! Map) {
        throw const FormatException('RoomNodeState.fromMap: "entityLinks_crdt" must be a Map.');
      }
      linksSet = EntityLinkCrdtSet.fromMap(
        Map<dynamic, dynamic>.from(rawCrdt),
        (raw) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: raw entity link must be a Map.');
          }
          return RoomEntityLink.fromMap(Map<String, dynamic>.from(raw));
        },
        entityLinksFormat,
      );
    } else if (map.containsKey('entityLinks')) {
      final rawLinks = map['entityLinks'];
      if (rawLinks is Map) {
        final legacyOrSet = CrdtOrSet<RoomEntityLink>.fromMap(
          Map<dynamic, dynamic>.from(rawLinks),
          (raw) {
            if (raw is! Map) {
              throw const FormatException('RoomNodeState.fromMap: raw entity link must be a Map.');
            }
            return RoomEntityLink.fromMap(Map<String, dynamic>.from(raw));
          },
        );
        linksSet = EntityLinkCrdtSet.fromCrdtOrSet(legacyOrSet);
      } else if (rawLinks is List) {
        final Map<String, RoomEntityLink> deduplicated = {};
        for (final raw in rawLinks) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: legacy entity link must be a Map.');
          }
          final l = RoomEntityLink.fromMap(Map<String, dynamic>.from(raw));
          final existing = deduplicated[l.entityId];
          if (existing == null) {
            deduplicated[l.entityId] = l;
          } else {
            if (l.incarnationTimestamp.isAfter(existing.incarnationTimestamp)) {
              deduplicated[l.entityId] = l;
            } else if (existing.incarnationTimestamp.isAfter(l.incarnationTimestamp)) {
              // Existing link has strictly higher generation; keep it.
            } else {
              if (existing == l) {
                // Same generation / same payload: duplicate is a no-op.
              } else {
                throw FormatException(
                  'RoomNodeState.fromMap: duplicate entity link ID "${l.entityId}" '
                  'with divergent payload in same generation.',
                );
              }
            }
          }
        }
        for (final l in deduplicated.values) {
          final ts = l.incarnationTimestamp.physicalTime > 0
              ? l.incarnationTimestamp
              : const HybridLogicalClock(
                  physicalTime: 0,
                  logicalCounter: 0,
                  nodeId: 'genesis',
                );
          linksSet = linksSet.add(
            l.entityId,
            l,
            ts,
          );
        }
      } else {
        throw const FormatException('RoomNodeState.fromMap: "entityLinks" must be a Map or List.');
      }
    }

    CrdtOrSet<dynamic> minionsSet = const CrdtOrSet<dynamic>.empty();
    if (map.containsKey('activeMinions_crdt')) {
      final rawCrdt = map['activeMinions_crdt'];
      if (rawCrdt is! Map) {
        throw const FormatException('RoomNodeState.fromMap: "activeMinions_crdt" must be a Map.');
      }
      minionsSet = CrdtOrSet<dynamic>.fromMap(
        Map<dynamic, dynamic>.from(rawCrdt),
        (raw) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: raw minion must be a Map.');
          }
          final parsed = parser(Map<String, dynamic>.from(raw));
          return deepFreezeValue(parsed);
        },
      );
    } else if (map.containsKey('activeMinions')) {
      final rawMinions = map['activeMinions'];
      if (rawMinions is Map) {
        minionsSet = CrdtOrSet<dynamic>.fromMap(
          Map<dynamic, dynamic>.from(rawMinions),
          (raw) {
            if (raw is! Map) {
              throw const FormatException('RoomNodeState.fromMap: raw minion must be a Map.');
            }
            final parsed = parser(Map<String, dynamic>.from(raw));
            return deepFreezeValue(parsed);
          },
        );
      } else if (rawMinions is List) {
        final entries =
            <({String id, dynamic item, HybridLogicalClock timestamp})>[];
        for (final raw in rawMinions) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: legacy minion must be a Map.');
          }
          final parsed = parser(Map<String, dynamic>.from(raw));
          final m = deepFreezeValue(parsed);
          final id = (raw['id'] ?? _resolveMinionId(m)).toString();
          entries.add((
            id: id,
            item: m,
            timestamp: const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            ),
          ));
        }
        minionsSet = minionsSet.addBatch(entries);
      } else {
        throw const FormatException('RoomNodeState.fromMap: "activeMinions" must be a Map or List.');
      }
    }

    CrdtOrSet<EncounterParticipant> encounterSet =
        const CrdtOrSet<EncounterParticipant>.empty();
    if (map.containsKey('activeEncounter_crdt')) {
      final rawCrdt = map['activeEncounter_crdt'];
      if (rawCrdt is! Map) {
        throw const FormatException('RoomNodeState.fromMap: "activeEncounter_crdt" must be a Map.');
      }
      encounterSet = CrdtOrSet<EncounterParticipant>.fromMap(
        Map<dynamic, dynamic>.from(rawCrdt),
        (raw) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: raw encounter participant must be a Map.');
          }
          return EncounterParticipant.fromMap(
              Map<String, dynamic>.from(raw));
        },
      );
    } else if (map.containsKey('activeEncounter')) {
      final rawEnc = map['activeEncounter'];
      if (rawEnc is Map) {
        encounterSet = CrdtOrSet<EncounterParticipant>.fromMap(
          Map<dynamic, dynamic>.from(rawEnc),
          (raw) {
            if (raw is! Map) {
              throw const FormatException('RoomNodeState.fromMap: raw encounter participant must be a Map.');
            }
            return EncounterParticipant.fromMap(
                Map<String, dynamic>.from(raw));
          },
        );
      } else if (rawEnc is List) {
        final entries =
            <({String id, EncounterParticipant item, HybridLogicalClock timestamp})>[];
        for (final raw in rawEnc) {
          if (raw is! Map) {
            throw const FormatException('RoomNodeState.fromMap: legacy encounter participant must be a Map.');
          }
          final p =
              EncounterParticipant.fromMap(Map<String, dynamic>.from(raw));
          entries.add((
            id: p.participantId,
            item: p,
            timestamp: const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            ),
          ));
        }
        encounterSet = encounterSet.addBatch(entries);
      } else {
        throw const FormatException('RoomNodeState.fromMap: "activeEncounter" must be a Map or List.');
      }
    }

    final entityInstances = <EntityInstance>[];
    if (map['entityInstances'] is List) {
      for (final raw in (map['entityInstances'] as List)) {
        if (raw is Map) {
          entityInstances.add(
              EntityInstance.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }

    return RoomNodeState(
      roomId: map['roomId']?.toString() ?? '',
      roomCode: map['roomCode']?.toString() ?? '',
      titleRegister: titleReg,
      descriptionRegister: descReg,
      entityLinksCrdt: linksSet,
      entityInstances: entityInstances,
      containers: (map['containers'] as List? ?? [])
          .whereType<Map>()
          .map((c) => LootContainer.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      activeEncounter: encounterSet,
      activeMinions: minionsSet,
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  /// Pure canonical aggregate join of two [RoomNodeState] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  /// Divergent unversioned or incompatible immutable state fails loudly and symmetrically.
  static RoomNodeState join(RoomNodeState a, RoomNodeState b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedRoomId = joinImmutableId(
      a.roomId,
      b.roomId,
      fieldName: 'RoomNodeState.roomId',
    );
    final mergedRoomCode = joinImmutableId(
      a.roomCode,
      b.roomCode,
      fieldName: 'RoomNodeState.roomCode',
    );
    final mergedTitle = a.titleRegister.merge(b.titleRegister);
    final mergedDescription = a.descriptionRegister.merge(b.descriptionRegister);

    // 1. Nested CRDT sets: OR-Set join for minions/encounters, generation-aware join for entityLinks
    final mergedMinions = a.activeMinions.merge(b.activeMinions);
    final mergedEncounter = a.activeEncounter.merge(b.activeEncounter);
    final mergedLinks = joinEntityLinks(a.entityLinksCrdt, b.entityLinksCrdt);

    // 2. Custom properties: deterministic per-key ownership merge
    final mergedCustomProperties = joinCustomProperties(
      a.customProperties,
      b.customProperties,
      context: 'RoomNodeState.customProperties',
    );

    // 3. Entity Instances: recursively join instances by instanceId
    final mergedInstances = joinEntityInstances(a.entityInstances, b.entityInstances);

    // 4. Containers: recursively join containers by containerId
    final mergedContainers = joinContainers(a.containers, b.containers);

    return RoomNodeState(
      roomId: mergedRoomId,
      roomCode: mergedRoomCode,
      titleRegister: mergedTitle,
      descriptionRegister: mergedDescription,
      entityLinksCrdt: mergedLinks,
      entityInstances: mergedInstances,
      containers: mergedContainers,
      activeEncounter: mergedEncounter,
      activeMinions: mergedMinions,
      customProperties: mergedCustomProperties,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  RoomNodeState merge(RoomNodeState other) => RoomNodeState.join(this, other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomNodeState &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          roomCode == other.roomCode &&
          titleRegister == other.titleRegister &&
          descriptionRegister == other.descriptionRegister &&
          entityLinksCrdt == other.entityLinksCrdt &&
          _deepEquality.equals(entityInstances, other.entityInstances) &&
          _deepEquality.equals(containers, other.containers) &&
          activeEncounter == other.activeEncounter &&
          activeMinions == other.activeMinions &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        roomId,
        roomCode,
        titleRegister,
        descriptionRegister,
        entityLinksCrdt,
        _deepEquality.hash(entityInstances),
        _deepEquality.hash(containers),
        activeEncounter,
        activeMinions,
        _deepEquality.hash(customProperties),
      );
}
