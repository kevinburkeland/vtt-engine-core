import 'package:collection/collection.dart';
import '../crdt/crdt_or_set.dart';
import '../models/loot_models.dart';
import '../models/party_event.dart';
import '../models/session_graph_models.dart';
import 'deep_immutable.dart';

const _deepEquality = DeepCollectionEquality();

/// Merges two unversioned strings symmetrically.
///
/// If both strings are identical, returns the string.
/// If one is empty and the other is non-empty, returns the non-empty string.
/// If both are non-empty and differ, throws [StateError] failing loudly and symmetrically.
String joinUnversionedString(
  String a,
  String b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  throw StateError(
    'Divergent unversioned scalar field "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically validates and merges two immutable identifiers.
///
/// If both identifiers match, returns the identifier.
/// If one is empty and the other is non-empty, returns the non-empty identifier.
/// If both are non-empty and differ, throws [StateError] failing loudly and symmetrically.
String joinImmutableId(
  String a,
  String b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  throw StateError(
    'Immutable identity field mismatch for "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically merges two nullable unversioned strings.
String? joinNullableString(
  String? a,
  String? b, {
  required String fieldName,
}) {
  if (a == b) return a;
  if (a == null || a.isEmpty) return b;
  if (b == null || b.isEmpty) return a;
  throw StateError(
    'Divergent unversioned nullable scalar field "$fieldName": "$a" vs "$b".',
  );
}

/// Symmetrically merges two JSON-like maps (e.g. `customProperties`, `permissions`, `runtimeData`)
/// with per-key ownership semantics.
///
/// Disjoint keys union deterministically with canonical sorted key ordering.
/// Same key with deep structural equality preserves the value.
/// Same key with divergent values without causal metadata fails loudly and symmetrically.
Map<String, dynamic> joinCustomProperties(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String context,
}) {
  if (identical(a, b)) return a;
  if (_deepEquality.equals(a, b)) return a;

  final allKeys = {...a.keys, ...b.keys}.toList()..sort();
  final result = <String, dynamic>{};
  for (final key in allKeys) {
    if (a.containsKey(key) && b.containsKey(key)) {
      final valA = a[key];
      final valB = b[key];
      if (!_deepEquality.equals(valA, valB)) {
        throw StateError(
          'Divergent unversioned value for key "$key" in $context: '
          '"$valA" vs "$valB".',
        );
      }
      result[key] = valA;
    } else if (a.containsKey(key)) {
      result[key] = a[key];
    } else {
      result[key] = b[key];
    }
  }
  return deepFreezeMap(result);
}

/// Symmetrically merges two nullable maps.
Map<String, dynamic>? joinNullableMap(
  Map<String, dynamic>? a,
  Map<String, dynamic>? b, {
  required String context,
}) {
  if (a == null && b == null) return null;
  if (a == null) return b != null ? deepFreezeMap(b) : null;
  if (b == null) return deepFreezeMap(a);
  return joinCustomProperties(a, b, context: context);
}

/// Merges two audit/change logs deduplicating identical events by ID,
/// sorting deterministically by timestamp and ID, and failing loudly on
/// divergent payloads under the same event ID.
List<PartyEvent> joinChangeLog(List<PartyEvent> a, List<PartyEvent> b) {
  if (identical(a, b)) return a;
  final eventMapA = <String, PartyEvent>{};
  for (final ev in a) {
    eventMapA[ev.id] = ev;
  }
  final eventMapB = <String, PartyEvent>{};
  for (final ev in b) {
    eventMapB[ev.id] = ev;
  }
  final allEventIds = <String>{...eventMapA.keys, ...eventMapB.keys};
  final mergedEvents = <PartyEvent>[];
  for (final id in allEventIds) {
    final evA = eventMapA[id];
    final evB = eventMapB[id];
    if (evA != null && evB != null) {
      if (evA != evB) {
        throw StateError(
          'Divergent PartyEvent under same event id "$id".',
        );
      }
      mergedEvents.add(evA);
    } else if (evA != null) {
      mergedEvents.add(evA);
    } else if (evB != null) {
      mergedEvents.add(evB);
    }
  }
  mergedEvents.sort((x, y) {
    final cmp = x.timestamp.compareTo(y.timestamp);
    if (cmp != 0) return cmp;
    return x.id.compareTo(y.id);
  });
  return List.unmodifiable(mergedEvents);
}

/// Symmetrically merges two [CrdtOrSet<String>] party roster collections via CvRDT OR-Set join.
CrdtOrSet<String> joinPartyRosterCrdt(
  CrdtOrSet<String> a,
  CrdtOrSet<String> b,
) {
  return a.merge(b);
}

CrdtOrSet<String> joinPinnedRules(
  CrdtOrSet<String> a,
  CrdtOrSet<String> b,
) {
  return a.merge(b);
}

/// Symmetrically merges two [CrdtOrSet<RoomEntityLink>] collections.
CrdtOrSet<RoomEntityLink> joinEntityLinks(
  CrdtOrSet<RoomEntityLink> a,
  CrdtOrSet<RoomEntityLink> b,
) {
  return a.merge(b);
}

/// Merges two lists of [EntityInstance] by ID, recursively joining instances
/// with identical instanceId, and sorting deterministically by instanceId.
List<EntityInstance> joinEntityInstances(
  List<EntityInstance> a,
  List<EntityInstance> b,
) {
  final instancesMapA = <String, EntityInstance>{};
  for (final i in a) {
    instancesMapA[i.instanceId] = i;
  }
  final instancesMapB = <String, EntityInstance>{};
  for (final i in b) {
    instancesMapB[i.instanceId] = i;
  }
  final allInstanceIds = <String>{...instancesMapA.keys, ...instancesMapB.keys}.toList()..sort();
  final mergedInstances = <EntityInstance>[];
  for (final id in allInstanceIds) {
    final instA = instancesMapA[id];
    final instB = instancesMapB[id];
    if (instA != null && instB != null) {
      mergedInstances.add(EntityInstance.join(instA, instB));
    } else if (instA != null) {
      mergedInstances.add(instA);
    } else if (instB != null) {
      mergedInstances.add(instB);
    }
  }
  return List.unmodifiable(mergedInstances);
}

/// Merges two lists of [LootContainer] by ID, recursively joining containers
/// with identical containerId, and sorting deterministically by containerId.
List<LootContainer> joinContainers(
  List<LootContainer> a,
  List<LootContainer> b,
) {
  final containerMapA = <String, LootContainer>{};
  for (final c in a) {
    containerMapA[c.containerId] = c;
  }
  final containerMapB = <String, LootContainer>{};
  for (final c in b) {
    containerMapB[c.containerId] = c;
  }
  final allContainerIds = <String>{...containerMapA.keys, ...containerMapB.keys}.toList()..sort();
  final mergedContainers = <LootContainer>[];
  for (final id in allContainerIds) {
    final cA = containerMapA[id];
    final cB = containerMapB[id];
    if (cA != null && cB != null) {
      mergedContainers.add(LootContainer.join(cA, cB));
    } else if (cA != null) {
      mergedContainers.add(cA);
    } else if (cB != null) {
      mergedContainers.add(cB);
    }
  }
  return List.unmodifiable(mergedContainers);
}
