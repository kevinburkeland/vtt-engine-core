import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import 'minion_instance.dart';
import 'value_objects/hit_points.dart';
import 'loot_models.dart';

bool listEquals<T>(List<T>? a, List<T>? b) => const ListEquality().equals(a, b);

/// Entity Types bindable within a session or room node
enum SessionRefType {
  character,
  monster,
  npc,
  lootContainer;

  String get displayName => switch (this) {
        SessionRefType.character => 'Player Character',
        SessionRefType.monster => 'Monster',
        SessionRefType.npc => 'NPC',
        SessionRefType.lootContainer => 'Loot Container',
      };
}

/// Contextual pointer linking characters, monsters, or objects to a room or graph node
@immutable
class RoomEntityLink {
  final SessionRefType refType;
  final String entityId;
  final String displayName;
  final String? notes;
  final Map<String, dynamic>? position; // e.g. {"x": 2, "y": 5}
  final bool
      isIsolatedClone; // If true, runtime modifications don't mutate parent template
  final Map<String, dynamic>?
      cloneRuntimeData; // HP, condition overrides for clones

  const RoomEntityLink({
    required this.refType,
    required this.entityId,
    required this.displayName,
    this.notes,
    this.position,
    this.isIsolatedClone = false,
    this.cloneRuntimeData,
  });

