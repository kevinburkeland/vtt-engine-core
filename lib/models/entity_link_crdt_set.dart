import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import 'session_graph_models.dart';

/// Replicated tombstone tracking the removal of a specific entity-link incarnation.
@immutable
class EntityLinkTombstone {
  /// The incarnation/generation that this removal targets and terminates.
  final HybridLogicalClock targetGeneration;

  /// The timestamp of the removal write.
  final HybridLogicalClock timestamp;

  const EntityLinkTombstone({
    required this.targetGeneration,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'targetGeneration': targetGeneration.toMap(),
        'timestamp': timestamp.toMap(),
      };

  factory EntityLinkTombstone.fromMap(Map<dynamic, dynamic> map) {
    final safeMap = Map<String, dynamic>.from(map);
    final rawGen = safeMap['targetGeneration'] ?? safeMap['targetIncarnation'];
    final rawTs = safeMap['timestamp'] ?? safeMap['ts'];

    if (rawGen != null && rawTs != null) {
      if (rawGen is! Map) {
        throw const FormatException(
            'EntityLinkTombstone.fromMap: "targetGeneration" must be a Map.');
      }
      if (rawTs is! Map) {
        throw const FormatException(
            'EntityLinkTombstone.fromMap: "timestamp" must be a Map.');
      }
      return EntityLinkTombstone(
        targetGeneration:
            HybridLogicalClock.fromMap(Map<String, dynamic>.from(rawGen)),
        timestamp:
            HybridLogicalClock.fromMap(Map<String, dynamic>.from(rawTs)),
      );
    } else if (safeMap.containsKey('physicalTime')) {
      // Deterministic migration for legacy tombstones:
      final legacyHlc = HybridLogicalClock.fromMap(safeMap);
      return EntityLinkTombstone(
        targetGeneration: legacyHlc,
        timestamp: legacyHlc,
      );
    } else {
      throw const FormatException(
          'EntityLinkTombstone.fromMap: malformed tombstone payload.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityLinkTombstone &&
          targetGeneration == other.targetGeneration &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(targetGeneration, timestamp);

  @override
  String toString() =>
      'EntityLinkTombstone(targetGeneration: $targetGeneration, timestamp: $timestamp)';
}

/// Generation-aware replicated collection for [RoomEntityLink] instances.
///
/// Implements a strict join-semilattice where:
/// 1. Higher generation strictly dominates lower generation.
/// 2. For equal generation, removal strictly dominates active items.
/// 3. For equal generation and both active, payloads recursively merge via [RoomEntityLink.join].
/// 4. For equal generation and both removed, the removal timestamp is max(tsA, tsB).
@immutable
class EntityLinkCrdtSet {
  final Map<String, CrdtLwwRegister<RoomEntityLink>> items;
  final Map<String, EntityLinkTombstone> tombstones;

  const EntityLinkCrdtSet.empty()
      : items = const {},
        tombstones = const {};

  EntityLinkCrdtSet({
    Map<String, CrdtLwwRegister<RoomEntityLink>>? items,
    Map<String, EntityLinkTombstone>? tombstones,
  })  : items = _canonicalizeItems(items, tombstones),
        tombstones = _canonicalizeTombstones(items, tombstones);

  static Map<String, CrdtLwwRegister<RoomEntityLink>> _canonicalizeItems(
    Map<String, CrdtLwwRegister<RoomEntityLink>>? items,
    Map<String, EntityLinkTombstone>? tombstones,
  ) {
    if (items == null || items.isEmpty) return const {};
    final result = <String, CrdtLwwRegister<RoomEntityLink>>{};
    for (final entry in items.entries) {
      final tomb = tombstones?[entry.key];
      if (tomb != null) {
        if (entry.value.value.incarnationTimestamp
            .isAfter(tomb.targetGeneration)) {
          result[entry.key] = entry.value;
        }
      } else {
        result[entry.key] = entry.value;
      }
    }
    return Map.unmodifiable(result);
  }

  static Map<String, EntityLinkTombstone> _canonicalizeTombstones(
    Map<String, CrdtLwwRegister<RoomEntityLink>>? items,
    Map<String, EntityLinkTombstone>? tombstones,
  ) {
    if (tombstones == null || tombstones.isEmpty) return const {};
    final result = <String, EntityLinkTombstone>{};
    for (final entry in tombstones.entries) {
      final item = items?[entry.key];
      if (item != null) {
        if (!item.value.incarnationTimestamp
            .isAfter(entry.value.targetGeneration)) {
          result[entry.key] = entry.value;
        }
      } else {
        result[entry.key] = entry.value;
      }
    }
    return Map.unmodifiable(result);
  }

  List<RoomEntityLink> get activeValues =>
      List.unmodifiable(items.values.map((reg) => reg.value));

  bool isRemoved(String id) =>
      tombstones.containsKey(id) && !items.containsKey(id);

  EntityLinkCrdtSet add(
    String id,
    RoomEntityLink link,
    HybridLogicalClock timestamp,
  ) {
    RoomEntityLink resolvedLink = link;
    if (resolvedLink.incarnationTimestamp.physicalTime == 0) {
      resolvedLink =
          resolvedLink.copyWith(incarnationTimestamp: timestamp);
    }

    final existingTombstone = tombstones[id];
    if (existingTombstone != null &&
        !resolvedLink.incarnationTimestamp
            .isAfter(existingTombstone.targetGeneration)) {
      resolvedLink = resolvedLink.copyWith(
        incarnationTimestamp: timestamp,
        displayNameTimestamp: timestamp,
      );
    }

    final newItems =
        Map<String, CrdtLwwRegister<RoomEntityLink>>.from(items);
    newItems[id] = CrdtLwwRegister<RoomEntityLink>(
      value: resolvedLink,
      timestamp: timestamp,
    );

    final newTombstones = Map<String, EntityLinkTombstone>.from(tombstones);
    newTombstones.remove(id);

    return EntityLinkCrdtSet(
      items: newItems,
      tombstones: newTombstones,
    );
  }

  EntityLinkCrdtSet addBatch(
    Iterable<({String id, RoomEntityLink item, HybridLogicalClock timestamp})>
        entries,
  ) {
    EntityLinkCrdtSet current = this;
    for (final e in entries) {
      current = current.add(e.id, e.item, e.timestamp);
    }
    return current;
  }

  EntityLinkCrdtSet remove(
    String id,
    HybridLogicalClock timestamp, {
    HybridLogicalClock? targetGeneration,
  }) {
    final HybridLogicalClock resolvedTargetGen = targetGeneration ??
        items[id]?.value.incarnationTimestamp ??
        tombstones[id]?.targetGeneration ??
        timestamp;

    HybridLogicalClock resolvedTs = timestamp;
    final existingTombstone = tombstones[id];
    if (existingTombstone != null &&
        existingTombstone.targetGeneration == resolvedTargetGen) {
      if (existingTombstone.timestamp.isAfter(resolvedTs)) {
        resolvedTs = existingTombstone.timestamp;
      }
    }

    final newItems =
        Map<String, CrdtLwwRegister<RoomEntityLink>>.from(items);
    newItems.remove(id);

    final newTombstones = Map<String, EntityLinkTombstone>.from(tombstones);
    newTombstones[id] = EntityLinkTombstone(
      targetGeneration: resolvedTargetGen,
      timestamp: resolvedTs,
    );

    return EntityLinkCrdtSet(
      items: newItems,
      tombstones: newTombstones,
    );
  }

  EntityLinkCrdtSet merge(EntityLinkCrdtSet other) {
    if (identical(this, other)) return this;

    final allIds = <String>{
      ...items.keys,
      ...tombstones.keys,
      ...other.items.keys,
      ...other.tombstones.keys,
    };

    final mergedItems = <String, CrdtLwwRegister<RoomEntityLink>>{};
    final mergedTombstones = <String, EntityLinkTombstone>{};

    for (final id in allIds) {
      final localItem = items[id];
      final remoteItem = other.items[id];
      final localTomb = tombstones[id];
      final remoteTomb = other.tombstones[id];

      // 1. Resolve candidate tombstone
      EntityLinkTombstone? candidateTomb;
      if (localTomb != null && remoteTomb != null) {
        if (localTomb.targetGeneration == remoteTomb.targetGeneration) {
          candidateTomb = EntityLinkTombstone(
            targetGeneration: localTomb.targetGeneration,
            timestamp: localTomb.timestamp.isAfter(remoteTomb.timestamp)
                ? localTomb.timestamp
                : remoteTomb.timestamp,
          );
        } else if (localTomb.targetGeneration
            .isAfter(remoteTomb.targetGeneration)) {
          candidateTomb = localTomb;
        } else {
          candidateTomb = remoteTomb;
        }
      } else {
        candidateTomb = localTomb ?? remoteTomb;
      }

      // 2. Resolve candidate item
      CrdtLwwRegister<RoomEntityLink>? candidateItem;
      if (localItem != null && remoteItem != null) {
        if (localItem.value.incarnationTimestamp ==
            remoteItem.value.incarnationTimestamp) {
          // Same generation: recursively compose fields
          final mergedLink =
              RoomEntityLink.join(localItem.value, remoteItem.value);
          final winningTs = localItem.timestamp.isAfter(remoteItem.timestamp)
              ? localItem.timestamp
              : remoteItem.timestamp;
          candidateItem = CrdtLwwRegister<RoomEntityLink>(
            value: mergedLink,
            timestamp: winningTs,
          );
        } else if (localItem.value.incarnationTimestamp
            .isAfter(remoteItem.value.incarnationTimestamp)) {
          candidateItem = localItem;
        } else {
          candidateItem = remoteItem;
        }
      } else {
        candidateItem = localItem ?? remoteItem;
      }

      // 3. Reconcile candidate item vs candidate tombstone
      if (candidateItem != null && candidateTomb != null) {
        if (candidateItem.value.incarnationTimestamp
            .isAfter(candidateTomb.targetGeneration)) {
          // Item belongs to a newer generation than the tombstone target -> ITEM WINS!
          mergedItems[id] = candidateItem;
        } else {
          // Tombstone targets this generation (or a newer one) -> TOMBSTONE WINS!
          mergedTombstones[id] = candidateTomb;
        }
      } else if (candidateItem != null) {
        mergedItems[id] = candidateItem;
      } else if (candidateTomb != null) {
        mergedTombstones[id] = candidateTomb;
      }
    }

    return EntityLinkCrdtSet(
      items: mergedItems,
      tombstones: mergedTombstones,
    );
  }

  List<HybridLogicalClock> extractTimestamps() {
    final result = <HybridLogicalClock>[];
    for (final reg in items.values) {
      if (reg.timestamp.physicalTime > 0) {
        result.add(reg.timestamp);
      }
      if (reg.value.incarnationTimestamp.physicalTime > 0 &&
          reg.value.incarnationTimestamp != reg.timestamp) {
        result.add(reg.value.incarnationTimestamp);
      }
      if (reg.value.displayNameRegister.timestamp.physicalTime > 0 &&
          reg.value.displayNameRegister.timestamp != reg.timestamp &&
          reg.value.displayNameRegister.timestamp != reg.value.incarnationTimestamp) {
        result.add(reg.value.displayNameRegister.timestamp);
      }
      if (reg.value.notesRegister.timestamp.physicalTime > 0 &&
          reg.value.notesRegister.timestamp != reg.timestamp &&
          reg.value.notesRegister.timestamp != reg.value.incarnationTimestamp) {
        result.add(reg.value.notesRegister.timestamp);
      }
    }
    for (final tomb in tombstones.values) {
      if (tomb.targetGeneration.physicalTime > 0) {
        result.add(tomb.targetGeneration);
      }
      if (tomb.timestamp.physicalTime > 0 &&
          tomb.timestamp != tomb.targetGeneration) {
        result.add(tomb.timestamp);
      }
    }
    return result;
  }

  Map<String, dynamic> toMap(
      [dynamic Function(RoomEntityLink)? itemEncoder]) {
    final encoder = itemEncoder ?? (link) => link.toMap();
    final itemsMap = <String, dynamic>{};
    for (final entry in items.entries) {
      itemsMap[entry.key] = {
        'v': encoder(entry.value.value),
        'ts': entry.value.timestamp.toMap(),
      };
    }
    final tombstonesMap = <String, dynamic>{};
    for (final entry in tombstones.entries) {
      tombstonesMap[entry.key] = entry.value.toMap();
    }
    return {
      'items': itemsMap,
      'tombstones': tombstonesMap,
    };
  }

  factory EntityLinkCrdtSet.fromMap(
    Map<dynamic, dynamic> map, [
    RoomEntityLink Function(dynamic)? itemDecoder,
  ]) {
    final decoder = itemDecoder ??
        (raw) {
          if (raw is! Map) {
            throw const FormatException(
                'EntityLinkCrdtSet.fromMap: raw item must be a Map.');
          }
          return RoomEntityLink.fromMap(Map<String, dynamic>.from(raw));
        };

    final itemsMap = <String, CrdtLwwRegister<RoomEntityLink>>{};
    if (map.containsKey('items')) {
      final rawItems = map['items'];
      if (rawItems is! Map) {
        throw const FormatException(
            'EntityLinkCrdtSet.fromMap: "items" must be a Map.');
      }
      for (final entry in rawItems.entries) {
        final key = entry.key.toString();
        final rawReg = entry.value;
        if (rawReg is! Map) {
          throw FormatException(
              'EntityLinkCrdtSet.fromMap: register for "$key" must be a Map.');
        }
        final safeReg = Map<String, dynamic>.from(rawReg);
        final rawTs = safeReg['ts'] ?? safeReg['timestamp'];
        if (rawTs is! Map) {
          throw FormatException(
              'EntityLinkCrdtSet.fromMap: missing or invalid timestamp for "$key".');
        }
        if (!safeReg.containsKey('v') && !safeReg.containsKey('value')) {
          throw FormatException(
              'EntityLinkCrdtSet.fromMap: missing "v" or "value" for "$key".');
        }
        final rawVal =
            safeReg.containsKey('v') ? safeReg['v'] : safeReg['value'];
        if (rawVal == null) {
          throw FormatException(
              'EntityLinkCrdtSet.fromMap: value for "$key" must not be null.');
        }
        final link = decoder(rawVal);
        final ts =
            HybridLogicalClock.fromMap(Map<String, dynamic>.from(rawTs));
        itemsMap[key] =
            CrdtLwwRegister<RoomEntityLink>(value: link, timestamp: ts);
      }
    }

    final tombstonesMap = <String, EntityLinkTombstone>{};
    if (map.containsKey('tombstones')) {
      final rawTombs = map['tombstones'];
      if (rawTombs is! Map) {
        throw const FormatException(
            'EntityLinkCrdtSet.fromMap: "tombstones" must be a Map.');
      }
      for (final entry in rawTombs.entries) {
        final key = entry.key.toString();
        final rawTomb = entry.value;
        if (rawTomb is! Map) {
          throw FormatException(
              'EntityLinkCrdtSet.fromMap: tombstone for "$key" must be a Map.');
        }
        tombstonesMap[key] = EntityLinkTombstone.fromMap(
            Map<String, dynamic>.from(rawTomb));
      }
    }

    return EntityLinkCrdtSet(
      items: itemsMap,
      tombstones: tombstonesMap,
    );
  }

  factory EntityLinkCrdtSet.fromCrdtOrSet(
      CrdtOrSet<RoomEntityLink> orSet) {
    final tombs = <String, EntityLinkTombstone>{};
    for (final entry in orSet.tombstones.entries) {
      tombs[entry.key] = EntityLinkTombstone(
        targetGeneration: entry.value,
        timestamp: entry.value,
      );
    }
    return EntityLinkCrdtSet(
      items: orSet.items,
      tombstones: tombs,
    );
  }

  CrdtOrSet<RoomEntityLink> toCrdtOrSet() {
    final legacyTombs = <String, HybridLogicalClock>{};
    for (final entry in tombstones.entries) {
      legacyTombs[entry.key] = entry.value.timestamp;
    }
    return CrdtOrSet<RoomEntityLink>(
      items: items,
      tombstones: legacyTombs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EntityLinkCrdtSet) return false;
    if (items.length != other.items.length ||
        tombstones.length != other.tombstones.length) {
      return false;
    }
    for (final key in items.keys) {
      final regA = items[key];
      final regB = other.items[key];
      if (regB == null || regA != regB) return false;
    }
    for (final key in tombstones.keys) {
      final tombA = tombstones[key];
      final tombB = other.tombstones[key];
      if (tombB == null || tombA != tombB) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hItems = 0;
    for (final entry in items.entries) {
      hItems ^= Object.hash(entry.key, entry.value);
    }
    int hTombs = 0;
    for (final entry in tombstones.entries) {
      hTombs ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(hItems, hTombs);
  }

  @override
  String toString() =>
      'EntityLinkCrdtSet(items: ${items.length}, tombstones: ${tombstones.length})';
}
