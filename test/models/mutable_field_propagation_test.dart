import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/crdt/stateful_hlc_clock.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/models/aggregate_hlc_extractor.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';

void main() {
  group('Cold Iron Birdcage — Pass 4.2: Mutable Field Propagation & Single-Writer Law', () {
    late StatefulHlcClock clockA;

    setUp(() {
      clockA = StatefulHlcClock(
        replicaId: ReplicaId('replica-a'),
        timeProvider: () => 1700000000000,
      );
    });

    CampaignProfile createBaseProfile() {
      final link = RoomEntityLink(
        entityId: 'link-door',
        displayName: 'North Door',
        notes: 'north door',
      );
      final instance = EntityInstance(
        instanceId: 'inst-goblin',
        displayName: 'Goblin',
      );
      final container = LootContainer(
        containerId: 'cont-chest',
        name: 'Chest',
      );
      final room = RoomNodeState(
        roomId: 'room-1',
        roomCode: 'RC-101',
        title: 'Tavern',
        description: 'old text',
        entityLinks: [link],
        entityInstances: [instance],
        containers: [container],
      );

      return CampaignProfile.raw(
        id: 'camp-base',
        name: 'Old Campaign',
        createdAt: DateTime.utc(2026, 1, 1),
        lastPlayedAt: DateTime.utc(2026, 1, 1),
        roomState: room,
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Briefing notes',
          timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
        ),
      );
    }

    group('1. Single-Writer Propagation Law', () {
      test('CampaignProfile.name: "Old Campaign" -> "New Campaign" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final mutA = base.copyWith(
          name: 'New Campaign',
          nameTimestamp: tsA,
        );
        final repB = base;

        // Commutative merge
        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.name, equals('New Campaign'));
        expect(joinBA.name, equals('New Campaign'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.nameRegister.timestamp, equals(tsA));

        // Repeated merge convergence
        final repeated = CampaignProfile.join(joinAB, repB);
        expect(repeated, equals(joinAB));
      });

      test('RoomNodeState.title: "Tavern" -> "Crypt" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            title: 'Crypt',
            titleTimestamp: tsA,
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.title, equals('Crypt'));
        expect(joinBA.roomState.title, equals('Crypt'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.titleRegister.timestamp, equals(tsA));
      });

      test('RoomNodeState.description: "old text" -> "new text" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            description: 'new text',
            descriptionTimestamp: tsA,
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.description, equals('new text'));
        expect(joinBA.roomState.description, equals('new text'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.descriptionRegister.timestamp, equals(tsA));
      });

      test('EntityInstance.displayName: "Goblin" -> "Goblin Boss" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final updatedInstance = base.roomState.entityInstances.first.copyWith(
          displayName: 'Goblin Boss',
          displayNameTimestamp: tsA,
        );
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            entityInstances: [updatedInstance],
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.entityInstances.first.displayName, equals('Goblin Boss'));
        expect(joinBA.roomState.entityInstances.first.displayName, equals('Goblin Boss'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.entityInstances.first.displayNameRegister.timestamp, equals(tsA));
      });

      test('RoomEntityLink.notes: "north door" -> "trapped north door" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final updatedLink = base.roomState.entityLinks.first.copyWith(
          notes: 'trapped north door',
          notesTimestamp: tsA,
        );
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            entityLinksCrdt: base.roomState.entityLinksCrdt.add(updatedLink.entityId, updatedLink, tsA),
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.entityLinks.first.notes, equals('trapped north door'));
        expect(joinBA.roomState.entityLinks.first.notes, equals('trapped north door'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.entityLinks.first.notesRegister.timestamp, equals(tsA));
      });

      test('LootContainer.name: "Chest" -> "Royal Vault" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final updatedContainer = base.roomState.containers.first.copyWith(
          name: 'Royal Vault',
          nameTimestamp: tsA,
        );
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            containers: [updatedContainer],
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.containers.first.name, equals('Royal Vault'));
        expect(joinBA.roomState.containers.first.name, equals('Royal Vault'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.containers.first.nameRegister.timestamp, equals(tsA));
      });
    });

    group('2. Concurrent Edits & Conflict Resolution', () {
      test('Concurrent Campaign name edits: higher HLC wins deterministically in both directions', () {
        final base = createBaseProfile();
        const tsA = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'replica-a');
        const tsB = HybridLogicalClock(physicalTime: 3000, logicalCounter: 0, nodeId: 'replica-b');

        final mutA = base.copyWith(name: 'Campaign by A', nameTimestamp: tsA);
        final mutB = base.copyWith(name: 'Campaign by B', nameTimestamp: tsB);

        final joinAB = CampaignProfile.join(mutA, mutB);
        final joinBA = CampaignProfile.join(mutB, mutA);

        expect(joinAB.name, equals('Campaign by B'));
        expect(joinBA.name, equals('Campaign by B'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.nameRegister.timestamp, equals(tsB));
      });

      test('Concurrent Room title edits: higher HLC wins deterministically', () {
        final base = createBaseProfile();
        const tsA = HybridLogicalClock(physicalTime: 5000, logicalCounter: 0, nodeId: 'replica-a');
        const tsB = HybridLogicalClock(physicalTime: 4000, logicalCounter: 0, nodeId: 'replica-b');

        final mutA = base.copyWith(roomState: base.roomState.copyWith(title: 'Crypt', titleTimestamp: tsA));
        final mutB = base.copyWith(roomState: base.roomState.copyWith(title: 'Dungeon', titleTimestamp: tsB));

        final joinAB = CampaignProfile.join(mutA, mutB);
        final joinBA = CampaignProfile.join(mutB, mutA);

        expect(joinAB.roomState.title, equals('Crypt'));
        expect(joinBA.roomState.title, equals('Crypt'));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.titleRegister.timestamp, equals(tsA));
      });

      test('Exact-HLC collision with divergent values fails loudly and symmetrically', () {
        final base = createBaseProfile();
        const collisionTs = HybridLogicalClock(physicalTime: 9999, logicalCounter: 1, nodeId: 'same-node');

        final mutA = base.copyWith(name: 'Name A', nameTimestamp: collisionTs);
        final mutB = base.copyWith(name: 'Name B', nameTimestamp: collisionTs);

        expect(() => CampaignProfile.join(mutA, mutB), throwsA(isA<StateError>()));
        expect(() => CampaignProfile.join(mutB, mutA), throwsA(isA<StateError>()));
      });
    });

    group('3. HLC Extraction & Remote Drift Validation', () {
      test('extractCampaignProfileTimestamps extracts all newly versioned fields', () {
        const tsName = HybridLogicalClock(physicalTime: 101, logicalCounter: 0, nodeId: 'n1');
        const tsTitle = HybridLogicalClock(physicalTime: 102, logicalCounter: 0, nodeId: 'n1');
        const tsDesc = HybridLogicalClock(physicalTime: 103, logicalCounter: 0, nodeId: 'n1');
        const tsLinkNotes = HybridLogicalClock(physicalTime: 104, logicalCounter: 0, nodeId: 'n1');
        const tsInstName = HybridLogicalClock(physicalTime: 105, logicalCounter: 0, nodeId: 'n1');
        const tsContName = HybridLogicalClock(physicalTime: 106, logicalCounter: 0, nodeId: 'n1');

        final link = RoomEntityLink(
          entityId: 'link-1',
          displayName: 'Door',
          notes: 'Trapped',
          notesTimestamp: tsLinkNotes,
        );
        final instance = EntityInstance(
          instanceId: 'inst-1',
          displayName: 'Orc',
          displayNameTimestamp: tsInstName,
        );
        final container = LootContainer(
          containerId: 'cont-1',
          name: 'Chest',
          nameTimestamp: tsContName,
        );
        final room = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC1',
          title: 'Room 1',
          titleTimestamp: tsTitle,
          description: 'Desc 1',
          descriptionTimestamp: tsDesc,
          entityLinks: [link],
          entityInstances: [instance],
          containers: [container],
        );
        final profile = CampaignProfile.raw(
          id: 'camp-1',
          name: 'Camp 1',
          nameRegister: const CrdtLwwRegister<String>(value: 'Camp 1', timestamp: tsName),
          createdAt: DateTime.utc(2026, 1, 1),
          lastPlayedAt: DateTime.utc(2026, 1, 1),
          roomState: room,
          notesRegister: const CrdtLwwRegister<String>(
            value: 'Notes',
            timestamp: HybridLogicalClock(physicalTime: 107, logicalCounter: 0, nodeId: 'n1'),
          ),
        );

        final extracted = extractCampaignProfileTimestamps(profile);
        final physicalTimes = extracted.map((e) => e.physicalTime).toSet();
        expect(physicalTimes, containsAll([101, 102, 103, 104, 105, 106, 107]));
      });

      test('Remote profile with title timestamp at T + 10 years fails remote drift validation', () {
        final clock = StatefulHlcClock(
          replicaId: ReplicaId('local-node'),
          timeProvider: () => 1700000000000,
        );
        final futureTs = HybridLogicalClock(
          physicalTime: 1700000000000 + const Duration(days: 3650).inMilliseconds,
          logicalCounter: 0,
          nodeId: 'remote-bad',
        );

        final remoteProfile = createBaseProfile().copyWith(
          roomState: createBaseProfile().roomState.copyWith(
            title: 'Hacked Title',
            titleTimestamp: futureTs,
          ),
        );

        final timestamps = extractCampaignProfileTimestamps(remoteProfile);
        final initialClockState = clock.latest;

        expect(
          () => clock.validateAllRemote(timestamps),
          throwsA(isA<HlcFutureDriftException>()),
        );
        expect(clock.latest, equals(initialClockState));
      });

      test('Remote profile with entity instance displayName at T + 10 years fails remote drift validation', () {
        final clock = StatefulHlcClock(
          replicaId: ReplicaId('local-node'),
          timeProvider: () => 1700000000000,
        );
        final futureTs = HybridLogicalClock(
          physicalTime: 1700000000000 + const Duration(days: 3650).inMilliseconds,
          logicalCounter: 0,
          nodeId: 'remote-bad',
        );

        final base = createBaseProfile();
        final badInstance = base.roomState.entityInstances.first.copyWith(
          displayName: 'Hacked Name',
          displayNameTimestamp: futureTs,
        );
        final remoteProfile = base.copyWith(
          roomState: base.roomState.copyWith(entityInstances: [badInstance]),
        );

        final timestamps = extractCampaignProfileTimestamps(remoteProfile);
        final initialClockState = clock.latest;

        expect(
          () => clock.validateAllRemote(timestamps),
          throwsA(isA<HlcFutureDriftException>()),
        );
        expect(clock.latest, equals(initialClockState));
      });
    });

    group('4. Trusted Local History Observation', () {
      test('Local profile with newly versioned timestamps is observed monotonically', () {
        const wallClockT = 1700000000000;
        final clock = StatefulHlcClock(
          replicaId: ReplicaId('current-replica'),
          timeProvider: () => wallClockT,
        );

        final futureHistTs = HybridLogicalClock(
          physicalTime: wallClockT + const Duration(hours: 5).inMilliseconds,
          logicalCounter: 10,
          nodeId: 'past-replica',
        );

        final localProfile = createBaseProfile().copyWith(
          name: 'Renamed Locally In Past',
          nameTimestamp: futureHistTs,
        );

        final timestamps = extractCampaignProfileTimestamps(localProfile);
        expect(() => clock.observeAllTrustedHistory(timestamps), returnsNormally);

        final nextTs = clock.nextTimestamp();
        expect(nextTs.physicalTime, greaterThanOrEqualTo(futureHistTs.physicalTime));
        expect(nextTs.nodeId, equals('current-replica'));
      });
    });

    group('5. Serialization & Round-Trip', () {
      test('RoomNodeState toMap / fromMap roundtrip preserves causal metadata', () {
        const tsTitle = HybridLogicalClock(physicalTime: 500, logicalCounter: 2, nodeId: 'n1');
        const tsDesc = HybridLogicalClock(physicalTime: 600, logicalCounter: 3, nodeId: 'n1');
        final room = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC1',
          title: 'Room 1',
          titleTimestamp: tsTitle,
          description: 'Description 1',
          descriptionTimestamp: tsDesc,
        );

        final map = room.toMap();
        expect(map['title'], equals('Room 1'));
        expect(map['titleRegister']['value'], equals('Room 1'));
        expect(map['titleRegister']['timestamp']['pt'], equals(500));
        expect(map['titleRegister']['timestamp']['lc'], equals(2));
        expect(map['titleRegister']['timestamp']['node'], equals('n1'));

        final restored = RoomNodeState.fromMap(map);
        expect(restored, equals(room));
        expect(restored.titleRegister.timestamp, equals(tsTitle));
        expect(restored.descriptionRegister.timestamp, equals(tsDesc));
      });

      test('EntityInstance toMap / fromMap roundtrip preserves causal metadata', () {
        const ts = HybridLogicalClock(physicalTime: 700, logicalCounter: 1, nodeId: 'n1');
        final instance = EntityInstance(
          instanceId: 'i1',
          displayName: 'Named Orc',
          displayNameTimestamp: ts,
        );

        final map = instance.toMap();
        expect(map['displayName'], equals('Named Orc'));
        expect(map['displayNameRegister']['value'], equals('Named Orc'));
        expect(map['displayNameRegister']['timestamp']['pt'], equals(700));

        final restored = EntityInstance.fromMap(map);
        expect(restored, equals(instance));
        expect(restored.displayNameRegister.timestamp, equals(ts));
      });

      test('RoomEntityLink toMap / fromMap roundtrip preserves causal metadata', () {
        const ts = HybridLogicalClock(physicalTime: 800, logicalCounter: 1, nodeId: 'n1');
        final link = RoomEntityLink(
          entityId: 'e1',
          displayName: 'Portal',
          notes: 'Active portal',
          notesTimestamp: ts,
        );

        final map = link.toMap();
        expect(map['notes'], equals('Active portal'));
        expect(map['notesRegister']['value'], equals('Active portal'));
        expect(map['notesRegister']['timestamp']['pt'], equals(800));

        final restored = RoomEntityLink.fromMap(map);
        expect(restored, equals(link));
        expect(restored.notesRegister.timestamp, equals(ts));
      });

      test('LootContainer toMap / fromMap roundtrip preserves causal metadata', () {
        const ts = HybridLogicalClock(physicalTime: 900, logicalCounter: 1, nodeId: 'n1');
        final container = LootContainer(
          containerId: 'c1',
          name: 'Treasure Chest',
          nameTimestamp: ts,
        );

        final map = container.toMap();
        expect(map['name'], equals('Treasure Chest'));
        expect(map['nameRegister']['value'], equals('Treasure Chest'));
        expect(map['nameRegister']['timestamp']['pt'], equals(900));

        final restored = LootContainer.fromMap(map);
        expect(restored, equals(container));
        expect(restored.nameRegister.timestamp, equals(ts));
      });
    });
  });
}
