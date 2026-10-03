import 'package:meta/meta.dart';
import 'crdt_lww_register.dart';
import 'hybrid_logical_clock.dart';

/// Observed-Remove Set (OR-Set) with explicit Tombstone tracking.
/// Provides deterministic reconciliation for collections (e.g., active conditions,
/// minion rosters) and prevents resurrection of deleted items across distributed nodes.
@immutable
class CrdtOrSet<T> {
  /// Maps item ID to the Register containing the item and its insertion timestamp.
  final Map<String, CrdtLwwRegister<T>> items;

  /// Maps item ID to the HLC timestamp of when it was removed.
  final Map<String, HybridLogicalClock> tombstones;

  CrdtOrSet({
    Map<String, CrdtLwwRegister<T>> items = const {},
    Map<String, HybridLogicalClock> tombstones = const {},
  })  : items = Map.unmodifiable(Map<String, CrdtLwwRegister<T>>.from(items)),
        tombstones = Map.unmodifiable(Map<String, HybridLogicalClock>.from(tombstones));

  const CrdtOrSet.empty()
      : items = const {},
        tombstones = const {};

  /// Returns the current list of active (non-tombstoned) values.
  List<T> get activeValues =>
      List.unmodifiable(items.values.map((r) => r.value));

  /// Returns the count of active values.
  int get length => items.length;

  /// Returns whether there are no active values.
  bool get isEmpty => items.isEmpty;

  /// Returns whether there are active values.
  bool get isNotEmpty => items.isNotEmpty;

  /// Returns the first active value.
  T get first => activeValues.first;

  /// Returns the last active value.
  T get last => activeValues.last;

  /// Returns the active value at index [index].
  T operator [](int index) => activeValues[index];

  /// Maps active values using [toElement].
  Iterable<R> map<R>(R Function(T e) toElement) => activeValues.map(toElement);

  /// Filters active values by [test].
  Iterable<T> where(bool Function(T element) test) => activeValues.where(test);

  /// Checks if any active value satisfies [test].
  bool any(bool Function(T element) test) => activeValues.any(test);

  /// Returns active values as a List.
  List<T> toList({bool growable = true}) =>
      activeValues.toList(growable: growable);

  /// Iterator over active values.
  Iterator<T> get iterator => activeValues.iterator;

  /// Adds or updates an item with the given [id] and [timestamp].
  /// If a tombstone exists for [id] that is newer than [timestamp], the addition is rejected.
  CrdtOrSet<T> add(String id, T item, HybridLogicalClock timestamp) {
    return addBatch([(id: id, item: item, timestamp: timestamp)]);
  }

  /// Adds or updates multiple items in a single batch operation to avoid O(N^2) map copies.
  CrdtOrSet<T> addBatch(
      Iterable<({String id, T item, HybridLogicalClock timestamp})> entries) {
    if (entries.isEmpty) return this;
    final newItems = Map<String, CrdtLwwRegister<T>>.from(items);
    final newTombstones = Map<String, HybridLogicalClock>.from(tombstones);

    for (final entry in entries) {
      final id = entry.id;
      final ts = entry.timestamp;
      if (!newTombstones.containsKey(id) || ts.isAfter(newTombstones[id]!)) {
        newItems[id] = CrdtLwwRegister(value: entry.item, timestamp: ts);
        newTombstones.remove(id);
      }
    }

    return CrdtOrSet(
      items: Map.unmodifiable(newItems),
      tombstones: Map.unmodifiable(newTombstones),
    );
  }

  /// Removes an item with the given [id] at [timestamp], recording a tombstone.
  /// Unconditionally records the tombstone if [timestamp] is strictly newer than
  /// any existing tombstone for [id], regardless of whether the item currently exists in items.
  CrdtOrSet<T> remove(String id, HybridLogicalClock timestamp) {
    final newItems = Map<String, CrdtLwwRegister<T>>.from(items);
    final newTombstones = Map<String, HybridLogicalClock>.from(tombstones);

    final currentItem = newItems[id];
    if (currentItem != null) {
      if (timestamp.isAfter(currentItem.timestamp)) {
        newItems.remove(id);
      } else {
        // Item was added/revived strictly after this removal timestamp.
        return CrdtOrSet(
          items: Map.unmodifiable(newItems),
          tombstones: Map.unmodifiable(newTombstones),
        );
      }
    }

    final existingTombstone = newTombstones[id];
    if (existingTombstone == null || timestamp.isAfter(existingTombstone)) {
      newTombstones[id] = timestamp;
    }

    return CrdtOrSet(
      items: Map.unmodifiable(newItems),
      tombstones: Map.unmodifiable(newTombstones),
    );
  }

