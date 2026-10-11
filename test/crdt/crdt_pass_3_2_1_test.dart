import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('Cold Iron Birdcage — Pass 3.2.1: StatefulHlcClock Validation & Extraction Tests', () {
    const localNow = 1700000000000;
    const maxDrift = Duration(minutes: 1); // 60,000 ms

    test('1. validateRemote within bound returns normally without mutating latest', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );
      final initialLatest = clock.latest;

      const remoteTs = HybridLogicalClock(
        physicalTime: localNow + 30000,
        logicalCounter: 5,
        nodeId: 'peer-node',
      );

      expect(() => clock.validateRemote(remoteTs), returnsNormally);
      expect(clock.latest, equals(initialLatest));
    });

    test('2. validateRemote exactly at bound returns normally without mutating latest', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );
      final initialLatest = clock.latest;

      const boundaryTs = HybridLogicalClock(
        physicalTime: localNow + 60000,
        logicalCounter: 0,
        nodeId: 'peer-node',
      );

      expect(() => clock.validateRemote(boundaryTs), returnsNormally);
      expect(clock.latest, equals(initialLatest));
    });

    test('3. validateRemote beyond bound throws HlcFutureDriftException without mutating latest', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );
      final initialLatest = clock.latest;

      const excessiveTs = HybridLogicalClock(
        physicalTime: localNow + 60001,
        logicalCounter: 2,
        nodeId: 'bad-peer',
      );

      expect(
        () => clock.validateRemote(excessiveTs),
        throwsA(isA<HlcFutureDriftException>()),
      );
      expect(clock.latest, equals(initialLatest));
    });

    test('4. validateRemote followed by observeRemote validates and observes normally', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );

      const remoteTs = HybridLogicalClock(
        physicalTime: localNow + 25000,
        logicalCounter: 3,
        nodeId: 'peer-node',
      );

      expect(() => clock.validateRemote(remoteTs), returnsNormally);
      expect(() => clock.observeRemote(remoteTs), returnsNormally);
      expect(clock.latest.physicalTime, equals(localNow + 25000));
      expect(clock.latest.logicalCounter, equals(4));
      expect(clock.latest.nodeId, equals('local-writer'));
    });

    test('5. validate multiple timestamps externally without mutation until all pass', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );
      final initialLatest = clock.latest;

      final validBatch = [
        const HybridLogicalClock(
          physicalTime: localNow + 10000,
          logicalCounter: 1,
          nodeId: 'peer-1',
        ),
        const HybridLogicalClock(
          physicalTime: localNow + 20000,
          logicalCounter: 2,
          nodeId: 'peer-2',
        ),
      ];

      expect(() => clock.validateAllRemote(validBatch), returnsNormally);
      expect(clock.latest, equals(initialLatest));

      final invalidBatch = [
        const HybridLogicalClock(
          physicalTime: localNow + 10000,
          logicalCounter: 1,
          nodeId: 'peer-1',
        ),
        const HybridLogicalClock(
          physicalTime: localNow + 100000, // exceeds 60s
          logicalCounter: 2,
          nodeId: 'peer-bad',
        ),
      ];

      expect(
        () => clock.validateAllRemote(invalidBatch),
        throwsA(isA<HlcFutureDriftException>()),
      );
      expect(clock.latest, equals(initialLatest));
    });

    test('6. observeAllRemote is atomic: if any fails, none are observed into latest', () {
      final clock = StatefulHlcClock(
        replicaId: ReplicaId('local-writer'),
        timeProvider: () => localNow,
        maxFutureDrift: maxDrift,
      );
      final initialLatest = clock.latest;

      final mixedBatch = [
        const HybridLogicalClock(
          physicalTime: localNow + 20000,
          logicalCounter: 1,
          nodeId: 'peer-1',
        ),
        const HybridLogicalClock(
          physicalTime: localNow + 100000, // exceeds 60s
          logicalCounter: 1,
          nodeId: 'peer-future',
        ),
      ];

      expect(
        () => clock.observeAllRemote(mixedBatch),
        throwsA(isA<HlcFutureDriftException>()),
      );
      expect(clock.latest, equals(initialLatest));
    });

    test('7. extractCampaignProfileTimestamps extracts notes, pinned rules, entity links, minions, encounter and tombstones', () {
      const tsNotes = HybridLogicalClock(
        physicalTime: localNow + 1000,
        logicalCounter: 0,
        nodeId: 'node-notes',
      );
      const tsPinnedItem = HybridLogicalClock(
        physicalTime: localNow + 1500,
        logicalCounter: 0,
        nodeId: 'node-pinned-item',
      );
      const tsPinnedTombstone = HybridLogicalClock(
        physicalTime: localNow + 1600,
        logicalCounter: 0,
        nodeId: 'node-pinned-ts',
      );
      const tsEntityLinkItem = HybridLogicalClock(
        physicalTime: localNow + 1700,
        logicalCounter: 0,
        nodeId: 'node-link-item',
      );
      const tsEntityLinkTombstone = HybridLogicalClock(
        physicalTime: localNow + 1800,
        logicalCounter: 0,
        nodeId: 'node-link-ts',
      );
      const tsMinionItem = HybridLogicalClock(
        physicalTime: localNow + 2000,
        logicalCounter: 0,
        nodeId: 'node-minion-item',
      );
      const tsMinionTombstone = HybridLogicalClock(
        physicalTime: localNow + 3000,
        logicalCounter: 0,
        nodeId: 'node-minion-ts',
      );
      const tsEncounterItem = HybridLogicalClock(
        physicalTime: localNow + 4000,
        logicalCounter: 0,
        nodeId: 'node-enc-item',
      );
      const tsEncounterTombstone = HybridLogicalClock(
        physicalTime: localNow + 5000,
        logicalCounter: 0,
        nodeId: 'node-enc-ts',
      );
      const tsRosterItem = HybridLogicalClock(
        physicalTime: localNow + 6000,
        logicalCounter: 0,
        nodeId: 'node-roster-item',
      );
      const tsRosterTombstone = HybridLogicalClock(
        physicalTime: localNow + 7000,
        logicalCounter: 0,
        nodeId: 'node-roster-ts',
      );

      final rosterSet = CrdtOrSet<String>(
        items: {
          'cleric-1': const CrdtLwwRegister<String>(
            value: 'cleric-1',
            timestamp: tsRosterItem,
          ),
        },
        tombstones: {
          'rogue-1': tsRosterTombstone,
        },
      );

      final pinnedRulesSet = CrdtOrSet<String>(
        items: {
          'rule_1': const CrdtLwwRegister<String>(
            value: 'rule_1',
            timestamp: tsPinnedItem,
          ),
        },
        tombstones: {
          'rule_2': tsPinnedTombstone,
        },
      );

      final entityLinksSet = CrdtOrSet<RoomEntityLink>(
        items: {
          'link_1': CrdtLwwRegister<RoomEntityLink>(
            value: RoomEntityLink(entityId: 'link_1', displayName: 'Hero'),
            timestamp: tsEntityLinkItem,
          ),
        },
        tombstones: {
          'link_2': tsEntityLinkTombstone,
        },
      );

      final minionsSet = CrdtOrSet<dynamic>(
        items: {
          'm1': const CrdtLwwRegister<dynamic>(
            value: {'name': 'Wolf'},
            timestamp: tsMinionItem,
          ),
        },
        tombstones: {
          'm2': tsMinionTombstone,
        },
      );

      final encounterSet = CrdtOrSet<EncounterParticipant>(
        items: {
          'e1': CrdtLwwRegister<EncounterParticipant>(
            value: EncounterParticipant(
              participantId: 'e1',
              entityLink: RoomEntityLink(entityId: 'e1', displayName: 'Goblin'),
            ),
            timestamp: tsEncounterItem,
          ),
        },
        tombstones: {
          'e2': tsEncounterTombstone,
        },
      );

      final roomState = RoomNodeState.fromLegacyCrdtOrSet(
        roomId: 'room_1',
        roomCode: 'RC1',
        title: 'Throne Room',
        entityLinksCrdt: entityLinksSet,
        activeMinions: minionsSet,
        activeEncounter: encounterSet,
      );

      final profile = CampaignProfile.raw(
        id: 'camp_1',
        name: 'Test Campaign',
        createdAt: DateTime.now().toUtc(),
        lastPlayedAt: DateTime.now().toUtc(),
        roomState: roomState,
        pinnedRules: pinnedRulesSet,
        partyRoster: rosterSet,
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Hello',
          timestamp: tsNotes,
        ),
      );

      final extracted = extractCampaignProfileTimestamps(profile);
      final expected = {
        tsNotes,
        tsPinnedItem,
        tsPinnedTombstone,
        tsEntityLinkItem,
        tsEntityLinkTombstone,
        tsMinionItem,
        tsMinionTombstone,
        tsEncounterItem,
        tsEncounterTombstone,
        tsRosterItem,
        tsRosterTombstone,
      };
      expect(extracted.toSet(), equals(expected));
      expect(extracted.length, equals(11));
    });
  });
}
