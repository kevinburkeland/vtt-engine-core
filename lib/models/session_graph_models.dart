

import '../utils/deep_immutable.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import 'loot_models.dart';

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
  final String displayName;
  final Map<String, dynamic>? position;
  final bool isVisible;
  final Map<String, dynamic> runtimeData;
  final Map<String, dynamic> customProperties;

  EntityInstance({
    required this.instanceId,
    this.entityDefinitionId,
    this.entityType,
    required this.displayName,
    Map<String, dynamic>? position,
    this.isVisible = true,
    Map<String, dynamic> runtimeData = const {},
    Map<String, dynamic> customProperties = const {},
  })  : position = position != null ? deepFreezeMap(position) : null,
        runtimeData = deepFreezeMap(runtimeData),
        customProperties = deepFreezeMap(customProperties);

  const EntityInstance.empty()
      : instanceId = '',
        entityDefinitionId = null,
        entityType = null,
        displayName = '',
        position = null,
        isVisible = true,
        runtimeData = const {},
        customProperties = const {};

  EntityInstance copyWith({
    String? instanceId,
    String? entityDefinitionId,
    String? entityType,
    String? displayName,
    Map<String, dynamic>? position,
    bool? isVisible,
    Map<String, dynamic>? runtimeData,
    Map<String, dynamic>? customProperties,
  }) {
    return EntityInstance(
      instanceId: instanceId ?? this.instanceId,
      entityDefinitionId: entityDefinitionId ?? this.entityDefinitionId,
      entityType: entityType ?? this.entityType,
      displayName: displayName ?? this.displayName,
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
        if (position != null) 'position': position,
        'isVisible': isVisible,
        if (runtimeData.isNotEmpty) 'runtimeData': runtimeData,
        if (customProperties.isNotEmpty)
          'customProperties': customProperties,
      };

  factory EntityInstance.fromMap(Map<String, dynamic> map) {
    return EntityInstance(
      instanceId: map['instanceId']?.toString() ?? '',
      entityDefinitionId: map['entityDefinitionId']?.toString(),
      entityType: map['entityType']?.toString(),
      displayName: map['displayName']?.toString() ?? '',
      position: map['position'] != null
          ? Map<String, dynamic>.from(map['position'] as Map)
          : null,
      isVisible: map['isVisible'] != false,
      runtimeData: Map<String, dynamic>.from(map['runtimeData'] as Map? ?? {}),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityInstance &&
          runtimeType == other.runtimeType &&
          instanceId == other.instanceId &&
          entityDefinitionId == other.entityDefinitionId &&
          entityType == other.entityType &&
          displayName == other.displayName &&
          _deepEquality.equals(position, other.position) &&
          isVisible == other.isVisible &&
          _deepEquality.equals(runtimeData, other.runtimeData) &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        instanceId,
        entityDefinitionId,
        entityType,
        displayName,
        _deepEquality.hash(position),
        isVisible,
        _deepEquality.hash(runtimeData),
        _deepEquality.hash(customProperties),
      );
}

/// Contextual pointer linking characters, tokens, objects, or zones to a room or graph node
@immutable
class RoomEntityLink {
  final dynamic refType;
  final String entityId;
  final String displayName;
  final String? notes;
  final Map<String, dynamic>? position; // e.g. {"x": 2, "y": 5}
  final bool isIsolatedClone; // If true, runtime modifications don't mutate parent template
  final Map<String, dynamic>? cloneRuntimeData;

  RoomEntityLink({
    this.refType = const EntityCategory('generic', 'Generic'),
    required this.entityId,
    required this.displayName,
    this.notes,
    Map<String, dynamic>? position,
    this.isIsolatedClone = false,
    Map<String, dynamic>? cloneRuntimeData,
  })  : position = position != null ? deepFreezeMap(position) : null,
        cloneRuntimeData =
            cloneRuntimeData != null ? deepFreezeMap(cloneRuntimeData) : null;

  const RoomEntityLink.empty()
      : refType = const EntityCategory('generic', 'Generic'),
        entityId = '',
        displayName = '',
        notes = null,
        position = null,
        isIsolatedClone = false,
        cloneRuntimeData = null;

  RoomEntityLink copyWith({
    dynamic refType,
    String? entityId,
    String? displayName,
    String? notes,
    Map<String, dynamic>? position,
    bool? isIsolatedClone,
    Map<String, dynamic>? cloneRuntimeData,
  }) {
    return RoomEntityLink(
      refType: refType ?? this.refType,
      entityId: entityId ?? this.entityId,
      displayName: displayName ?? this.displayName,
      notes: notes ?? this.notes,
      position: position ?? this.position,
      isIsolatedClone: isIsolatedClone ?? this.isIsolatedClone,
      cloneRuntimeData: cloneRuntimeData ?? this.cloneRuntimeData,
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
        'notes': notes,
        'position': position,
        'isIsolatedClone': isIsolatedClone,
        'cloneRuntimeData': cloneRuntimeData,
      };

  factory RoomEntityLink.fromMap(Map<String, dynamic> map,
      {dynamic Function(String)? refTypeResolver}) {
    final typeStr = map['refType']?.toString() ?? 'generic';
    final resolvedRefType = refTypeResolver != null
        ? refTypeResolver(typeStr)
        : EntityCategory(typeStr, typeStr);

    return RoomEntityLink(
      refType: resolvedRefType,
      entityId: map['entityId']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      notes: map['notes']?.toString(),
      position: map['position'] != null
          ? Map<String, dynamic>.from(map['position'] as Map)
          : null,
      isIsolatedClone: map['isIsolatedClone'] == true,
      cloneRuntimeData: map['cloneRuntimeData'] != null
          ? Map<String, dynamic>.from(map['cloneRuntimeData'] as Map)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomEntityLink &&
          runtimeType == other.runtimeType &&
          canonicalRefTypeKey(refType) == canonicalRefTypeKey(other.refType) &&
          entityId == other.entityId &&
          displayName == other.displayName &&
          notes == other.notes &&
          _deepEquality.equals(position, other.position) &&
          isIsolatedClone == other.isIsolatedClone &&
          _deepEquality.equals(cloneRuntimeData, other.cloneRuntimeData);

  @override
  int get hashCode => Object.hash(
        canonicalRefTypeKey(refType),
        entityId,
        displayName,
        notes,
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
  final String roomId;
  final String roomCode;
  final String title;
  final String description;
  final List<RoomEntityLink> entityLinks;
  final List<EntityInstance> entityInstances;
  final List<LootContainer> containers;
  final CrdtOrSet<EncounterParticipant> activeEncounter;
  final CrdtOrSet<dynamic> activeMinions;
  final Map<String, dynamic> customProperties;

  /// Hook for modules to provide custom deserializer for active minions / summons.
  static dynamic Function(Map<String, dynamic>)? defaultMinionParser;

  List<EncounterParticipant> get activeEncounterList =>
      activeEncounter.activeValues;
  List<dynamic> get activeMinionsList => activeMinions.activeValues;

  RoomNodeState({
    required this.roomId,
    required this.roomCode,
    required this.title,
    this.description = '',
    List<RoomEntityLink> entityLinks = const [],
    List<EntityInstance> entityInstances = const [],
    List<LootContainer> containers = const [],
    this.activeEncounter = const CrdtOrSet<EncounterParticipant>.empty(),
    this.activeMinions = const CrdtOrSet<dynamic>.empty(),
    Map<String, dynamic> customProperties = const {},
  })  : entityLinks = List.unmodifiable(entityLinks),
        entityInstances = List.unmodifiable(entityInstances),
        containers = List.unmodifiable(containers),
        customProperties = deepFreezeMap(customProperties);

  const RoomNodeState.empty()
      : roomId = '',
        roomCode = '',
        title = '',
        description = '',
        entityLinks = const [],
        entityInstances = const [],
        containers = const [],
        activeEncounter = const CrdtOrSet<EncounterParticipant>.empty(),
        activeMinions = const CrdtOrSet<dynamic>.empty(),
        customProperties = const {};

  factory RoomNodeState.fromLists({
    required String roomId,
    required String roomCode,
    required String title,
    String description = '',
    List<RoomEntityLink> entityLinks = const [],
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
      description: description,
      entityLinks: entityLinks,
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
    String? description,
    List<RoomEntityLink>? entityLinks,
    List<EntityInstance>? entityInstances,
    List<LootContainer>? containers,
    CrdtOrSet<EncounterParticipant>? activeEncounter,
    CrdtOrSet<dynamic>? activeMinions,
    Map<String, dynamic>? customProperties,
  }) {
    return RoomNodeState(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      title: title ?? this.title,
      description: description ?? this.description,
      entityLinks: entityLinks ?? this.entityLinks,
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
        'description': description,
        'entityLinks': entityLinks.map((e) => e.toMap()).toList(),
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
        'customProperties': customProperties,
      };

  factory RoomNodeState.fromMap(
    Map<String, dynamic> map, {
    dynamic Function(Map<String, dynamic>)? minionParser,
  }) {
    final parser = minionParser ?? defaultMinionParser ?? (m) => deepFreezeMap(m);

    CrdtOrSet<dynamic> minionsSet = const CrdtOrSet<dynamic>.empty();
    if (map.containsKey('activeMinions_crdt') && map['activeMinions_crdt'] != null) {
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
    } else if (map.containsKey('activeMinions') && map['activeMinions'] != null) {
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
    if (map.containsKey('activeEncounter_crdt') && map['activeEncounter_crdt'] != null) {
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
    } else if (map.containsKey('activeEncounter') && map['activeEncounter'] != null) {
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
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      entityLinks: (map['entityLinks'] as List? ?? [])
          .whereType<Map>()
          .map((l) => RoomEntityLink.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomNodeState &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          roomCode == other.roomCode &&
          title == other.title &&
          description == other.description &&
          _deepEquality.equals(entityLinks, other.entityLinks) &&
          _deepEquality.equals(entityInstances, other.entityInstances) &&
          _deepEquality.equals(containers, other.containers) &&
          activeEncounter == other.activeEncounter &&
          activeMinions == other.activeMinions &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        roomId,
        roomCode,
        title,
        description,
        _deepEquality.hash(entityLinks),
        _deepEquality.hash(entityInstances),
        _deepEquality.hash(containers),
        activeEncounter,
        activeMinions,
        _deepEquality.hash(customProperties),
      );
}