  /// Merges this OR-Set with a [remote] OR-Set deterministically.
  CrdtOrSet<T> merge(CrdtOrSet<T> remote) {
    final mergedItems = Map<String, CrdtLwwRegister<T>>.from(items);
    final mergedTombstones = Map<String, HybridLogicalClock>.from(tombstones);

    // Merge tombstones
    remote.tombstones.forEach((id, remoteTs) {
      final localTs = mergedTombstones[id];
      final localItem = mergedItems[id];

      // If local item is strictly newer than the remote tombstone,
      // the tombstone is obsolete (the item was revived) and must not be added.
      if (localItem != null && localItem.timestamp.isAfter(remoteTs)) {
        return;
      }

      if (localTs == null || remoteTs.isAfter(localTs)) {
        mergedTombstones[id] = remoteTs;
        // If remote tombstone is newer than our item, delete our item
        if (localItem != null && remoteTs.isAfter(localItem.timestamp)) {
          mergedItems.remove(id);
        }
      }
    });

    // Merge items
    remote.items.forEach((id, remoteReg) {
      final localTombstone = mergedTombstones[id];
      // Only merge if the item is newer than the local tombstone
      if (localTombstone == null ||
          remoteReg.timestamp.isAfter(localTombstone)) {
        final localReg = mergedItems[id];
        if (localReg == null ||
            remoteReg.timestamp.isAfter(localReg.timestamp)) {
          mergedItems[id] = remoteReg;
          mergedTombstones.remove(id);
        }
      }
    });

    return CrdtOrSet(
      items: Map.unmodifiable(mergedItems),
      tombstones: Map.unmodifiable(mergedTombstones),
    );
  }

  /// Garbage-collects tombstones with timestamps older than [threshold] HLC.
  CrdtOrSet<T> pruneTombstones(HybridLogicalClock threshold) {
    final prunedTombstones = Map<String, HybridLogicalClock>.from(tombstones)
      ..removeWhere((_, ts) => ts.isBefore(threshold));

    return CrdtOrSet(
      items: Map.unmodifiable(items),
      tombstones: Map.unmodifiable(prunedTombstones),
    );
  }

  /// Alias for [pruneTombstones] conforming to DATA_SAFETY_AND_CRDT.md directives.
  CrdtOrSet<T> prune(HybridLogicalClock threshold) =>
      pruneTombstones(threshold);

  /// Encodes this [CrdtOrSet] into a JSON-encodable map representation.
  Map<String, dynamic> toMap(dynamic Function(T item) valueEncoder) {
    final itemsMap = <String, dynamic>{};
    items.forEach((key, reg) {
      itemsMap[key] = {
        'v': valueEncoder(reg.value),
        'ts': reg.timestamp.toMap(),
      };
    });

    final tombstonesMap = <String, dynamic>{};
    tombstones.forEach((key, ts) {
      tombstonesMap[key] = ts.toMap();
    });

    return {
      'items': itemsMap,
      'tombstones': tombstonesMap,
    };
  }

  /// Deserializes a [CrdtOrSet] from a map representation with explicit type validation.
  factory CrdtOrSet.fromMap(
    Map<dynamic, dynamic> map,
    T Function(dynamic raw) valueDecoder,
  ) {
    final newItems = <String, CrdtLwwRegister<T>>{};
    final newTombstones = <String, HybridLogicalClock>{};

    final rawItems = map['items'];
    if (rawItems is Map) {
      rawItems.forEach((key, val) {
        if (val is Map && val['ts'] is Map && val['v'] != null) {
          final ts = HybridLogicalClock.fromMap(val['ts'] as Map);
          final decodedVal = valueDecoder(val['v']);
          newItems[key.toString()] =
              CrdtLwwRegister<T>(value: decodedVal, timestamp: ts);
        }
      });
    }

    final rawTombstones = map['tombstones'];
    if (rawTombstones is Map) {
      rawTombstones.forEach((key, val) {
        if (val is Map) {
          newTombstones[key.toString()] = HybridLogicalClock.fromMap(val);
        }
      });
    }

    return CrdtOrSet<T>(
      items: newItems,
      tombstones: newTombstones,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrdtOrSet<T> &&
          runtimeType == other.runtimeType &&
          _mapsEqual(items, other.items) &&
          _mapsEqual(tombstones, other.tombstones);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(
          items.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAllUnordered(
          tombstones.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'CrdtOrSet(items: ${items.length}, tombstones: ${tombstones.length})';
}
