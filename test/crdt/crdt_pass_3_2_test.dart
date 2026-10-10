import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('Cold Iron Birdcage — Pass 3.2: StatefulHlcClock Future Drift & Authority Tests', () {
    const localNow = 1700000000000;
    const maxDrift = Duration(minutes: 1); // 60,000 ms

    test('1. remote within drift bound is accepted and advances causality', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      const remoteTs = HybridLogicalClock(
        physicalTime: localNow + 30000, // 30s ahead, well within 60s
        logicalCounter: 5,
        nodeId: 'peer-node',
      );

      expect(() => clock.observeRemote(remoteTs), returnsNormally);
      expect(clock.latest.physicalTime, equals(localNow + 30000));
      expect(clock.latest.logicalCounter, equals(6));
      expect(clock.latest.nodeId, equals('local-writer'));
    });

    test('2. remote exactly at drift bound is accepted (defined boundary behavior)', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      const boundaryTs = HybridLogicalClock(
        physicalTime: localNow + 60000, // exactly at +60s bound
        logicalCounter: 0,
        nodeId: 'peer-node',
      );

      expect(() => clock.observeRemote(boundaryTs), returnsNormally);
      expect(clock.latest.physicalTime, equals(localNow + 60000));
      expect(clock.latest.logicalCounter, equals(1));
    });

    test('3. remote strictly beyond drift bound throws HlcFutureDriftException with typed fields', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      const excessiveTs = HybridLogicalClock(
        physicalTime: localNow + 60001, // 1ms beyond bound
        logicalCounter: 2,
        nodeId: 'malicious-peer',
      );

      try {
        clock.observeRemote(excessiveTs);
        fail('Expected HlcFutureDriftException');
      } on HlcFutureDriftException catch (e) {
        expect(e.remotePhysicalTime, equals(localNow + 60001));
        expect(e.localPhysicalTime, equals(localNow));
        expect(e.maxFutureDrift, equals(maxDrift));
        expect(e.remoteNodeId, equals('malicious-peer'));
        expect(e.toString(), contains('HlcFutureDriftException'));
      }
    });

    test('4. beyond-bound observation leaves local clock completely unchanged', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      // Generate a legitimate local timestamp first
      final t1 = clock.nextTimestamp();
      final latestBefore = clock.latest;

      const excessiveTs = HybridLogicalClock(
        physicalTime: localNow + 1000000,
        logicalCounter: 0,
        nodeId: 'bad-peer',
      );

      expect(
        () => clock.observeRemote(excessiveTs),
        throwsA(isA<HlcFutureDriftException>()),
      );

      expect(clock.latest, equals(latestBefore));
      expect(clock.latest.physicalTime, equals(t1.physicalTime));
      expect(clock.latest.logicalCounter, equals(t1.logicalCounter));
    });

    test('5. nextTimestamp after rejected observation remains strictly valid and monotonic', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      final t1 = clock.nextTimestamp();

      const excessiveTs = HybridLogicalClock(
        physicalTime: localNow + 9999999,
        logicalCounter: 0,
        nodeId: 'bad-peer',
      );

      expect(
        () => clock.observeRemote(excessiveTs),
        throwsA(isA<HlcFutureDriftException>()),
      );

      final t2 = clock.nextTimestamp();
      expect(t2.isAfter(t1), isTrue);
      expect(t2.nodeId, equals('local-writer'));
      expect(t2.physicalTime, equals(localNow));
      expect(t2.logicalCounter, equals(1));
    });
  });
}
