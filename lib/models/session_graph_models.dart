import '../utils/deep_immutable.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import 'loot_models.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) =>
    const ListEquality().equals(a, b);
bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);

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
      (other is EntityCategory && key == other.key) ||
      (other is Enum && key == other.name) ||
      (other is String && key == other);

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
          _mapEquals(position, other.position) &&
          isVisible == other.isVisible &&
          _mapEquals(runtimeData, other.runtimeData) &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        instanceId,
        entityDefinitionId,
        entityType,
        displayName,
        isVisible,
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

  Map<String, dynamic> toMap() => {
        'refType': refType is Enum
            ? (refType as Enum).name
            : (refType is EntityCategory ? (refType as EntityCategory).key : refType.toString()),
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
          refType == other.refType &&
          entityId == other.entityId &&
          displayName == other.displayName &&
          notes == other.notes &&
          _mapEquals(position, other.position) &&
          isIsolatedClone == other.isIsolatedClone &&
          _mapEquals(cloneRuntimeData, other.cloneRuntimeData);

  @override
  int get hashCode => Object.hash(
        refType,
        entityId,
        displayName,
        notes,
        isIsolatedClone,
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
          _listEquals(activeConditions, other.activeConditions) &&
          isDefeated == other.isDefeated &&
          isDead == other.isDead &&
          isActiveTurn == other.isActiveTurn &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        participantId,
        entityLink,
        initiativeScore,
        currentHp,
        maxHp,
        defense,
        isActiveTurn,
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
              id: (m != null ? (m as dynamic).id ?? '' : '').toString(),
              item: m,
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
    dynamic activeEncounter,
    dynamic activeMinions,
    Map<String, dynamic>? customProperties,
    String? nodeId,
  }) {
    CrdtOrSet<EncounterParticipant>? resolvedEncounter;
    if (activeEncounter is CrdtOrSet<EncounterParticipant>) {
      resolvedEncounter = activeEncounter;
    } else if (activeEncounter is Iterable<EncounterParticipant>) {
      if (nodeId == null || nodeId.trim().isEmpty) {
        throw ArgumentError.value(
            nodeId, 'nodeId', 'Valid nodeId required when converting activeEncounter Iterable to CrdtOrSet.');
      }
      if (nodeId.trim().toLowerCase() == 'local') {
        throw ArgumentError.value(
            nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      var set = const CrdtOrSet<EncounterParticipant>.empty();
      for (final p in activeEncounter) {
        set = set.add(
            p.participantId,
            p,
            HybridLogicalClock(
                physicalTime: now, logicalCounter: 0, nodeId: nodeId));
      }
      resolvedEncounter = set;
    }

    CrdtOrSet<dynamic>? resolvedMinions;
    if (activeMinions is CrdtOrSet<dynamic>) {
      resolvedMinions = activeMinions;
    } else if (activeMinions is Iterable<dynamic>) {
      if (nodeId == null || nodeId.trim().isEmpty) {
        throw ArgumentError.value(
            nodeId, 'nodeId', 'Valid nodeId required when converting activeMinions Iterable to CrdtOrSet.');
      }
      if (nodeId.trim().toLowerCase() == 'local') {
        throw ArgumentError.value(
            nodeId, 'nodeId', 'CRDT mutations cannot use "local" as replica identity.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      var set = const CrdtOrSet<dynamic>.empty();
      for (final m in activeMinions) {
        final id = (m != null ? (m as dynamic).id ?? '' : '').toString();
        set = set.add(
            id,
            m,
            HybridLogicalClock(
                physicalTime: now, logicalCounter: 0, nodeId: nodeId));
      }
      resolvedMinions = set;
    }

    return RoomNodeState(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      title: title ?? this.title,
      description: description ?? this.description,
      entityLinks: entityLinks ?? this.entityLinks,
      entityInstances: entityInstances ?? this.entityInstances,
      containers: containers ?? this.containers,
      activeEncounter: resolvedEncounter ?? this.activeEncounter,
      activeMinions: resolvedMinions ?? this.activeMinions,
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
    final parser = minionParser ?? defaultMinionParser ?? (m) => m;

    CrdtOrSet<dynamic> minionsSet = const CrdtOrSet<dynamic>.empty();
    if (map['activeMinions_crdt'] is Map) {
      try {
        minionsSet = CrdtOrSet<dynamic>.fromMap(
          Map<dynamic, dynamic>.from(map['activeMinions_crdt'] as Map),
          (raw) => parser(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeMinions'] is Map &&
        (map['activeMinions'] as Map).containsKey('items')) {
      try {
        minionsSet = CrdtOrSet<dynamic>.fromMap(
          Map<dynamic, dynamic>.from(map['activeMinions'] as Map),
          (raw) => parser(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeMinions'] is List) {
      final rawMinions = map['activeMinions'] as List;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final raw in rawMinions) {
        if (raw is Map) {
          try {
            final m = parser(Map<String, dynamic>.from(raw));
            final id = (raw['id'] ?? (m != null ? (m as dynamic).id : '')).toString();
            minionsSet = minionsSet.add(
                id,
                m,
                HybridLogicalClock(
                    physicalTime: now, logicalCounter: 0, nodeId: 'genesis'));
          } catch (_) {}
        }
      }
    }

    CrdtOrSet<EncounterParticipant> encounterSet =
        const CrdtOrSet<EncounterParticipant>.empty();
    if (map['activeEncounter_crdt'] is Map) {
      try {
        encounterSet = CrdtOrSet<EncounterParticipant>.fromMap(
          Map<dynamic, dynamic>.from(map['activeEncounter_crdt'] as Map),
          (raw) => EncounterParticipant.fromMap(
              Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeEncounter'] is Map &&
        (map['activeEncounter'] as Map).containsKey('items')) {
      try {
        encounterSet = CrdtOrSet<EncounterParticipant>.fromMap(
          Map<dynamic, dynamic>.from(map['activeEncounter'] as Map),
          (raw) => EncounterParticipant.fromMap(
              Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeEncounter'] is List) {
      final rawEnc = map['activeEncounter'] as List;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final raw in rawEnc) {
        if (raw is Map) {
          try {
            final p =
                EncounterParticipant.fromMap(Map<String, dynamic>.from(raw));
            encounterSet = encounterSet.add(
                p.participantId,
                p,
                HybridLogicalClock(
                    physicalTime: now, logicalCounter: 0, nodeId: 'genesis'));
          } catch (_) {}
        }
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
          _listEquals(entityLinks, other.entityLinks) &&
          _listEquals(entityInstances, other.entityInstances) &&
          _listEquals(containers, other.containers) &&
          activeEncounter == other.activeEncounter &&
          activeMinions == other.activeMinions &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        roomId,
        roomCode,
        title,
        description,
        activeEncounter,
        activeMinions,
      );
}
