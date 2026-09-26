import 'dart:async';
import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';

class Mutex {
  Completer<void>? _completer;

  bool get isLocked => _completer != null;

  Future<T> protect<T>(Future<T> Function() criticalSection) async {
    while (_completer != null) {
      await _completer!.future;
    }
    final c = Completer<void>();
    _completer = c;
    try {
      return await criticalSection();
    } finally {
      _completer = null;
      c.complete();
    }
  }
}

void main() {
  group('CRDT Synchronization Ledger & HLC Test Suite', () {
    group('Phase 1: Hybrid Logical Clock (HLC) Causality & Monotonicity', () {
      test('HLC Monotonicity: local ticks strictly increment causality', () {
        const basePt = 1700000000000;
        const hlc0 = HybridLogicalClock(
          physicalTime: basePt,
          logicalCounter: 0,
          nodeId: 'node-alpha',
        );

        // Same physical time ticks
        final hlc1 = hlc0.tick(timeProvider: () => basePt);
        final hlc2 = hlc1.tick(timeProvider: () => basePt);
        final hlc3 = hlc2.tick(timeProvider: () => basePt);

        expect(hlc1.physicalTime, equals(basePt));
        expect(hlc1.logicalCounter, equals(1));
        expect(hlc2.logicalCounter, equals(2));
        expect(hlc3.logicalCounter, equals(3));

        expect(hlc1.isAfter(hlc0), isTrue);
        expect(hlc2.isAfter(hlc1), isTrue);
        expect(hlc3.isAfter(hlc2), isTrue);

        // Advancing physical time resets logical counter to 0
        final hlc4 = hlc3.tick(timeProvider: () => basePt + 500);
        expect(hlc4.physicalTime, equals(basePt + 500));
        expect(hlc4.logicalCounter, equals(0));
        expect(hlc4.isAfter(hlc3), isTrue);
      });

      test(
          'Causal Message Chain: A -> B -> C preserves strict monotonicity across nodes',
          () {
        // Node A produces event eA
        var clockA = const HybridLogicalClock(
          physicalTime: 1000,
          logicalCounter: 0,
          nodeId: 'node-A',
        );
        final eA = clockA = clockA.tick(timeProvider: () => 1000);

        // Node B has local clock at physical time 950 (behind A). Receives eA and merges.
        var clockB = const HybridLogicalClock(
          physicalTime: 950,
          logicalCounter: 0,
          nodeId: 'node-B',
        );
        clockB = clockB.merge(eA, timeProvider: () => 950);
        final eB = clockB = clockB.tick(timeProvider: () => 950);

        // Node C has local clock at physical time 900. Receives eB and merges.
        var clockC = const HybridLogicalClock(
          physicalTime: 900,
          logicalCounter: 0,
          nodeId: 'node-C',
        );
        clockC = clockC.merge(eB, timeProvider: () => 900);
        final eC = clockC = clockC.tick(timeProvider: () => 900);

        // Causality must hold transitively: eA < eB < eC
        expect(eB.isAfter(eA), isTrue,
            reason: 'Event B must be causally after Event A');
        expect(eC.isAfter(eB), isTrue,
            reason: 'Event C must be causally after Event B');
        expect(eC.isAfter(eA), isTrue,
            reason: 'Event C must be causally after Event A');

        // Physical times must not regress
        expect(eB.physicalTime, greaterThanOrEqualTo(eA.physicalTime));
        expect(eC.physicalTime, greaterThanOrEqualTo(eB.physicalTime));
      });

      test(
          'Clock Skew Resilience: handling incoming remote messages with future or past drift',
          () {
        // Local node at time 2000
        const local = HybridLogicalClock(
          physicalTime: 2000,
          logicalCounter: 5,
          nodeId: 'node-local',
        );

        // Case 1: Remote is far in the future (physical time 5000)
        const remoteFuture = HybridLogicalClock(
          physicalTime: 5000,
          logicalCounter: 2,
          nodeId: 'node-remote-future',
        );
        final mergedFuture =
            local.merge(remoteFuture, timeProvider: () => 2000);
        expect(mergedFuture.physicalTime, equals(5000));
        expect(mergedFuture.logicalCounter, equals(3)); // remoteCounter + 1
        expect(mergedFuture.isAfter(local), isTrue);
        expect(mergedFuture.isAfter(remoteFuture), isTrue);

        // Case 2: Remote is far in the past (physical time 500)
        const remotePast = HybridLogicalClock(
          physicalTime: 500,
          logicalCounter: 99,
          nodeId: 'node-remote-past',
        );
        final mergedPast = local.merge(remotePast, timeProvider: () => 2000);
        expect(mergedPast.physicalTime, equals(2000));
        expect(mergedPast.logicalCounter, equals(6)); // localCounter + 1
        expect(mergedPast.isAfter(local), isTrue);
        expect(mergedPast.isAfter(remotePast), isTrue);

        // Case 3: Both clocks identical in physical and logical
        const remoteIdentical = HybridLogicalClock(
          physicalTime: 2000,
          logicalCounter: 5,
          nodeId: 'node-remote-equal',
        );
        final mergedEqual =
            local.merge(remoteIdentical, timeProvider: () => 2000);
        expect(mergedEqual.physicalTime, equals(2000));
        expect(mergedEqual.logicalCounter, equals(6)); // max(5, 5) + 1
        expect(mergedEqual.isAfter(local), isTrue);
      });

      test(
          'Deterministic Tie-Breaking: strictly resolves identical timestamps using lexicographical nodeId',
          () {
        const pt = 1750000000000;
        const lc = 10;

        final nodes = [
          'node-zebra',
          'node-alpha',
          'node-charlie',
          'node-bravo',
          'node-delta'
        ];
        final clocks = nodes
            .map((id) => HybridLogicalClock(
                physicalTime: pt, logicalCounter: lc, nodeId: id))
            .toList();

        final sorted = List<HybridLogicalClock>.from(clocks)..sort();

        expect(
            sorted.map((c) => c.nodeId).toList(),
            equals([
              'node-alpha',
              'node-bravo',
              'node-charlie',
              'node-delta',
              'node-zebra',
            ]));

        // Direct pairwise checks
        expect(sorted[0].compareTo(sorted[1]), lessThan(0));
        expect(sorted[1].compareTo(sorted[0]), greaterThan(0));
        expect(sorted[0].compareTo(sorted[0]), equals(0));
      });
    });

    group('Phase 1: CrdtOrSet Convergence & Conflict-Free Invariants', () {
      test(
          'Algebraic Properties: Commutativity, Associativity, and Idempotence',
          () {
        const t1 = HybridLogicalClock(
            physicalTime: 1000, logicalCounter: 0, nodeId: 'node-1');
        const t2 = HybridLogicalClock(
            physicalTime: 1050, logicalCounter: 0, nodeId: 'node-2');
        const t3 = HybridLogicalClock(
            physicalTime: 1100, logicalCounter: 0, nodeId: 'node-3');

        final setA = const CrdtOrSet<String>.empty()
            .add('item-1', 'Longsword', t1)
            .add('item-2', 'Shield', t2);

        final setB = const CrdtOrSet<String>.empty()
            .add('item-2', 'Shield +1', t3)
            .add('item-3', 'Potion of Healing', t1);

        final setC = const CrdtOrSet<String>.empty()
            .remove('item-1', t3)
            .add('item-4', 'Ring of Protection', t2);

        // 1. Idempotence: A merge A == A
        final idempotentA = setA.merge(setA);
        expect(idempotentA, equals(setA));
        expect(idempotentA.hashCode, equals(setA.hashCode));

        // 2. Commutativity: A merge B == B merge A
        final mergeAB = setA.merge(setB);
        final mergeBA = setB.merge(setA);
        expect(mergeAB, equals(mergeBA));
        expect(mergeAB.hashCode, equals(mergeBA.hashCode));

        // 3. Associativity: (A merge B) merge C == A merge (B merge C)
        final leftAssoc = (setA.merge(setB)).merge(setC);
        final rightAssoc = setA.merge(setB.merge(setC));
        expect(leftAssoc, equals(rightAssoc));
        expect(leftAssoc.hashCode, equals(rightAssoc.hashCode));
      });

      test(
          'Zero Tombstone Resurrection: older add arriving out-of-order cannot resurrect deleted item',
          () {
        // Sequence: Item is added at tAdd, then removed at tDel (tDel > tAdd)
        const tAdd = HybridLogicalClock(
            physicalTime: 1000, logicalCounter: 0, nodeId: 'node-A');
        const tDel = HybridLogicalClock(
            physicalTime: 2000, logicalCounter: 0, nodeId: 'node-B');

        // Node 1 receives deletion first (e.g. from Node B)
        final node1 = const CrdtOrSet<String>.empty()
            .add('goblin-1', 'Goblin Scout', tAdd)
            .remove('goblin-1', tDel);

        expect(node1.activeValues, isEmpty);
        expect(node1.tombstones.containsKey('goblin-1'), isTrue);

        // Node 2 has the stale addition only
        final node2 = const CrdtOrSet<String>.empty()
            .add('goblin-1', 'Goblin Scout', tAdd);
        expect(node2.activeValues, equals(['Goblin Scout']));

        // Merge stale node2 into node1: tombstone at tDel must suppress addition at tAdd
        final merged1 = node1.merge(node2);
        expect(merged1.activeValues, isEmpty);
        expect(merged1.tombstones['goblin-1'], equals(tDel));

        // Merge node1 into stale node2: tombstone at tDel must delete the active item in node2
        final merged2 = node2.merge(node1);
        expect(merged2.activeValues, isEmpty);
        expect(merged2.tombstones['goblin-1'], equals(tDel));

        // Attempting to directly call add() with an outdated timestamp must also fail
        const tOld = HybridLogicalClock(
            physicalTime: 1500, logicalCounter: 0, nodeId: 'node-C');
        final reAddAttempt = merged1.add('goblin-1', 'Zombie Goblin', tOld);
        expect(reAddAttempt.activeValues, isEmpty);
        expect(reAddAttempt.tombstones['goblin-1'], equals(tDel));
      });

      test(
          'Legitimate Revival: re-adding with timestamp newer than tombstone restores entity',
          () {
        const tAdd = HybridLogicalClock(
            physicalTime: 1000, logicalCounter: 0, nodeId: 'node-A');
        const tDel = HybridLogicalClock(
            physicalTime: 2000, logicalCounter: 0, nodeId: 'node-B');
        const tRevive = HybridLogicalClock(
            physicalTime: 3000, logicalCounter: 0, nodeId: 'node-C');

        final set = const CrdtOrSet<String>.empty()
            .add('skeleton-1', 'Skeleton', tAdd)
            .remove('skeleton-1', tDel);

        expect(set.activeValues, isEmpty);
        expect(set.tombstones.containsKey('skeleton-1'), isTrue);

        // Revive with tRevive > tDel
        final revived =
            set.add('skeleton-1', 'Skeleton (Summoned Again)', tRevive);
        expect(revived.activeValues, equals(['Skeleton (Summoned Again)']));
        expect(revived.tombstones.containsKey('skeleton-1'), isFalse);
        expect(revived.items['skeleton-1']!.timestamp, equals(tRevive));
      });

      test(
          'Out-of-Order Delivery Convergence: random permutations of operations converge to identical state',
          () {
        // Define a set of discrete operations across 3 distributed nodes
        const t1 = HybridLogicalClock(
            physicalTime: 1000, logicalCounter: 0, nodeId: 'node-A');
        const t2 = HybridLogicalClock(
            physicalTime: 1100, logicalCounter: 0, nodeId: 'node-B');
        const t3 = HybridLogicalClock(
            physicalTime: 1200, logicalCounter: 0, nodeId: 'node-C');
        const t4 = HybridLogicalClock(
            physicalTime: 1300, logicalCounter: 0, nodeId: 'node-A');
        const t5 = HybridLogicalClock(
            physicalTime: 1400, logicalCounter: 0, nodeId: 'node-B');
        const t6 = HybridLogicalClock(
            physicalTime: 1500, logicalCounter: 0, nodeId: 'node-C');

        // Operations:
        // Op1: Add 'spell-1' -> 'Fireball' (t1)
        // Op2: Add 'spell-2' -> 'Mage Armor' (t2)
        // Op3: Remove 'spell-1' (t3)
        // Op4: Add 'spell-1' -> 'Delayed Blast Fireball' (t4 - revive!)
        // Op5: Add 'spell-3' -> 'Counterspell' (t5)
        // Op6: Remove 'spell-2' (t6)

        final deltas = <CrdtOrSet<String>>[
          const CrdtOrSet<String>.empty().add('spell-1', 'Fireball', t1),
          const CrdtOrSet<String>.empty().add('spell-2', 'Mage Armor', t2),
          const CrdtOrSet<String>.empty()
              .add('spell-1', 'Fireball', t1)
              .remove('spell-1', t3),
          const CrdtOrSet<String>.empty()
              .add('spell-1', 'Delayed Blast Fireball', t4),
          const CrdtOrSet<String>.empty().add('spell-3', 'Counterspell', t5),
          const CrdtOrSet<String>.empty()
              .add('spell-2', 'Mage Armor', t2)
              .remove('spell-2', t6),
        ];

        // Compute canonical merged state
        var canonical = const CrdtOrSet<String>.empty();
        for (final delta in deltas) {
          canonical = canonical.merge(delta);
        }

        expect(canonical.activeValues,
            containsAll(['Delayed Blast Fireball', 'Counterspell']));
        expect(canonical.items.containsKey('spell-2'), isFalse);
        expect(canonical.tombstones['spell-2'], equals(t6));

        // Test multiple permutations (reverse, interleaved, rotated)
        final permutations = <List<CrdtOrSet<String>>>[
          deltas.reversed.toList(),
          [deltas[2], deltas[0], deltas[5], deltas[1], deltas[4], deltas[3]],
          [deltas[5], deltas[4], deltas[3], deltas[2], deltas[1], deltas[0]],
          [deltas[3], deltas[1], deltas[4], deltas[0], deltas[2], deltas[5]],
        ];

        for (var i = 0; i < permutations.length; i++) {
          var state = const CrdtOrSet<String>.empty();
          for (final delta in permutations[i]) {
            state = state.merge(delta);
          }
          expect(
            state,
            equals(canonical),
            reason:
                'Permutation $i must converge identically to canonical state',
          );
          expect(state.hashCode, equals(canonical.hashCode));
          expect(state.activeValues.toSet(),
              equals(canonical.activeValues.toSet()));
        }
      });
    });

    group(
        'Phase 2: Execution & Pipeline Integration (Async Streams & Mutex Concurrency)',
        () {
      test(
          'Asynchronous Ledger: Mutex protects state updates across concurrent async streams without deadlocks',
          () async {
        final stateMutex = Mutex();
        final inboundStreamController =
            StreamController<CrdtOrSet<String>>.broadcast();
        final localOutboundController =
            StreamController<CrdtOrSet<String>>.broadcast();

        var currentState = const CrdtOrSet<String>.empty();
        final processedDeltas = <CrdtOrSet<String>>[];

        // Inbound subscription handles network payloads under Mutex protection
        final sub =
            inboundStreamController.stream.listen((incomingDelta) async {
          await stateMutex.protect(() async {
            // Simulate minimal async microtask latency (e.g. database save / validation)
            await Future.microtask(() {});
            currentState = currentState.merge(incomingDelta);
            processedDeltas.add(incomingDelta);
          });
        });

        // Simulate 20 concurrent interleaved operations (10 inbound from remote, 10 local changes)
        const nodeLocal = 'node-local';
        const nodeRemote = 'node-remote';

        final futures = <Future<void>>[];

        for (var i = 0; i < 10; i++) {
          final step = i;
          // Concurrent local change
          futures.add(() async {
            await Future.microtask(() {});
            await stateMutex.protect(() async {
              final hlc = HybridLogicalClock(
                physicalTime: 2000 + step * 10,
                logicalCounter: 0,
                nodeId: nodeLocal,
              );
              currentState =
                  currentState.add('local-$step', 'Local Item $step', hlc);
              localOutboundController.add(currentState);
            });
          }());

          // Concurrent inbound change
          futures.add(() async {
            final remoteHlc = HybridLogicalClock(
              physicalTime: 2000 + step * 10 + 5,
              logicalCounter: 0,
              nodeId: nodeRemote,
            );
            final remoteDelta = const CrdtOrSet<String>.empty().add(
              'remote-$step',
              'Remote Item $step',
              remoteHlc,
            );
            inboundStreamController.add(remoteDelta);
          }());
        }

        // Await all dispatches to finish without timing out / deadlocking
        await Future.wait(futures).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
              'Deadlock detected during concurrent mutex operations'),
        );

        // Pump event queue to ensure all async stream listeners execute
        await pumpEventQueue();

        // Mutex must be unlocked
        expect(stateMutex.isLocked, isFalse);

        // Verify state consistency: all 10 local items and 10 remote items must be present
        expect(currentState.items.length, equals(20));
        for (var i = 0; i < 10; i++) {
          expect(currentState.items.containsKey('local-$i'), isTrue);
          expect(currentState.items.containsKey('remote-$i'), isTrue);
        }

        await sub.cancel();
        await inboundStreamController.close();
        await localOutboundController.close();
      });

      test(
          'Re-entrant Inbound Emission: Asynchronous microtask dispatch prevents self-deadlock',
          () async {
        final syncMutex = Mutex();
        final routerController = StreamController<String>.broadcast();
        final executionLog = <String>[];

        // Simulate a router listener that triggers another broadcast upon receiving a message
        final sub = routerController.stream.listen((message) {
          // Asynchronous microtask dispatch prevents synchronous re-entrant deadlock on syncMutex
          scheduleMicrotask(() async {
            await syncMutex.protect(() async {
              executionLog.add('processed-$message');
            });
          });
        });

        // Acquire mutex for an active outbound operation and broadcast to router inside lock
        await syncMutex.protect(() async {
          executionLog.add('start-outbound');
          routerController.add('payload-1');
          executionLog.add('end-outbound');
        });

        // Drain microtasks
        await pumpEventQueue();

        expect(
            executionLog,
            equals([
              'start-outbound',
              'end-outbound',
              'processed-payload-1',
            ]));
        expect(syncMutex.isLocked, isFalse);

        await sub.cancel();
        await routerController.close();
      });
    });
  });
}
