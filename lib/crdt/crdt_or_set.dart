import 'package:meta/meta.dart';
import 'crdt_equality.dart';
import 'crdt_lww_register.dart';
import 'hybrid_logical_clock.dart';

/// Observed-Remove Set (OR-Set) with explicit Tombstone tracking.
/// Provides deterministic reconciliation for collections (e.g., active conditions,
/// minion rosters) and prevents resurrection of deleted items across distributed nodes.
///
/// Implements explicit ADD-WINS semantics when item and tombstone timestamps are identical:
/// - item timestamp > tombstone -> item wins
/// - item timestamp < tombstone -> tombstone wins
/// - item timestamp == tombstone -> ITEM WINS
///
/// Concurrent items with identical timestamp and divergent payload values fail loudly and
/// symmetrically with a [StateError].
@immutable
class CrdtOrSet<T> {
  /// Maps item ID to the Register containing the item and its insertion timestamp.
  final Map<String, CrdtLwwRegister<T>> items;

  /// Maps item ID to the HLC timestamp of when it was removed.
  final Map<String, HybridLogicalClock> tombstones;

  CrdtOrSet({
    Map<String, CrdtLwwRegister<T>> items = const {},
    Map<String, HybridLogicalClock> tombstones = const {},
  })  : items = items.isEmpty && tombstones.isEmpty
            ? const {}
            : Map.unmodifiable(_canonicalize(items, tombstones).items),
        tombstones = items.isEmpty && tombstones.isEmpty
            ? const {}
            : Map.unmodifiable(_canonicalize(items, tombstones).tombstones);

  const CrdtOrSet.empty()
      : items = const {},
        tombstones = const {};

  /// Canonicalizes contradictory state where an ID exists in both items and tombstones
  /// under explicit ADD-WINS semantics.
  static ({
    Map<String, CrdtLwwRegister<T>> items,
    Map<String, HybridLogicalClock> tombstones
  }) _canonicalize<T>(
    Map<String, CrdtLwwRegister<T>> rawItems,
    Map<String, HybridLogicalClock> rawTombstones,
  ) {
    final cleanItems = Map<String, CrdtLwwRegister<T>>.from(rawItems);
    final cleanTombstones = Map<String, HybridLogicalClock>.from(rawTombstones);

    for (final id in rawItems.keys) {
      final tombTs = cleanTombstones[id];
      if (tombTs != null) {
        final itemReg = cleanItems[id]!;
        if (!tombTs.isAfter(itemReg.timestamp)) {
          // item timestamp >= tombstone -> ADD WINS
          cleanTombstones.remove(id);
        } else {
          // tombstone > item timestamp -> TOMBSTONE WINS
          cleanItems.remove(id);
        }
      }
    }

    return (items: cleanItems, tombstones: cleanTombstones);
  }

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
  /// Follows explicit ADD-WINS semantics against existing tombstones.
  CrdtOrSet<T> add(String id, T item, HybridLogicalClock timestamp) {
    return addBatch([(id: id, item: item, timestamp: timestamp)]);
  }

  /// Adds or updates multiple items in a single batch operation to avoid O(N^2) map copies.
  /// Follows explicit ADD-WINS semantics:
  /// - If item timestamp >= existing tombstone timestamp: addition wins and clears tombstone.
  /// - If item timestamp < existing tombstone timestamp: addition is defeated by tombstone.
  /// - If identical timestamp already exists in items with divergent value: fails loudly.
  /// - Stale additions older than the existing item timestamp do not overwrite newer items.
  CrdtOrSet<T> addBatch(
      Iterable<({String id, T item, HybridLogicalClock timestamp})> entries) {
    if (entries.isEmpty) return this;
    final newItems = Map<String, CrdtLwwRegister<T>>.from(items);
    final newTombstones = Map<String, HybridLogicalClock>.from(tombstones);

    for (final entry in entries) {
      final id = entry.id;
      final ts = entry.timestamp;
      final tombstone = newTombstones[id];

      // Add-wins: tombstone defeats item ONLY if tombstone is strictly newer.
      // If ts >= tombstone, item wins.
      if (tombstone != null && tombstone.isAfter(ts)) {
        continue;
      }

      final existingItem = newItems[id];
      if (existingItem != null && existingItem.timestamp == ts) {
        if (!crdtPayloadEquals(existingItem.value, entry.item)) {
          throw StateError(
            'CRDT Collision: CrdtOrSet detected identical timestamp $ts with '
            'divergent item values for ID "$id": "${existingItem.value}" vs "${entry.item}".',
          );
        }
        // Same timestamp, same value: idempotent
        newTombstones.remove(id);
      } else if (existingItem == null || ts.isAfter(existingItem.timestamp)) {
        newItems[id] = CrdtLwwRegister(value: entry.item, timestamp: ts);
        newTombstones.remove(id);
      }
    }

    return CrdtOrSet(
      items: newItems,
      tombstones: newTombstones,
    );
  }

  /// Removes an item with the given [id] at [timestamp], recording a tombstone.
  /// Follows explicit ADD-WINS semantics:
  /// - If an active item has timestamp >= removal timestamp, removal is defeated (item wins).
  /// - If removal timestamp > active item timestamp, item is removed and tombstone is recorded.
  /// - Never leaves both an active item and an equal/newer tombstone in a contradictory state.
  CrdtOrSet<T> remove(String id, HybridLogicalClock timestamp) {
    final currentItem = items[id];
    if (currentItem != null) {
      if (!timestamp.isAfter(currentItem.timestamp)) {
        // Item was added at an equal or newer timestamp; Add-Wins keeps the item.
        return this;
      }
    }

    final existingTombstone = tombstones[id];
    if (existingTombstone != null && !timestamp.isAfter(existingTombstone)) {
      if (currentItem == null) {
        return this;
      }
    }

    final newItems = Map<String, CrdtLwwRegister<T>>.from(items)..remove(id);
    final newTombstones = Map<String, HybridLogicalClock>.from(tombstones);
    if (existingTombstone == null || timestamp.isAfter(existingTombstone)) {
      newTombstones[id] = timestamp;
    }

    return CrdtOrSet(
      items: newItems,
      tombstones: newTombstones,
    );
  }

