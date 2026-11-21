import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../crdt/crdt_lww_register.dart';
import '../../crdt/crdt_or_set.dart';
import '../../crdt/hybrid_logical_clock.dart';
import '../../utils/aggregate_join_utils.dart';
import '../../utils/deep_immutable.dart';
import '../entity_link_crdt_set.dart';
import '../loot_models.dart';
import 'encounter_participant.dart';
import 'entity_instance.dart';
import 'room_entity_link.dart';

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
    } else if (titleTimestamp != null) {
      throw ArgumentError(
        'Updating titleTimestamp via copyWith requires an authoritative title.',
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
    } else if (descriptionTimestamp != null) {
      throw ArgumentError(
        'Updating descriptionTimestamp via copyWith requires an authoritative description.',
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
          .whereType<Map<dynamic, dynamic>>()
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
