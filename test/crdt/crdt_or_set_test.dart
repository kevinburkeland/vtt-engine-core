import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

void main() {
  group('CrdtOrSet Tests', () {
    test('Basic add and activeValues', () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const set0 = CrdtOrSet<String>.empty();
      final set1 = set0.add('item-1', 'Goblin 1', t1);

      expect(set0.activeValues, isEmpty);
      expect(set1.activeValues, equals(['Goblin 1']));
    });

    test('remove() removes item and creates a tombstone', () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');

      final set1 =
          const CrdtOrSet<String>.empty().add('item-1', 'Goblin 1', t1);
      final set2 = set1.remove('item-1', t2);

      expect(set2.activeValues, isEmpty);
      expect(set2.tombstones.containsKey('item-1'), isTrue);
      expect(set2.tombstones['item-1'], equals(t2));
    });

    test(
        'remove() is ignored if removal timestamp is older than item timestamp',
        () {
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');

      final set1 =
          const CrdtOrSet<String>.empty().add('item-1', 'Goblin 1', t2);
      final set2 = set1.remove('item-1', t1);

      expect(set2.activeValues, equals(['Goblin 1']));
      expect(set2.tombstones.containsKey('item-1'), isFalse);
    });

    test(
        'OR-Set Resurrection Prevention: Tombstone prevents older item from returning upon merge',
        () {
      // Client A and B both start with item-1 added at T1
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeShared');
      var clientA = const CrdtOrSet<String>.empty()
          .add('minion-1', 'Skeleton Archer', t1);
      final clientB = const CrdtOrSet<String>.empty()
          .add('minion-1', 'Skeleton Archer', t1);

      // Client A goes online and removes minion-1 at T2
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      clientA = clientA.remove('minion-1', t2);
      expect(clientA.activeValues, isEmpty);

      // Client B was offline, still holding minion-1 at T1
      expect(clientB.activeValues, equals(['Skeleton Archer']));

      // Now Client A merges Client B's state:
      // Client B has minion-1 with ts=T1. Client A has tombstone for minion-1 at ts=T2 (T2 > T1).
      // The tombstone must prevent minion-1 from resurrecting.
      final mergedIntoA = clientA.merge(clientB);
      expect(mergedIntoA.activeValues, isEmpty);
      expect(mergedIntoA.tombstones['minion-1'], equals(t2));

      // Similarly, when Client B receives Client A's state:
      // Client A's tombstone at T2 must overwrite Client B's item at T1.
      final mergedIntoB = clientB.merge(clientA);
      expect(mergedIntoB.activeValues, isEmpty);
      expect(mergedIntoB.tombstones['minion-1'], equals(t2));
    });

    test(
        'Re-adding an item after deletion succeeds if timestamp is newer than tombstone',
        () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      const t3 = HybridLogicalClock(
          physicalTime: 3000, logicalCounter: 0, nodeId: 'nodeA');

      final set1 =
          const CrdtOrSet<String>.empty().add('minion-1', 'Zombie', t1);
      final set2 = set1.remove('minion-1', t2);
      expect(set2.activeValues, isEmpty);
      expect(set2.tombstones.containsKey('minion-1'), isTrue);

      final set3 = set2.add('minion-1', 'Zombie (Revived)', t3);
      expect(set3.activeValues, equals(['Zombie (Revived)']));
      expect(set3.tombstones.containsKey('minion-1'), isFalse);
    });

    test('add() is rejected if item timestamp is older than existing tombstone',
        () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');

      // Set has tombstone at t2
      final setWithTombstone = CrdtOrSet<String>(tombstones: {'item-1': t2});
      // Attempt to add with t1 < t2
      final resultSet = setWithTombstone.add('item-1', 'Old Zombie', t1);

      expect(resultSet.activeValues, isEmpty);
      expect(resultSet.tombstones['item-1'], equals(t2));
    });

    test(
        'Tombstone Pruning: pruneTombstones() and prune() delete tombstones older than threshold',
        () {
      const oldTs1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const oldTs2 = HybridLogicalClock(
          physicalTime: 1500, logicalCounter: 2, nodeId: 'nodeB');
      const newTs1 = HybridLogicalClock(
          physicalTime: 3000, logicalCounter: 0, nodeId: 'nodeA');
      const newTs2 = HybridLogicalClock(
          physicalTime: 4000, logicalCounter: 1, nodeId: 'nodeC');

      const threshold = HybridLogicalClock(
          physicalTime: 2500, logicalCounter: 0, nodeId: 'nodeA');

      final setWithTombstones = CrdtOrSet<String>(
        tombstones: {
          'tomb-1': oldTs1,
          'tomb-2': oldTs2,
          'tomb-3': newTs1,
          'tomb-4': newTs2,
        },
      );

      final pruned1 = setWithTombstones.pruneTombstones(threshold);
      expect(pruned1.tombstones.containsKey('tomb-1'), isFalse);
      expect(pruned1.tombstones.containsKey('tomb-2'), isFalse);
      expect(pruned1.tombstones['tomb-3'], equals(newTs1));
      expect(pruned1.tombstones['tomb-4'], equals(newTs2));

      // Test alias prune()
      final pruned2 = setWithTombstones.prune(threshold);
      expect(pruned2.tombstones.keys, containsAll(['tomb-3', 'tomb-4']));
      expect(pruned2.tombstones.containsKey('tomb-1'), isFalse);
      expect(pruned2.tombstones.containsKey('tomb-2'), isFalse);
    });

    test('merge() combines distinct items from multiple nodes', () {
      const tA = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const tB = HybridLogicalClock(
          physicalTime: 1200, logicalCounter: 0, nodeId: 'nodeB');

      final setA = const CrdtOrSet<String>.empty().add('item-A', 'Fighter', tA);
      final setB = const CrdtOrSet<String>.empty().add('item-B', 'Wizard', tB);

      final merged = setA.merge(setB);
      expect(merged.activeValues, containsAll(['Fighter', 'Wizard']));
      expect(merged.items.length, equals(2));
    });

    test(
        'remove() on non-existent item unconditionally records tombstone preventing out-of-order add',
        () {
      const tRemove = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      const tAddEarlier = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeB');

      // Empty set receives a removal for 'ghost-item'
      const emptySet = CrdtOrSet<String>.empty();
      expect(emptySet.items.containsKey('ghost-item'), isFalse);

      final setWithTombstone = emptySet.remove('ghost-item', tRemove);
      expect(setWithTombstone.activeValues, isEmpty);
      expect(setWithTombstone.tombstones['ghost-item'], equals(tRemove));

      // An out-of-order addition created earlier arrives later
      final rejectedAddSet =
          setWithTombstone.add('ghost-item', 'Ghost Monster', tAddEarlier);
      expect(rejectedAddSet.activeValues, isEmpty);
      expect(rejectedAddSet.tombstones['ghost-item'], equals(tRemove));
    });

    test(
        'addBatch() atomically adds multiple items while respecting tombstones',
        () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      const t2 = HybridLogicalClock(
          physicalTime: 2000, logicalCounter: 0, nodeId: 'nodeA');
      const t3 = HybridLogicalClock(
          physicalTime: 3000, logicalCounter: 0, nodeId: 'nodeA');

      final initial = CrdtOrSet<String>(
        tombstones: {'deleted-item': t2},
      );

      final batch = [
        (id: 'item-1', item: 'Fighter', timestamp: t1),
        (id: 'item-2', item: 'Wizard', timestamp: t3),
        (
          id: 'deleted-item',
          item: 'Ghost',
          timestamp: t1
        ), // Rejected (t1 < t2)
        (id: 'revived-item', item: 'Lich', timestamp: t3),
      ];

      final result = initial.addBatch(batch);

      expect(result.activeValues, containsAll(['Fighter', 'Wizard', 'Lich']));
      expect(result.activeValues.contains('Ghost'), isFalse);
      expect(result.tombstones.containsKey('deleted-item'), isTrue);
      expect(result.items.length, equals(3));
    });

    test(
        'CRDT Immutability: items and tombstones are sealed as unmodifiable maps',
        () {
      const t1 = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'nodeA');
      final set = const CrdtOrSet<String>.empty().add('item-1', 'Paladin', t1);

      // Attempting to mutate items must throw UnsupportedError
      expect(
        () => (set.items as dynamic)['item-2'] =
            const CrdtLwwRegister<String>(value: 'Fighter', timestamp: t1),
        throwsUnsupportedError,
      );

      // Attempting to mutate tombstones must throw UnsupportedError
      final setWithTombstone = set.remove('item-1', t1);
      expect(() => (setWithTombstone.tombstones as dynamic)['tomb-1'] = t1,
          throwsUnsupportedError);

      // Passing mutable map to constructor must wrap into unmodifiable map
      final mutableMap = <String, HybridLogicalClock>{'tomb': t1};
      final customSet = CrdtOrSet<String>(tombstones: mutableMap);
      expect(() => (customSet.tombstones as dynamic)['tomb2'] = t1,
          throwsUnsupportedError);
    });

    group('CrdtOrSet.fromMap Tests', () {
      test(
          'Deserializes valid items and tombstones with explicit type validation',
          () {
        final map = {
          'items': {
            'i1': {
              'v': 'Ranger',
              'ts': {'pt': 1000, 'lc': 0, 'node': 'nodeA'},
            },
          },
          'tombstones': {
            't1': {'pt': 2000, 'lc': 1, 'node': 'nodeB'},
          },
        };

        final orSet = CrdtOrSet<String>.fromMap(map, (raw) => raw.toString());
        expect(orSet.activeValues, equals(['Ranger']));
        expect(orSet.tombstones.containsKey('t1'), isTrue);
        expect(orSet.tombstones['t1']!.nodeId, equals('nodeB'));
      });

      test(
          'Explicit type validation skips items with missing ts or null value without throwing',
          () {
        final map = {
          'items': {
            'valid': {
              'v': 'Cleric',
              'ts': {'pt': 1000, 'lc': 0, 'node': 'nodeA'},
            },
            'no_ts': {
              'v': 'Bard',
            },
            'null_val': {
              'v': null,
              'ts': {'pt': 1000, 'lc': 0, 'node': 'nodeA'},
            },
            'non_map': 'corrupted_string',
          },
          'tombstones': {
            'non_map_tomb': 'corrupted_string',
          },
        };

        final orSet = CrdtOrSet<String>.fromMap(map, (raw) => raw.toString());
        expect(orSet.activeValues, equals(['Cleric']));
        expect(orSet.items.length, equals(1));
        expect(orSet.tombstones, isEmpty);
      });

      test(
          'Propagates FormatException from HybridLogicalClock.fromMap when nodeId is missing in items',
          () {
        final mapWithMissingNodeInItem = {
          'items': {
            'i1': {
              'v': 'Wizard',
              'ts': {'pt': 1000, 'lc': 0}, // Missing node/nodeId
            },
          },
        };

        expect(
          () => CrdtOrSet<String>.fromMap(
              mapWithMissingNodeInItem, (raw) => raw.toString()),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required nodeId in HLC payload',
          )),
        );
      });

      test(
          'Propagates FormatException from HybridLogicalClock.fromMap when nodeId is missing in tombstones',
          () {
        final mapWithMissingNodeInTombstone = {
          'tombstones': {
            't1': {'pt': 2000, 'lc': 0}, // Missing node/nodeId
          },
        };

        expect(
          () => CrdtOrSet<String>.fromMap(
              mapWithMissingNodeInTombstone, (raw) => raw.toString()),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Missing required nodeId in HLC payload',
          )),
        );
      });

      test('Propagates exceptions thrown by valueDecoder', () {
        final map = {
          'items': {
            'i1': {
              'v': 'not-an-int',
              'ts': {'pt': 1000, 'lc': 0, 'node': 'nodeA'},
            },
          },
        };

        expect(
          () => CrdtOrSet<int>.fromMap(map, (raw) => int.parse(raw.toString())),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