  RoomEntityLink copyWith({
    SessionRefType? refType,
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
        'refType': refType.name,
        'entityId': entityId,
        'displayName': displayName,
        'notes': notes,
        'position': position,
        'isIsolatedClone': isIsolatedClone,
        'cloneRuntimeData': cloneRuntimeData,
      };

  factory RoomEntityLink.fromMap(Map<String, dynamic> map) {
    final typeStr = map['refType']?.toString() ?? 'character';
    final refType = SessionRefType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => SessionRefType.character,
    );

    return RoomEntityLink(
      refType: refType,
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
}

/// Dynamic Combat and Turn-Tracker Participant in an active room encounter
@immutable
class EncounterParticipant {
  final String participantId;
  final RoomEntityLink entityLink;
  final int initiativeScore;
  final int initiativeTieBreaker;
  final int currentHp;
  final int maxHp;
  final int tempHp;
  final int armorClass;
  final List<String> activeConditions;
  final bool isDefeated;
  final bool isDead;
  final bool isActiveTurn;

  HitPoints get hitPoints => HitPoints(
        currentHp: currentHp,
        maxHp: maxHp,
        tempHp: tempHp,
        isDead: isDead,
      );

  const EncounterParticipant({
    required this.participantId,
    required this.entityLink,
    this.initiativeScore = 10,
    this.initiativeTieBreaker = 0,
    this.currentHp = 10,
    this.maxHp = 10,
    this.tempHp = 0,
    this.armorClass = 10,
    this.activeConditions = const [],
    this.isDefeated = false,
    this.isDead = false,
    this.isActiveTurn = false,
  });

  EncounterParticipant copyWith({
    String? participantId,
    RoomEntityLink? entityLink,
    int? initiativeScore,
    int? initiativeTieBreaker,
    HitPoints? hitPoints,
    int? currentHp,
    int? maxHp,
    int? tempHp,
    int? armorClass,
    List<String>? activeConditions,
    bool? isDefeated,
    bool? isDead,
    bool? isActiveTurn,
  }) {
    final int resolvedCurrentHp =
        hitPoints?.currentHp ?? currentHp ?? this.currentHp;
    final int resolvedMaxHp = hitPoints?.maxHp ?? maxHp ?? this.maxHp;
    final int resolvedTempHp = hitPoints?.tempHp ?? tempHp ?? this.tempHp;
    final bool resolvedIsDead = hitPoints?.isDead ?? isDead ?? this.isDead;

    return EncounterParticipant(
      participantId: participantId ?? this.participantId,
      entityLink: entityLink ?? this.entityLink,
      initiativeScore: initiativeScore ?? this.initiativeScore,
      initiativeTieBreaker: initiativeTieBreaker ?? this.initiativeTieBreaker,
      currentHp: resolvedCurrentHp,
      maxHp: resolvedMaxHp,
      tempHp: resolvedTempHp,
      armorClass: armorClass ?? this.armorClass,
      activeConditions: activeConditions ?? this.activeConditions,
      isDefeated: isDefeated ?? this.isDefeated,
      isDead: resolvedIsDead,
      isActiveTurn: isActiveTurn ?? this.isActiveTurn,
    );
  }

  Map<String, dynamic> toMap() => {
        'participantId': participantId,
        'entityLink': entityLink.toMap(),
        'initiativeScore': initiativeScore,
        'initiativeTieBreaker': initiativeTieBreaker,
        'currentHp': currentHp,
        'maxHp': maxHp,
        'tempHp': tempHp,
        'armorClass': armorClass,
        'activeConditions': activeConditions,
        'isDefeated': isDefeated,
        'isDead': isDead,
        'isActiveTurn': isActiveTurn,
      };

  factory EncounterParticipant.fromMap(Map<String, dynamic> map) {
    final cur = (map['currentHp'] as num?)?.toInt() ?? 10;
    final max = (map['maxHp'] as num?)?.toInt() ?? 10;
    final temp = (map['tempHp'] as num?)?.toInt() ?? 0;
    final hp = map['hitPoints'] is Map
        ? HitPoints(
            currentHp:
                ((map['hitPoints'] as Map)['currentHp'] as num?)?.toInt() ??
                    cur,
            maxHp: ((map['hitPoints'] as Map)['maxHp'] as num?)?.toInt() ?? max,
            tempHp:
                ((map['hitPoints'] as Map)['tempHp'] as num?)?.toInt() ?? temp,
            isDead: (map['hitPoints'] as Map)['isDead'] == true,
          )
        : HitPoints(currentHp: cur, maxHp: max, tempHp: temp);

    return EncounterParticipant(
      participantId: map['participantId']?.toString() ?? '',
      entityLink: RoomEntityLink.fromMap(
          Map<String, dynamic>.from(map['entityLink'] as Map? ?? {})),
      initiativeScore: (map['initiativeScore'] as num?)?.toInt() ?? 10,
      initiativeTieBreaker: (map['initiativeTieBreaker'] as num?)?.toInt() ?? 0,
      currentHp: hp.currentHp,
      maxHp: hp.maxHp,
      tempHp: hp.tempHp,
      armorClass: (map['armorClass'] as num?)?.toInt() ?? 10,
      activeConditions:
          (map['activeConditions'] as List? ?? []).whereType<String>().toList(),
      isDefeated: map['isDefeated'] == true,
      isDead: map['isDead'] == true || hp.isDead,
      isActiveTurn: map['isActiveTurn'] == true,
    );
  }
}

/// Root Node Representation of a dynamic Dungeon Room or Session Graph State
@immutable
class RoomNodeState {
  final String roomId;
  final String roomCode;
  final String title;
  final String description;
  final List<RoomEntityLink> entityLinks;
  final List<LootContainer> containers;
  final CrdtOrSet<EncounterParticipant> activeEncounter;
  final CrdtOrSet<MinionInstance> activeMinions;
  final Map<String, dynamic> customProperties;

  List<EncounterParticipant> get activeEncounterList =>
      activeEncounter.activeValues;
  List<MinionInstance> get activeMinionsList => activeMinions.activeValues;

  const RoomNodeState({
    required this.roomId,
    required this.roomCode,
    required this.title,
    this.description = '',
    this.entityLinks = const [],
    this.containers = const [],
    this.activeEncounter = const CrdtOrSet<EncounterParticipant>.empty(),
    this.activeMinions = const CrdtOrSet<MinionInstance>.empty(),
    this.customProperties = const {},
  });

  factory RoomNodeState.fromLists({
    required String roomId,
    required String roomCode,
    required String title,
    String description = '',
    List<RoomEntityLink> entityLinks = const [],
    List<LootContainer> containers = const [],
    Iterable<EncounterParticipant>? activeEncounter,
    Iterable<MinionInstance>? activeMinions,
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
        ? const CrdtOrSet<MinionInstance>.empty().addBatch(activeMinions.map(
            (m) => (
              id: m.id,
              item: m,
              timestamp: const HybridLogicalClock(
                physicalTime: 0,
                logicalCounter: 0,
                nodeId: 'genesis',
              ),
            ),
          ))
        : const CrdtOrSet<MinionInstance>.empty();

    return RoomNodeState(
      roomId: roomId,
      roomCode: roomCode,
      title: title,
      description: description,
      entityLinks: entityLinks,
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
    List<LootContainer>? containers,
    dynamic activeEncounter,
    dynamic activeMinions,
    Map<String, dynamic>? customProperties,
  }) {
    CrdtOrSet<EncounterParticipant>? resolvedEncounter;
    if (activeEncounter is CrdtOrSet<EncounterParticipant>) {
      resolvedEncounter = activeEncounter;
    } else if (activeEncounter is Iterable<EncounterParticipant>) {
      final now = DateTime.now().millisecondsSinceEpoch;
      var set = const CrdtOrSet<EncounterParticipant>.empty();
      for (final p in activeEncounter) {
        set = set.add(
            p.participantId,
            p,
            HybridLogicalClock(
                physicalTime: now, logicalCounter: 0, nodeId: 'local'));
      }
      resolvedEncounter = set;
    }

    CrdtOrSet<MinionInstance>? resolvedMinions;
    if (activeMinions is CrdtOrSet<MinionInstance>) {
      resolvedMinions = activeMinions;
    } else if (activeMinions is Iterable<MinionInstance>) {
      final now = DateTime.now().millisecondsSinceEpoch;
      var set = const CrdtOrSet<MinionInstance>.empty();
      for (final m in activeMinions) {
        set = set.add(
            m.id,
            m,
            HybridLogicalClock(
                physicalTime: now, logicalCounter: 0, nodeId: 'local'));
      }
      resolvedMinions = set;
    }

    return RoomNodeState(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      title: title ?? this.title,
      description: description ?? this.description,
      entityLinks: entityLinks ?? this.entityLinks,
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
        'containers': containers.map((c) => c.toMap()).toList(),
        'activeEncounter':
            activeEncounter.activeValues.map((e) => e.toMap()).toList(),
        'activeEncounter_crdt': activeEncounter.toMap((e) => e.toMap()),
        'activeMinions':
            activeMinions.activeValues.map((m) => m.toMap()).toList(),
        'activeMinions_crdt': activeMinions.toMap((m) => m.toMap()),
        'customProperties': customProperties,
      };

  factory RoomNodeState.fromMap(Map<String, dynamic> map) {
    CrdtOrSet<MinionInstance> minionsSet =
        const CrdtOrSet<MinionInstance>.empty();
    if (map['activeMinions_crdt'] is Map) {
      try {
        minionsSet = CrdtOrSet<MinionInstance>.fromMap(
          Map<dynamic, dynamic>.from(map['activeMinions_crdt'] as Map),
          (raw) =>
              MinionInstance.fromMap(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeMinions'] is Map &&
        (map['activeMinions'] as Map).containsKey('items')) {
      try {
        minionsSet = CrdtOrSet<MinionInstance>.fromMap(
          Map<dynamic, dynamic>.from(map['activeMinions'] as Map),
          (raw) =>
              MinionInstance.fromMap(Map<String, dynamic>.from(raw as Map)),
        );
      } catch (_) {}
    } else if (map['activeMinions'] is List) {
      final rawMinions = map['activeMinions'] as List;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final raw in rawMinions) {
        if (raw is Map) {
          try {
            final m = MinionInstance.fromMap(Map<String, dynamic>.from(raw));
            minionsSet = minionsSet.add(
                m.id,
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

    return RoomNodeState(
      roomId: map['roomId']?.toString() ?? '',
      roomCode: map['roomCode']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Room',
      description: map['description']?.toString() ?? '',
      entityLinks: (map['entityLinks'] as List? ?? [])
          .whereType<Map>()
          .map((e) => RoomEntityLink.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
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
          listEquals(entityLinks, other.entityLinks) &&
          listEquals(containers, other.containers) &&
          activeEncounter == other.activeEncounter &&
          activeMinions == other.activeMinions;

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
