import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('Cold Iron Birdcage — Pass 3.3: Trusted-History Clock Semantics & Monotonicity', () {
    const localNow = 1700000000000;
    const sixHoursMs = 6 * 60 * 60 * 1000;

    test('observeTrustedHistory accepts far-future persisted timestamp without drift rejection', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('runtime-dm'),
        timeProvider: () => localNow,
      );

      const savedHlc = HybridLogicalClock(
        physicalTime: localNow + sixHoursMs,
        logicalCounter: 42,
        nodeId: 'old-dm-session',
      );

      expect(() => clock.observeTrustedHistory(savedHlc), returnsNormally);
      expect(clock.latest.physicalTime, equals(localNow + sixHoursMs));
      expect(clock.latest.logicalCounter, equals(43));
      expect(clock.latest.nodeId, equals('runtime-dm'));

      final next = clock.nextTimestamp();
      expect(next.isAfter(savedHlc), isTrue);
      expect(next.nodeId, equals('runtime-dm'));
      expect(next.physicalTime, equals(localNow + sixHoursMs));
      expect(next.logicalCounter, equals(44));
    });

    test('observeAllTrustedHistory merges multiple historical timestamps monotonically', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('runtime-writer'),
        timeProvider: () => localNow,
      );

      const hlc1 = HybridLogicalClock(
        physicalTime: localNow + 1000000,
        logicalCounter: 1,
        nodeId: 'node-1',
      );
      const hlc2 = HybridLogicalClock(
        physicalTime: localNow + 2000000,
        logicalCounter: 5,
        nodeId: 'node-2',
      );
      const hlc3 = HybridLogicalClock(
        physicalTime: localNow + 3000000,
        logicalCounter: 10,
        nodeId: 'node-3',
      );

      expect(() => clock.observeAllTrustedHistory([hlc1, hlc2, hlc3]), returnsNormally);
      expect(clock.latest.physicalTime, equals(localNow + 3000000));
      expect(clock.latest.nodeId, equals('runtime-writer'));

      final next = clock.nextTimestamp();
      expect(next.isAfter(hlc1), isTrue);
      expect(next.isAfter(hlc2), isTrue);
      expect(next.isAfter(hlc3), isTrue);
      expect(next.nodeId, equals('runtime-writer'));
    });

    test('observeRemote still strictly rejects far-future timestamps exceeding maxFutureDrift', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('runtime-writer'),
        timeProvider: () => localNow,
      );
      final initial = clock.latest;

      const remoteFarFuture = HybridLogicalClock(
        physicalTime: localNow + sixHoursMs,
        logicalCounter: 0,
        nodeId: 'remote-bad-actor',
      );

      expect(
        () => clock.observeRemote(remoteFarFuture),
        throwsA(isA<HlcFutureDriftException>()),
      );
      expect(clock.latest, equals(initial));
    });
  });
}