  /// Merges this OR-Set with [remote] deterministically as a CvRDT lattice join.
  /// Implements explicit ADD-WINS for exact timestamps and fails loudly and
  /// symmetrically on identical timestamp collisions with divergent item payloads.
  CrdtOrSet<T> merge(CrdtOrSet<T> remote) {
    if (identical(this, remote)) return this;

    final allIds = <String>{
      ...items.keys,
      ...tombstones.keys,
      ...remote.items.keys,
      ...remote.tombstones.keys,
    };

    final mergedItems = <String, CrdtLwwRegister<T>>{};
    final mergedTombstones = <String, HybridLogicalClock>{};

    for (final id in allIds) {
      final localItem = items[id];
      final remoteItem = remote.items[id];
      final localTomb = tombstones[id];
      final remoteTomb = remote.tombstones[id];

      // 1. Resolve best candidate item for this ID
      CrdtLwwRegister<T>? candidateItem;
      if (localItem != null && remoteItem != null) {
        if (localItem.timestamp == remoteItem.timestamp) {
          if (!crdtPayloadEquals(localItem.value, remoteItem.value)) {
            throw StateError(
              'CRDT Collision: CrdtOrSet merge detected identical timestamp '
              '${localItem.timestamp} with divergent item values for ID "$id": '
              '"${localItem.value}" vs "${remoteItem.value}".',
            );
          }
          candidateItem = localItem;
        } else if (localItem.timestamp.isAfter(remoteItem.timestamp)) {
          candidateItem = localItem;
        } else {
          candidateItem = remoteItem;
        }
      } else {
        candidateItem = localItem ?? remoteItem;
      }

      // 2. Resolve best candidate tombstone for this ID
      HybridLogicalClock? candidateTomb;
      if (localTomb != null && remoteTomb != null) {
        candidateTomb =
            localTomb.isAfter(remoteTomb) ? localTomb : remoteTomb;
      } else {
        candidateTomb = localTomb ?? remoteTomb;
      }

      // 3. Reconcile item vs tombstone under ADD-WINS:
      // item timestamp > tombstone -> item wins
      // item timestamp < tombstone -> tombstone wins
      // item timestamp == tombstone -> item wins
      if (candidateItem != null && candidateTomb != null) {
        if (!candidateTomb.isAfter(candidateItem.timestamp)) {
          // candidateItem.timestamp >= candidateTomb -> ADD WINS!
          mergedItems[id] = candidateItem;
        } else {
          // candidateTomb is strictly newer -> TOMBSTONE WINS!
          mergedTombstones[id] = candidateTomb;
        }
      } else if (candidateItem != null) {
        mergedItems[id] = candidateItem;
      } else if (candidateTomb != null) {
        mergedTombstones[id] = candidateTomb;
      }
    }

    return CrdtOrSet(
      items: mergedItems,
      tombstones: mergedTombstones,
    );
  }

  /// Garbage-collects tombstones with timestamps older than [threshold] HLC.
  CrdtOrSet<T> pruneTombstones(HybridLogicalClock threshold) {
    final prunedTombstones = Map<String, HybridLogicalClock>.from(tombstones)
      ..removeWhere((_, ts) => ts.isBefore(threshold));

    return CrdtOrSet(
      items: items,
      tombstones: prunedTombstones,
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

  /// Deserializes a [CrdtOrSet] from a map representation with strict structural validation.
  /// Throws [FormatException] if present fields or entries are structurally malformed.
  /// Null payload values are supported when [T] is nullable, validated via key presence ('v').
  factory CrdtOrSet.fromMap(
    Map<dynamic, dynamic> map,
    T Function(dynamic raw) valueDecoder,
  ) {
    final newItems = <String, CrdtLwwRegister<T>>{};
    final newTombstones = <String, HybridLogicalClock>{};

    if (map.containsKey('items')) {
      final rawItems = map['items'];
      if (rawItems is! Map) {
        throw const FormatException('CrdtOrSet.fromMap: "items" field must be a Map.');
      }
      rawItems.forEach((key, val) {
        if (val is! Map) {
          throw FormatException('CrdtOrSet.fromMap: item "$key" must be a Map.');
        }
        if (!val.containsKey('v')) {
          throw FormatException('CrdtOrSet.fromMap: item "$key" missing "v" field.');
        }
        if (!val.containsKey('ts')) {
          throw FormatException('CrdtOrSet.fromMap: item "$key" missing "ts" field.');
        }
        final rawTs = val['ts'];
        if (rawTs is! Map) {
          throw FormatException('CrdtOrSet.fromMap: item "$key" "ts" field must be a Map.');
        }
        final ts = HybridLogicalClock.fromMap(rawTs);
        final decodedVal = valueDecoder(val['v']);
        newItems[key.toString()] =
            CrdtLwwRegister<T>(value: decodedVal, timestamp: ts);
      });
    }

    if (map.containsKey('tombstones')) {
      final rawTombstones = map['tombstones'];
      if (rawTombstones is! Map) {
        throw const FormatException('CrdtOrSet.fromMap: "tombstones" field must be a Map.');
      }
      rawTombstones.forEach((key, val) {
        if (val is! Map) {
          throw FormatException('CrdtOrSet.fromMap: tombstone "$key" must be a Map.');
        }
        newTombstones[key.toString()] = HybridLogicalClock.fromMap(val);
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
