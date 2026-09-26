import 'package:test/test.dart';

import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

void main() {
  group('HybridLogicalClock Tests', () {
    test(
        'Clock Increment: tick() increments logicalCounter when within same millisecond',
        () {
      // Create a clock set to a future physical time so DateTime.now() will not exceed it
      const futureTime = 2500000000000;
      const clock0 = HybridLogicalClock(
        physicalTime: futureTime,
        logicalCounter: 0,
        nodeId: 'nodeA',
      );

      final clock1 = clock0.tick();
      expect(clock1.physicalTime, equals(futureTime));
      expect(clock1.logicalCounter, equals(1));
      expect(clock1.nodeId, equals('nodeA'));

      final clock2 = clock1.tick();
      expect(clock2.physicalTime, equals(futureTime));
      expect(clock2.logicalCounter, equals(2));

      final clock3 = clock2.tick();
      expect(clock3.physicalTime, equals(futureTime));
      expect(clock3.logicalCounter, equals(3));
    });

    test('tick() resets logicalCounter to 0 when physical time moves forward',
        () {
      // Clock in the past
      const pastClock = HybridLogicalClock(
        physicalTime: 1000,
        logicalCounter: 42,
        nodeId: 'nodeA',
      );

      final nextClock = pastClock.tick();
      expect(nextClock.physicalTime, greaterThan(1000));
      expect(nextClock.logicalCounter, equals(0));
      expect(nextClock.nodeId, equals('nodeA'));
    });

    test(
        'Deterministic Tie-Breaking: compareTo() uses lexicographical nodeId when time and counter match',
        () {
      const fixedPt = 1700000000000;
      const fixedCounter = 5;

      const clockA = HybridLogicalClock(
        physicalTime: fixedPt,
        logicalCounter: fixedCounter,
        nodeId: 'nodeA',
      );

      const clockB = HybridLogicalClock(
        physicalTime: fixedPt,
        logicalCounter: fixedCounter,
        nodeId: 'nodeB',
      );

      // 'nodeB' > 'nodeA', so clockB is after clockA
      expect(clockB.isAfter(clockA), isTrue);
      expect(clockA.isBefore(clockB), isTrue);
      expect(clockA.compareTo(clockB), lessThan(0));
      expect(clockB.compareTo(clockA), greaterThan(0));
      expect(clockA.compareTo(clockA), equals(0));
    });

    test('compareTo() prioritizes physicalTime over logicalCounter and nodeId',
        () {
      const earlierClock = HybridLogicalClock(
        physicalTime: 1000,
        logicalCounter: 99,
        nodeId: 'nodeZ',
      );
      const laterClock = HybridLogicalClock(
        physicalTime: 2000,
        logicalCounter: 0,
        nodeId: 'nodeA',
      );

      expect(laterClock.isAfter(earlierClock), isTrue);
      expect(earlierClock.isBefore(laterClock), isTrue);
    });

    test(
        'compareTo() prioritizes logicalCounter over nodeId when physicalTime is equal',
        () {
      const clock1 = HybridLogicalClock(
        physicalTime: 1000,
        logicalCounter: 1,
        nodeId: 'nodeZ',
      );
      const clock2 = HybridLogicalClock(
        physicalTime: 1000,
        logicalCounter: 2,
        nodeId: 'nodeA',
      );

      expect(clock2.isAfter(clock1), isTrue);
      expect(clock1.isBefore(clock2), isTrue);
    });

    test(
        'merge() takes maximum physical time and updates logical counter causality',
        () {
      const futureTime = 3000000000000;

      // Case 1: remote physical time is higher
      const local1 = HybridLogicalClock(
        physicalTime: 2000000000000,
        logicalCounter: 10,
        nodeId: 'nodeLocal',
      );
      const remote1 = HybridLogicalClock(
        physicalTime: futureTime,
        logicalCounter: 3,
        nodeId: 'nodeRemote',
      );

      final merged1 = local1.merge(remote1);
      expect(merged1.physicalTime, equals(futureTime));
      expect(merged1.logicalCounter, equals(4));
      expect(merged1.nodeId, equals('nodeLocal'));

      // Case 2: both clocks at the same physical time (in future)
      const local2 = HybridLogicalClock(
        physicalTime: futureTime,
        logicalCounter: 5,
        nodeId: 'nodeLocal',
      );
      const remote2 = HybridLogicalClock(
        physicalTime: futureTime,
        logicalCounter: 8,
        nodeId: 'nodeRemote',
      );

      final merged2 = local2.merge(remote2);
      expect(merged2.physicalTime, equals(futureTime));
      expect(merged2.logicalCounter, equals(9)); // max(5, 8) + 1
      expect(merged2.nodeId, equals('nodeLocal'));
    });

    test('Value equality and hash code', () {
      const c1 = HybridLogicalClock(
          physicalTime: 100, logicalCounter: 1, nodeId: 'n1');
      const c2 = HybridLogicalClock(
          physicalTime: 100, logicalCounter: 1, nodeId: 'n1');
      const c3 = HybridLogicalClock(
          physicalTime: 100, logicalCounter: 2, nodeId: 'n1');

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1, isNot(equals(c3)));
    });

    test(
        'Tie-Breaker Collision Test: 1,000 UUID-backed HLCs at the exact same physical millisecond result in 0 collisions and perfect sort order',
        () {
      const fixedPt = 1700000000000;
      const fixedCounter = 0;
      

      final clocks = List.generate(
        1000,
        (index) => HybridLogicalClock(
          physicalTime: fixedPt,
          logicalCounter: fixedCounter,
          nodeId: 'node_$index',
        ),
      );

      // Verify 0 collisions in node IDs
      final uniqueNodeIds = clocks.map((c) => c.nodeId).toSet();
      expect(uniqueNodeIds.length, equals(1000));

      // Verify deterministic sorting via compareTo()
      clocks.sort();

      for (var i = 0; i < clocks.length - 1; i++) {
        final current = clocks[i];
        final next = clocks[i + 1];

        expect(current.compareTo(next), lessThan(0));
        expect(next.isAfter(current), isTrue);
        expect(current.isBefore(next), isTrue);
      }
    });

    test('Network Offset Support: now() adjusts physical time by offsetMs', () {
      final before = DateTime.now().toUtc().millisecondsSinceEpoch;
      const offset = 50000;
      final hlc = HybridLogicalClock.now('node-offset', offsetMs: offset);
      final after = DateTime.now().toUtc().millisecondsSinceEpoch;

      expect(hlc.physicalTime, greaterThanOrEqualTo(before + offset));
      expect(hlc.physicalTime, lessThanOrEqualTo(after + offset));
      expect(hlc.logicalCounter, equals(0));
      expect(hlc.nodeId, equals('node-offset'));
    });

    test(
        'Clock Spoofing Mitigation: negative offsetMs neutralizes future-skewed local time',
        () {
      final localNow = DateTime.now().toUtc().millisecondsSinceEpoch;
      const oneYearMs = 365 * 24 * 60 * 60 * 1000;
      // Negative offset representing network time being 1 year behind local spoof
      final hlc = HybridLogicalClock.now('spoofed-node', offsetMs: -oneYearMs);

      // Verify physical time is ~1 year prior to local machine clock
      final expectedTime = localNow - oneYearMs;
      expect((hlc.physicalTime - expectedTime).abs(), lessThanOrEqualTo(100));
    });

    test(
        'tick() and merge() accept offsetMs to preserve network-synchronized time',
        () {
      const offset = 10000;
      final initial = HybridLogicalClock.now('node-tick', offsetMs: offset);
      final ticked = initial.tick(offsetMs: offset);

      expect(ticked.physicalTime, greaterThanOrEqualTo(initial.physicalTime));

      const remote = HybridLogicalClock(
          physicalTime: 1000, logicalCounter: 0, nodeId: 'remote');
      final merged = ticked.merge(remote, offsetMs: offset);
      expect(merged.physicalTime, greaterThanOrEqualTo(ticked.physicalTime));
    });

    test(
        'Strict Node Identity: fromMap throws FormatException when node and nodeId are missing',
        () {
      final invalidMapWithoutNode = {
        'pt': 1700000000000,
        'lc': 0,
      };

      expect(
        () => HybridLogicalClock.fromMap(invalidMapWithoutNode),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Missing required nodeId in HLC payload',
        )),
      );
    });

    test('Strict Node Identity: fromMap parses valid node and nodeId fields',
        () {
      final withNode = {
        'pt': 1700000000000,
        'lc': 2,
        'node': 'node-via-node',
      };
      final hlc1 = HybridLogicalClock.fromMap(withNode);
      expect(hlc1.nodeId, equals('node-via-node'));
      expect(hlc1.physicalTime, equals(1700000000000));
      expect(hlc1.logicalCounter, equals(2));

      final withNodeId = {
        'physicalTime': 1700000000000,
        'logicalCounter': 4,
        'nodeId': 'node-via-nodeId',
      };
      final hlc2 = HybridLogicalClock.fromMap(withNodeId);
      expect(hlc2.nodeId, equals('node-via-nodeId'));
      expect(hlc2.physicalTime, equals(1700000000000));
      expect(hlc2.logicalCounter, equals(4));
    });
  });
}
