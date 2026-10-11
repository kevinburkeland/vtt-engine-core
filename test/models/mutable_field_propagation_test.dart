import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/crdt/stateful_hlc_clock.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/models/aggregate_hlc_extractor.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/utils/aggregate_join_utils.dart';

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

      test('RoomEntityLink.displayName: "North Door" -> "Secret North Door" propagates symmetrically', () {
        final base = createBaseProfile();
        final tsA = clockA.nextTimestamp();
        final updatedLink = base.roomState.entityLinks.first.copyWith(
          displayName: "Secret North Door",
          displayNameTimestamp: tsA,
        );
        final mutA = base.copyWith(
          roomState: base.roomState.copyWith(
            entityLinksCrdt: base.roomState.entityLinksCrdt.add(updatedLink.entityId, updatedLink, tsA),
          ),
        );
        final repB = base;

        final joinAB = CampaignProfile.join(mutA, repB);
        final joinBA = CampaignProfile.join(repB, mutA);

        expect(joinAB.roomState.entityLinks.first.displayName, equals("Secret North Door"));
        expect(joinBA.roomState.entityLinks.first.displayName, equals("Secret North Door"));
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.entityLinks.first.displayNameRegister.timestamp, equals(tsA));
      });

      test('RoomEntityLink.notes: non-null -> null propagates symmetrically via LWW', () {
        final base = createBaseProfile();
        expect(base.roomState.entityLinks.first.notes, isNotNull);
        final tsA = clockA.nextTimestamp();
        final updatedLink = base.roomState.entityLinks.first.copyWith(
          clearNotes: true,
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

        expect(joinAB.roomState.entityLinks.first.notes, isNull);
        expect(joinBA.roomState.entityLinks.first.notes, isNull);
        expect(joinAB, equals(joinBA));
        expect(joinAB.roomState.entityLinks.first.notesRegister.timestamp, equals(tsA));
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

      test('Concurrent RoomEntityLink displayName edits: higher HLC wins deterministically', () {
        final base = createBaseProfile();
        const tsA = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: "n1");
        const tsB = HybridLogicalClock(physicalTime: 3000, logicalCounter: 0, nodeId: "n2");

        final linkA = base.roomState.entityLinks.first.copyWith(
          displayName: "Iron Door",
          displayNameTimestamp: tsA,
        );
        final linkB = base.roomState.entityLinks.first.copyWith(
          displayName: "Adamantine Door",
          displayNameTimestamp: tsB,
        );

        final joined = RoomEntityLink.join(linkA, linkB);
        final joinedRev = RoomEntityLink.join(linkB, linkA);

        expect(joined.displayName, equals("Adamantine Door"));
        expect(joinedRev.displayName, equals("Adamantine Door"));
        expect(joined, equals(joinedRev));
        expect(joined.displayNameRegister.timestamp, equals(tsB));
      });

      test('Exact-HLC collision on RoomEntityLink.displayName fails loudly and symmetrically', () {
        final base = createBaseProfile();
        const collisionTs = HybridLogicalClock(physicalTime: 5000, logicalCounter: 0, nodeId: "same-node");

        final linkA = base.roomState.entityLinks.first.copyWith(
          displayName: "Door Alpha",
          displayNameTimestamp: collisionTs,
        );
        final linkB = base.roomState.entityLinks.first.copyWith(
          displayName: "Door Beta",
          displayNameTimestamp: collisionTs,
        );

        expect(() => RoomEntityLink.join(linkA, linkB), throwsA(isA<StateError>()));
        expect(() => RoomEntityLink.join(linkB, linkA), throwsA(isA<StateError>()));
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

    group('6. Authoritative Register Strict Presence & Malformed Fallback Prevention', () {
      test('RoomNodeState.fromMap: titleRegister strict presence', () {
        // PRESENT wrong type throws FormatException, NEVER falls back to legacy title
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "titleRegister": "bad-string",
            "title": "Legacy Tavern",
          }),
          throwsA(isA<FormatException>()),
        );

        // PRESENT null throws FormatException
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "titleRegister": null,
            "title": "Legacy Tavern",
          }),
          throwsA(isA<FormatException>()),
        );

        // PRESENT map with malformed timestamp throws FormatException
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "titleRegister": {
              "value": "Valid Title",
              "timestamp": "not-a-map",
            },
            "title": "Legacy Tavern",
          }),
          throwsA(isA<FormatException>()),
        );

        // PRESENT valid register + divergent legacy scalar: authoritative register wins
        final validWithDivergentLegacy = RoomNodeState.fromMap({
          "roomId": "r1",
          "titleRegister": {
            "value": "Authoritative Crypt",
            "timestamp": {"pt": 500, "lc": 0, "node": "n1"},
          },
          "title": "Divergent Legacy Title",
        });
        expect(validWithDivergentLegacy.title, equals("Authoritative Crypt"));
        expect(validWithDivergentLegacy.titleRegister.timestamp.physicalTime, equals(500));

        // ABSENT register: migrates legacy scalar at genesis HLC
        final legacyAbsent = RoomNodeState.fromMap({
          "roomId": "r1",
          "title": "Legacy Tavern",
        });
        expect(legacyAbsent.title, equals("Legacy Tavern"));
        expect(legacyAbsent.titleRegister.timestamp.physicalTime, equals(0));
        expect(legacyAbsent.titleRegister.timestamp.nodeId, equals("genesis"));
      });

      test('RoomNodeState.fromMap: descriptionRegister strict presence', () {
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "descriptionRegister": 12345,
            "description": "Legacy Desc",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "descriptionRegister": null,
            "description": "Legacy Desc",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "descriptionRegister": {
              "value": "Valid Desc",
              "timestamp": {"pt": "bad-pt", "node": "n1"},
            },
            "description": "Legacy Desc",
          }),
          throwsA(isA<FormatException>()),
        );

        final validDesc = RoomNodeState.fromMap({
          "roomId": "r1",
          "descriptionRegister": {
            "value": "Authoritative Desc",
            "timestamp": {"pt": 600, "lc": 0, "node": "n1"},
          },
          "description": "Divergent Legacy Desc",
        });
        expect(validDesc.description, equals("Authoritative Desc"));
        expect(validDesc.descriptionRegister.timestamp.physicalTime, equals(600));

        final absentDesc = RoomNodeState.fromMap({
          "roomId": "r1",
          "description": "Legacy Desc",
        });
        expect(absentDesc.description, equals("Legacy Desc"));
        expect(absentDesc.descriptionRegister.timestamp.physicalTime, equals(0));
      });

      test('EntityInstance.fromMap: displayNameRegister strict presence', () {
        expect(
          () => EntityInstance.fromMap({
            "instanceId": "i1",
            "displayNameRegister": "corrupted",
            "displayName": "Goblin",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => EntityInstance.fromMap({
            "instanceId": "i1",
            "displayNameRegister": null,
            "displayName": "Goblin",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => EntityInstance.fromMap({
            "instanceId": "i1",
            "displayNameRegister": {
              "value": "Boss",
              "timestamp": null,
            },
            "displayName": "Goblin",
          }),
          throwsA(isA<FormatException>()),
        );

        final validInst = EntityInstance.fromMap({
          "instanceId": "i1",
          "displayNameRegister": {
            "value": "Hobgoblin Warlord",
            "timestamp": {"pt": 700, "lc": 0, "node": "n1"},
          },
          "displayName": "Goblin Minion",
        });
        expect(validInst.displayName, equals("Hobgoblin Warlord"));
        expect(validInst.displayNameRegister.timestamp.physicalTime, equals(700));

        final absentInst = EntityInstance.fromMap({
          "instanceId": "i1",
          "displayName": "Goblin Minion",
        });
        expect(absentInst.displayName, equals("Goblin Minion"));
        expect(absentInst.displayNameRegister.timestamp.physicalTime, equals(0));
      });

      test('RoomEntityLink.fromMap: displayNameRegister and notesRegister strict presence', () {
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "displayNameRegister": "bad",
            "displayName": "Old Door",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "notesRegister": false,
            "notes": "Old notes",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "notesRegister": {
              "value": "Valid notes",
              "timestamp": "malformed",
            },
            "notes": "Old notes",
          }),
          throwsA(isA<FormatException>()),
        );

        final validLink = RoomEntityLink.fromMap({
          "entityId": "e1",
          "displayNameRegister": {
            "value": "Iron Portcullis",
            "timestamp": {"pt": 800, "lc": 0, "node": "n1"},
          },
          "displayName": "Old Wooden Door",
          "notesRegister": {
            "value": "Trapped with glyph",
            "timestamp": {"pt": 850, "lc": 0, "node": "n1"},
          },
          "notes": "No traps",
        });
        expect(validLink.displayName, equals("Iron Portcullis"));
        expect(validLink.notes, equals("Trapped with glyph"));
        expect(validLink.displayNameRegister.timestamp.physicalTime, equals(800));
        expect(validLink.notesRegister.timestamp.physicalTime, equals(850));

        // Null value in notesRegister is valid and preserved
        final nullNotesLink = RoomEntityLink.fromMap({
          "entityId": "e1",
          "notesRegister": {
            "value": null,
            "timestamp": {"pt": 900, "lc": 0, "node": "n1"},
          },
          "notes": "Legacy note",
        });
        expect(nullNotesLink.notes, isNull);
        expect(nullNotesLink.notesRegister.timestamp.physicalTime, equals(900));

        // Absent registers migrate legacy scalars
        final absentLink = RoomEntityLink.fromMap({
          "entityId": "e1",
          "displayName": "Old Wooden Door",
          "notes": "Legacy note",
        });
        expect(absentLink.displayName, equals("Old Wooden Door"));
        expect(absentLink.notes, equals("Legacy note"));
        expect(absentLink.displayNameRegister.timestamp.physicalTime, equals(0));
        expect(absentLink.notesRegister.timestamp.physicalTime, equals(0));
      });

      test('LootContainer.fromMap: nameRegister strict presence', () {
        expect(
          () => LootContainer.fromMap({
            "containerId": "c1",
            "nameRegister": [1, 2, 3],
            "name": "Old Chest",
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => LootContainer.fromMap({
            "containerId": "c1",
            "nameRegister": null,
            "name": "Old Chest",
          }),
          throwsA(isA<FormatException>()),
        );

        final validContainer = LootContainer.fromMap({
          "containerId": "c1",
          "nameRegister": {
            "value": "Gilded Reliquary",
            "timestamp": {"pt": 950, "lc": 0, "node": "n1"},
          },
          "name": "Rotten Wooden Box",
        });
        expect(validContainer.name, equals("Gilded Reliquary"));
        expect(validContainer.nameRegister.timestamp.physicalTime, equals(950));

        final absentContainer = LootContainer.fromMap({
          "containerId": "c1",
          "name": "Rotten Wooden Box",
        });
        expect(absentContainer.name, equals("Rotten Wooden Box"));
        expect(absentContainer.nameRegister.timestamp.physicalTime, equals(0));
      });
    });

    group('7. RoomEntityLink Notes Clearing & copyWith Contracts', () {
      test('copyWith requires timestamp for displayName, notes, and clearNotes', () {
        final link = RoomEntityLink(entityId: "e1", displayName: "Door", notes: "A note");
        const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: "n1");

        // Mutating displayName without timestamp throws ArgumentError
        expect(() => link.copyWith(displayName: "New Door"), throwsA(isA<ArgumentError>()));

        // Mutating notes without timestamp throws ArgumentError
        expect(() => link.copyWith(notes: "New Note"), throwsA(isA<ArgumentError>()));

        // Explicitly clearing notes with null without timestamp throws ArgumentError
        expect(() => link.copyWith(notes: null), throwsA(isA<ArgumentError>()));

        // Clearing notes via clearNotes: true without timestamp throws ArgumentError
        expect(() => link.copyWith(clearNotes: true), throwsA(isA<ArgumentError>()));

        // With timestamp, mutations succeed
        final renamed = link.copyWith(displayName: "Reinforced Door", displayNameTimestamp: ts);
        expect(renamed.displayName, equals("Reinforced Door"));

        final renoted = link.copyWith(notes: "Reinforced hinges", notesTimestamp: ts);
        expect(renoted.notes, equals("Reinforced hinges"));

        final cleared1 = link.copyWith(notes: null, notesTimestamp: ts);
        expect(cleared1.notes, isNull);

        final cleared2 = link.copyWith(clearNotes: true, notesTimestamp: ts);
        expect(cleared2.notes, isNull);

        // Omitting notes preserves existing notes
        final untouched = link.copyWith(entityId: "e2");
        expect(untouched.notes, equals("A note"));
      });
    });

    group('8. Strict Register Value-Key Presence (Pass 4.2.2)', () {
      final validHlcMap = {"pt": 1000, "lc": 0, "node": "n1"};

      test('LootContainer.fromMap: timestamp without value/v key throws FormatException', () {
        expect(
          () => LootContainer.fromMap({
            "containerId": "c1",
            "nameRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LootContainer.fromMap({
            "containerId": "c1",
            "nameRegister": {"ts": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LootContainer.fromMap({
            "containerId": "c1",
            "nameRegister": {"timestamp": validHlcMap, "value": null},
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('RoomNodeState.fromMap: titleRegister timestamp without value throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "titleRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "titleRegister": {"timestamp": validHlcMap, "value": null},
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('RoomNodeState.fromMap: descriptionRegister timestamp without value throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "descriptionRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RoomNodeState.fromMap({
            "roomId": "r1",
            "descriptionRegister": {"timestamp": validHlcMap, "value": null},
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('EntityInstance.fromMap: displayNameRegister timestamp without value throws FormatException', () {
        expect(
          () => EntityInstance.fromMap({
            "instanceId": "i1",
            "displayNameRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => EntityInstance.fromMap({
            "instanceId": "i1",
            "displayNameRegister": {"timestamp": validHlcMap, "value": null},
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('RoomEntityLink.fromMap: displayNameRegister timestamp without value throws FormatException', () {
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "displayNameRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "displayNameRegister": {"timestamp": validHlcMap, "value": null},
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('RoomEntityLink.fromMap: notesRegister distinguishes authoritative null from missing value', () {
        // Missing value key throws FormatException
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "notesRegister": {"timestamp": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "e1",
            "notesRegister": {"ts": validHlcMap},
          }),
          throwsA(isA<FormatException>()),
        );

        // Explicit "value": null is valid authoritative null
        final linkWithNullValue = RoomEntityLink.fromMap({
          "entityId": "e1",
          "notesRegister": {"value": null, "timestamp": validHlcMap},
        });
        expect(linkWithNullValue.notes, isNull);
        expect(linkWithNullValue.notesRegister.timestamp.physicalTime, equals(1000));

        // Explicit "v": null is valid authoritative null
        final linkWithNullV = RoomEntityLink.fromMap({
          "entityId": "e1",
          "notesRegister": {"v": null, "ts": validHlcMap},
        });
        expect(linkWithNullV.notes, isNull);
        expect(linkWithNullV.notesRegister.timestamp.physicalTime, equals(1000));
      });
    });

    group('9. joinEntityLinks Recursive Nested Composition & Algebra (Pass 4.2.2)', () {
      const ts1000 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: "n1");
      const ts2000 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: "nA");
      const ts3000 = HybridLogicalClock(physicalTime: 3000, logicalCounter: 0, nodeId: "nB");
      const ts4000 = HybridLogicalClock(physicalTime: 4000, logicalCounter: 0, nodeId: "nC");

      final baseLink = RoomEntityLink(
        entityId: "link-door",
        displayName: "Door",
        displayNameTimestamp: ts1000,
        notes: "Locked",
        notesTimestamp: ts1000,
      );

      test('Concurrent independent nested-field edits: both edits survive', () {
        // Replica A edits displayName
        final linkA = baseLink.copyWith(
          displayName: "Secret Door",
          displayNameTimestamp: ts2000,
        );
        final setA = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkA, ts2000);

        // Replica B edits notes
        final linkB = baseLink.copyWith(
          notes: "Trapped",
          notesTimestamp: ts3000,
        );
        final setB = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkB, ts3000);

        final mergedAB = joinEntityLinks(setA, setB);
        final mergedBA = joinEntityLinks(setB, setA);

        expect(mergedAB, equals(mergedBA));
        expect(mergedAB.items.containsKey("link-door"), isTrue);

        final surviving = mergedAB.items["link-door"]!;
        expect(surviving.timestamp, equals(ts3000)); // max(ts2000, ts3000)
        expect(surviving.value.displayName, equals("Secret Door"));
        expect(surviving.value.notes, equals("Trapped"));
      });

      test('Removal vs edit: newer removal defeats stale edit', () {
        // Replica A edits at ts1000
        final setA = const EntityLinkCrdtSet.empty().add("link-door", baseLink, ts1000);

        // Replica B removes at ts2000
        final setB = const EntityLinkCrdtSet.empty()
            .add("link-door", baseLink, ts1000)
            .remove("link-door", ts2000);

        final merged = joinEntityLinks(setA, setB);
        expect(merged.items.containsKey("link-door"), isFalse);
        expect(merged.tombstones["link-door"]!.timestamp, equals(ts2000));
      });

      test('Newer re-add defeats older tombstone', () {
        // Replica A had removed at ts1000
        final setA = const EntityLinkCrdtSet.empty().remove("link-door", ts1000);

        // Replica B re-added at ts2000 (new generation ts2000)
        final readdedLink = baseLink.copyWith(
          incarnationTimestamp: ts2000,
          displayNameTimestamp: ts2000,
        );
        final setB = const EntityLinkCrdtSet.empty().add("link-door", readdedLink, ts2000);

        final merged = joinEntityLinks(setA, setB);
        expect(merged.items.containsKey("link-door"), isTrue);
        expect(merged.items["link-door"]!.timestamp, equals(ts2000));
        expect(merged.items["link-door"]!.value.incarnationTimestamp, equals(ts2000));
      });

      test('Newer edit after re-add is preserved', () {
        // Set with re-add at ts2000, then edit at ts3000
        final readdedLink = baseLink.copyWith(
          displayName: "Dungeon Gate",
          displayNameTimestamp: ts3000,
          incarnationTimestamp: ts2000,
        );
        final setA = const EntityLinkCrdtSet.empty().add("link-door", readdedLink, ts3000);
        final setB = const EntityLinkCrdtSet.empty().remove("link-door", ts1000);

        final merged = joinEntityLinks(setA, setB);
        expect(merged.items["link-door"]!.value.displayName, equals("Dungeon Gate"));
        expect(merged.items["link-door"]!.timestamp, equals(ts3000));
        expect(merged.items["link-door"]!.value.incarnationTimestamp, equals(ts2000));
      });

      test('Exact-HLC divergent nested payload collision throws StateError', () {
        final linkA = baseLink.copyWith(
          displayName: "Iron Door",
          displayNameTimestamp: ts2000,
        );
        final linkB = baseLink.copyWith(
          displayName: "Wooden Door",
          displayNameTimestamp: ts2000,
        );
        final setA = const EntityLinkCrdtSet.empty().add("link-door", linkA, ts2000);
        final setB = const EntityLinkCrdtSet.empty().add("link-door", linkB, ts2000);

        expect(() => joinEntityLinks(setA, setB), throwsA(isA<StateError>()));
        expect(() => joinEntityLinks(setB, setA), throwsA(isA<StateError>()));
      });

      test('Algebra laws: Idempotence, Commutativity, Associativity', () {
        final linkA = baseLink.copyWith(displayName: "A Door", displayNameTimestamp: ts2000);
        final linkB = baseLink.copyWith(notes: "B Trap", notesTimestamp: ts3000);
        final linkC = baseLink.copyWith(displayName: "C Portal", displayNameTimestamp: ts4000);

        final setA = const EntityLinkCrdtSet.empty().add("link-door", linkA, ts2000);
        final setB = const EntityLinkCrdtSet.empty().add("link-door", linkB, ts3000);
        final setC = const EntityLinkCrdtSet.empty().add("link-door", linkC, ts4000);

        // Idempotence
        expect(joinEntityLinks(setA, setA), equals(setA));
        expect(joinEntityLinks(setB, setB), equals(setB));

        // Commutativity
        expect(joinEntityLinks(setA, setB), equals(joinEntityLinks(setB, setA)));
        expect(joinEntityLinks(setB, setC), equals(joinEntityLinks(setC, setB)));
        expect(joinEntityLinks(setA, setC), equals(joinEntityLinks(setC, setA)));

        // Associativity
        final abThenC = joinEntityLinks(joinEntityLinks(setA, setB), setC);
        final aThenBc = joinEntityLinks(setA, joinEntityLinks(setB, setC));
        expect(abThenC, equals(aThenBc));
        expect(abThenC.items["link-door"]!.value.displayName, equals("C Portal"));
        expect(abThenC.items["link-door"]!.value.notes, equals("B Trap"));
      });

      test('Permanent bar: joinEntityLinks cannot regress to opaque a.merge(b)', () {
        final linkA = baseLink.copyWith(displayName: "Portcullis", displayNameTimestamp: ts2000);
        final linkB = baseLink.copyWith(notes: "Electrified", notesTimestamp: ts3000);

        final setA = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkA, ts2000);
        final setB = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkB, ts3000);

        // Generic a.merge(b) would drop linkA.displayName because ts3000 > ts2000
        final opaqueResult = setA.merge(setB);
        expect(opaqueResult.items["link-door"]!.value.displayName, equals("Door"),
            reason: "Generic merge erroneously drops nested field edit");

        // joinEntityLinks MUST preserve both
        final properResult = joinEntityLinks(setA, setB);
        expect(properResult.items["link-door"]!.value.displayName, equals("Portcullis"));
        expect(properResult.items["link-door"]!.value.notes, equals("Electrified"));
      });
    });

    group('10. Entity-Link Incarnation Semantics & Remove/Re-add Associativity (Pass 4.2.3)', () {
      const ts10 = HybridLogicalClock(physicalTime: 10, logicalCounter: 0, nodeId: "n1");
      const ts20 = HybridLogicalClock(physicalTime: 20, logicalCounter: 0, nodeId: "n2");
      const ts30 = HybridLogicalClock(physicalTime: 30, logicalCounter: 0, nodeId: "n3");
      const ts35 = HybridLogicalClock(physicalTime: 35, logicalCounter: 0, nodeId: "n3");
      const ts40 = HybridLogicalClock(physicalTime: 40, logicalCounter: 0, nodeId: "n4");

      final oldIncarnationLink = RoomEntityLink(
        entityId: "link-door",
        displayName: "Old Door",
        displayNameTimestamp: ts10,
        notes: "old secret note",
        notesTimestamp: ts10,
        incarnationTimestamp: ts10,
      );

      final readdedLink = RoomEntityLink(
        entityId: "link-door",
        displayName: "New Door",
        displayNameTimestamp: ts30,
        notes: null,
        incarnationTimestamp: ts30,
      );

      test('Associativity across old-incarnation -> removal -> re-add: all permutations converge without note resurrection', () {
        // State A: old incarnation @ ts10 with secret note
        final setA = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", oldIncarnationLink, ts10);

        // State B: removal @ ts20
        final setB = const CrdtOrSet<RoomEntityLink>.empty()
            .add("link-door", oldIncarnationLink, ts10)
            .remove("link-door", ts20);

        // State C: re-added link @ ts30 with null notes
        final setC = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", readdedLink, ts30);

        // Permutation 1: (A + B) + C
        final abThenC = joinEntityLinks(joinEntityLinks(setA, setB), setC);

        // Permutation 2: A + (B + C)
        final aThenBc = joinEntityLinks(setA, joinEntityLinks(setB, setC));

        // Permutation 3: (C + B) + A
        final cbThenA = joinEntityLinks(joinEntityLinks(setC, setB), setA);

        // Permutation 4: C + (B + A)
        final cThenBa = joinEntityLinks(setC, joinEntityLinks(setB, setA));

        // Permutation 5: (A + C) + B
        final acThenB = joinEntityLinks(joinEntityLinks(setA, setC), setB);

        // Permutation 6: A + (C + B)
        final aThenCb = joinEntityLinks(setA, joinEntityLinks(setC, setB));

        // All 6 permutations must evaluate identically
        expect(abThenC, equals(aThenBc));
        expect(abThenC, equals(cbThenA));
        expect(abThenC, equals(cThenBa));
        expect(abThenC, equals(acThenB));
        expect(abThenC, equals(aThenCb));

        // Invariant: link exists with new incarnation, new displayName, and null notes (old notes do NOT resurrect)
        final surviving = abThenC.items["link-door"]!;
        expect(surviving.value.displayName, equals("New Door"));
        expect(surviving.value.notes, isNull);
        expect(surviving.value.incarnationTimestamp, equals(ts30));
        expect(surviving.timestamp, equals(ts30));
      });

      test('Stale replica reconnect: pre-removal payload cannot contaminate new incarnation', () {
        // Replica A goes offline with old incarnation @ ts10
        final replicaA = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", oldIncarnationLink, ts10);

        // Replica B removes link @ ts20, re-adds @ ts30, and edits displayName @ ts35
        final linkB35 = readdedLink.copyWith(
          displayName: "Reinforced Portcullis",
          displayNameTimestamp: ts35,
        );
        final replicaB = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkB35, ts35);

        // Replica A reconnects and merges with Replica B in both directions
        final mergedAB = joinEntityLinks(replicaA, replicaB);
        final mergedBA = joinEntityLinks(replicaB, replicaA);

        expect(mergedAB, equals(mergedBA));
        final surviving = mergedAB.items["link-door"]!;
        expect(surviving.value.displayName, equals("Reinforced Portcullis"));
        expect(surviving.value.notes, isNull);
        expect(surviving.value.incarnationTimestamp, equals(ts30));
        expect(surviving.timestamp, equals(ts35));
      });

      test('Same-incarnation independent field edits compose cleanly', () {
        // In incarnation ts30:
        // Replica A edits displayName
        final linkA = readdedLink.copyWith(
          displayName: "Dungeon Portcullis",
          displayNameTimestamp: ts35,
        );
        final setA = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkA, ts35);

        // Replica B edits notes
        final linkB = readdedLink.copyWith(
          notes: "Spike trap mechanism active",
          notesTimestamp: ts40,
        );
        final setB = const CrdtOrSet<RoomEntityLink>.empty().add("link-door", linkB, ts40);

        final merged = joinEntityLinks(setA, setB);
        expect(merged, equals(joinEntityLinks(setB, setA)));

        final surviving = merged.items["link-door"]!;
        expect(surviving.value.displayName, equals("Dungeon Portcullis"));
        expect(surviving.value.notes, equals("Spike trap mechanism active"));
        expect(surviving.value.incarnationTimestamp, equals(ts30));
        expect(surviving.timestamp, equals(ts40));
      });

      test('RoomEntityLink serialization roundtrip preserves incarnationTimestamp', () {
        final link = RoomEntityLink(
          entityId: "link-door",
          displayName: "Vault Gate",
          displayNameTimestamp: ts30,
          incarnationTimestamp: ts30,
        );

        final map = link.toMap();
        expect(map["incarnationTimestamp"], isA<Map>());

        final restored = RoomEntityLink.fromMap(map);
        expect(restored.incarnationTimestamp, equals(ts30));
        expect(restored, equals(link));
      });

      test('RoomEntityLink.fromMap: malformed incarnationTimestamp throws FormatException', () {
        expect(
          () => RoomEntityLink.fromMap({
            "entityId": "link-door",
            "incarnationTimestamp": "not-a-map",
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('11. Generation-Aware Entity-Link Membership & Full Remove-Readd Algebra (Pass 4.2.4)', () {
      const ts10 = HybridLogicalClock(physicalTime: 10, logicalCounter: 0, nodeId: "n1");
      const ts20 = HybridLogicalClock(physicalTime: 20, logicalCounter: 0, nodeId: "n2");
      const ts30 = HybridLogicalClock(physicalTime: 30, logicalCounter: 0, nodeId: "n3");
      const ts35 = HybridLogicalClock(physicalTime: 35, logicalCounter: 0, nodeId: "n2");
      const ts40 = HybridLogicalClock(physicalTime: 40, logicalCounter: 0, nodeId: "n1");
      const ts50 = HybridLogicalClock(physicalTime: 50, logicalCounter: 0, nodeId: "n1");

      final linkG1 = RoomEntityLink(
        entityId: "link-gate",
        displayName: "Gate G1",
        displayNameTimestamp: ts10,
        notes: "G1 Secret Notes",
        notesTimestamp: ts10,
        incarnationTimestamp: ts10,
      );

      final linkG2 = RoomEntityLink(
        entityId: "link-gate",
        displayName: "Gate G2",
        displayNameTimestamp: ts30,
        notes: null,
        incarnationTimestamp: ts30,
      );

      test('J. Core Counterexample: all 6 permutations converge to C without grouping dependence', () {
        // A: G1 created @10, offline edit @40
        final linkA = linkG1.copyWith(
          displayName: "Gate G1 Stale Offline Edit",
          displayNameTimestamp: ts40,
        );
        final setA = const EntityLinkCrdtSet.empty().add("link-gate", linkA, ts40);

        // B: removal targeting G1 @35
        final setB = const EntityLinkCrdtSet.empty()
            .add("link-gate", linkG1, ts10)
            .remove("link-gate", ts35);

        // C: re-add G2 @30, item @30
        final setC = const EntityLinkCrdtSet.empty().add("link-gate", linkG2, ts30);

        final abThenC = joinEntityLinks(joinEntityLinks(setA, setB), setC);
        final aThenBc = joinEntityLinks(setA, joinEntityLinks(setB, setC));
        final cbThenA = joinEntityLinks(joinEntityLinks(setC, setB), setA);
        final cThenBa = joinEntityLinks(setC, joinEntityLinks(setB, setA));
        final acThenB = joinEntityLinks(joinEntityLinks(setA, setC), setB);
        final aThenCb = joinEntityLinks(setA, joinEntityLinks(setC, setB));

        expect(abThenC, equals(aThenBc));
        expect(abThenC, equals(cbThenA));
        expect(abThenC, equals(cThenBa));
        expect(abThenC, equals(acThenB));
        expect(abThenC, equals(aThenCb));

        // Result: G2 survives cleanly, notes are null (no resurrection of G1 notes)
        final item = abThenC.items["link-gate"]!;
        expect(item.value.displayName, equals("Gate G2"));
        expect(item.value.notes, isNull);
        expect(item.value.incarnationTimestamp, equals(ts30));
      });

      test('K. Old-edit-after-remove: removal targeting G1 defeats subsequent offline edit to G1', () {
        // Replica A: edits G1 @40
        final linkA = linkG1.copyWith(
          displayName: "Offline G1 T40",
          displayNameTimestamp: ts40,
        );
        final setA = const EntityLinkCrdtSet.empty().add("link-gate", linkA, ts40);

        // Replica B: removes G1 @35
        final setB = const EntityLinkCrdtSet.empty()
            .add("link-gate", linkG1, ts10)
            .remove("link-gate", ts35);

        // Both directions converge to G1 removed
        final mergedAB = joinEntityLinks(setA, setB);
        final mergedBA = joinEntityLinks(setB, setA);

        expect(mergedAB, equals(mergedBA));
        expect(mergedAB.items.containsKey("link-gate"), isFalse);
        expect(mergedAB.isRemoved("link-gate"), isTrue);
        expect(mergedAB.tombstones["link-gate"]!.targetGeneration, equals(ts10));
        expect(mergedAB.tombstones["link-gate"]!.timestamp, equals(ts35));
      });

      test('L. Stale G1 edit arrives with high edit timestamp (@50) after G2 re-add: G2 survives', () {
        // G1 created, removed @20, G2 created @30
        final setG2 = const EntityLinkCrdtSet.empty()
            .add("link-gate", linkG1, ts10)
            .remove("link-gate", ts20)
            .add("link-gate", linkG2, ts30);

        // Stale G1 edit arrives @50
        final linkG1Stale = linkG1.copyWith(
          displayName: "Very High HLC G1 Edit",
          displayNameTimestamp: ts50,
        );
        final setStaleG1 = const EntityLinkCrdtSet.empty().add("link-gate", linkG1Stale, ts50);

        final merged = joinEntityLinks(setG2, setStaleG1);
        expect(merged, equals(joinEntityLinks(setStaleG1, setG2)));

        // G2 stays current, G1 fields do not leak
        final item = merged.items["link-gate"]!;
        expect(item.value.displayName, equals("Gate G2"));
        expect(item.value.notes, isNull);
        expect(item.value.incarnationTimestamp, equals(ts30));
      });

      test('M. Second removal: G1 -> remove -> G2 -> edit -> remove G2: stale snapshots cannot resurrect', () {
        // G1 created @10, removed @20, G2 created @30, edited @35, removed @40
        final linkG2Edit = linkG2.copyWith(displayName: "G2 Edit @35", displayNameTimestamp: ts35);
        final setDeadG2 = const EntityLinkCrdtSet.empty()
            .add("link-gate", linkG1, ts10)
            .remove("link-gate", ts20)
            .add("link-gate", linkG2, ts30)
            .add("link-gate", linkG2Edit, ts35)
            .remove("link-gate", ts40);

        // Stale G1 snapshot @50 (from an offline replica)
        final staleG1 = const EntityLinkCrdtSet.empty().add(
          "link-gate",
          linkG1.copyWith(displayName: "Stale G1", displayNameTimestamp: ts50),
          ts50,
        );

        // Stale G2 snapshot @35
        final staleG2 = const EntityLinkCrdtSet.empty().add("link-gate", linkG2Edit, ts35);

        final merged = joinEntityLinks(joinEntityLinks(setDeadG2, staleG1), staleG2);
        expect(merged.items.containsKey("link-gate"), isFalse);
        expect(merged.isRemoved("link-gate"), isTrue);
        expect(merged.tombstones["link-gate"]!.targetGeneration, equals(ts30));
        expect(merged.tombstones["link-gate"]!.timestamp, equals(ts40));
      });

      test('N. Same-generation field composition remains fully functional', () {
        final linkA = linkG2.copyWith(displayName: "DisplayName A", displayNameTimestamp: ts35);
        final linkB = linkG2.copyWith(notes: "Notes B", notesTimestamp: ts40);

        final setA = const EntityLinkCrdtSet.empty().add("link-gate", linkA, ts35);
        final setB = const EntityLinkCrdtSet.empty().add("link-gate", linkB, ts40);

        final merged = joinEntityLinks(setA, setB);
        expect(merged, equals(joinEntityLinks(setB, setA)));

        final item = merged.items["link-gate"]!;
        expect(item.value.displayName, equals("DisplayName A"));
        expect(item.value.notes, equals("Notes B"));
        expect(item.value.incarnationTimestamp, equals(ts30));
        expect(item.timestamp, equals(ts40));
      });

      test('T & V. EntityLinkCrdtSet serialization roundtrip and malformed validation', () {
        final set = const EntityLinkCrdtSet.empty()
            .add("live-1", linkG2, ts30)
            .remove("dead-1", ts35);

        final map = set.toMap();
        expect(map["items"], isA<Map>());
        expect(map["tombstones"], isA<Map>());

        final restored = EntityLinkCrdtSet.fromMap(map);
        expect(restored, equals(set));

        // Malformed tombstones throw FormatException
        expect(
          () => EntityLinkCrdtSet.fromMap({
            "tombstones": {
              "dead-1": "not-a-map",
            },
          }),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => EntityLinkCrdtSet.fromMap({
            "items": {
              "live-1": "not-a-map",
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('X. Randomized property tests: idempotence, commutativity, and associativity over 100 transitions', () {

        for (int i = 0; i < 100; i++) {
          final t1 = (i * 10) + 1;
          final t2 = t1 + 5;
          final t3 = t2 + 5;
          final t4 = t3 + 5;

          final hlc1 = HybridLogicalClock(physicalTime: t1, logicalCounter: 0, nodeId: "n1");
          final hlc2 = HybridLogicalClock(physicalTime: t2, logicalCounter: 0, nodeId: "n2");
          final hlc3 = HybridLogicalClock(physicalTime: t3, logicalCounter: 0, nodeId: "n3");
          final hlc4 = HybridLogicalClock(physicalTime: t4, logicalCounter: 0, nodeId: "n4");

          final l1 = RoomEntityLink(
            entityId: "link-rnd",
            displayName: "Name $t1",
            displayNameTimestamp: hlc1,
            incarnationTimestamp: hlc1,
          );

          final l2 = RoomEntityLink(
            entityId: "link-rnd",
            displayName: "Name $t3",
            displayNameTimestamp: hlc3,
            incarnationTimestamp: hlc3,
          );

          // Construct 3 diverse states:
          // State A: generation 1 live or edited
          EntityLinkCrdtSet setA = const EntityLinkCrdtSet.empty().add("link-rnd", l1, hlc1);
          if (i % 2 == 0) {
            setA = setA.add("link-rnd", l1.copyWith(displayName: "Edit A $t2", displayNameTimestamp: hlc2), hlc2);
          }

          // State B: generation 1 removed or generation 2 live
          EntityLinkCrdtSet setB;
          if (i % 3 == 0) {
            setB = const EntityLinkCrdtSet.empty().add("link-rnd", l1, hlc1).remove("link-rnd", hlc2);
          } else {
            setB = const EntityLinkCrdtSet.empty().add("link-rnd", l2, hlc3);
          }

          // State C: generation 2 edited or generation 2 removed
          EntityLinkCrdtSet setC;
          if (i % 4 == 0) {
            setC = const EntityLinkCrdtSet.empty().add("link-rnd", l2, hlc3).remove("link-rnd", hlc4);
          } else {
            setC = const EntityLinkCrdtSet.empty().add("link-rnd", l2.copyWith(notes: "Notes C $t4", notesTimestamp: hlc4), hlc4);
          }

          // 1. Idempotence
          expect(setA.merge(setA), equals(setA));
          expect(setB.merge(setB), equals(setB));
          expect(setC.merge(setC), equals(setC));

          // 2. Commutativity
          expect(setA.merge(setB), equals(setB.merge(setA)));
          expect(setB.merge(setC), equals(setC.merge(setB)));
          expect(setA.merge(setC), equals(setC.merge(setA)));

          // 3. Associativity across all groupings
          final abThenC = (setA.merge(setB)).merge(setC);
          final aThenBc = setA.merge(setB.merge(setC));
          final cbThenA = (setC.merge(setB)).merge(setA);
          final cThenBa = setC.merge(setB.merge(setA));
          final acThenB = (setA.merge(setC)).merge(setB);
          final aThenCb = setA.merge(setC.merge(setB));

          expect(abThenC, equals(aThenBc));
          expect(abThenC, equals(cbThenA));
          expect(abThenC, equals(cThenBa));
          expect(abThenC, equals(acThenB));
          expect(abThenC, equals(aThenCb));
        }
      });
    });

    group('12. Pass 4.2.5 Inflationary Mutations, Explicit Re-Add & Typed CRDT Construction', () {
      test('M & N. Local mutation monotonicity & explicit re-add laws', () {
        const ts10 = HybridLogicalClock(physicalTime: 10, logicalCounter: 0, nodeId: "n1");
        const ts20 = HybridLogicalClock(physicalTime: 20, logicalCounter: 0, nodeId: "n2");
        const ts30 = HybridLogicalClock(physicalTime: 30, logicalCounter: 0, nodeId: "n3");
        const ts40 = HybridLogicalClock(physicalTime: 40, logicalCounter: 0, nodeId: "n1");
        const ts50 = HybridLogicalClock(physicalTime: 50, logicalCounter: 0, nodeId: "n2");
        const ts60 = HybridLogicalClock(physicalTime: 60, logicalCounter: 0, nodeId: "n3");

        final g1 = RoomEntityLink(
          entityId: "link-mut",
          displayName: "G1 Name",
          displayNameTimestamp: ts10,
          notes: "G1 Notes",
          notesTimestamp: ts10,
          incarnationTimestamp: ts10,
        );

        final g2 = RoomEntityLink(
          entityId: "link-mut",
          displayName: "G2 Name",
          displayNameTimestamp: ts30,
          notes: null,
          incarnationTimestamp: ts30,
        );

        // 1. Initial creation
        var set = const EntityLinkCrdtSet.empty().createOrReadd("link-mut", g1, ts10);
        expect(set.items["link-mut"]!.value.displayName, equals("G1 Name"));
        expect(set.items["link-mut"]!.value.incarnationTimestamp, equals(ts10));

        // 2. Removal targets active G1
        set = set.remove("link-mut", ts20);
        expect(set.isRemoved("link-mut"), isTrue);
        expect(set.tombstones["link-mut"]!.targetGeneration, equals(ts10));
        expect(set.tombstones["link-mut"]!.timestamp, equals(ts20));

        // 3. Stale G1 update on removed state -> remains removed!
        final staleG1 = g1.copyWith(displayName: "Stale G1 Offline", displayNameTimestamp: ts40);
        final afterStaleUpdate = set.update("link-mut", staleG1, ts40);
        expect(afterStaleUpdate, equals(set));
        expect(afterStaleUpdate.isRemoved("link-mut"), isTrue);

        // Compatibility add() also cannot resurrect removed state
        final afterStaleAdd = set.add("link-mut", staleG1, ts40);
        expect(afterStaleAdd, equals(set));
        expect(afterStaleAdd.isRemoved("link-mut"), isTrue);

        // 4. Explicit re-add creates G2 from supplied authoritative timestamp
        set = set.createOrReadd("link-mut", g2, ts30);
        expect(set.items.containsKey("link-mut"), isTrue);
        expect(set.isRemoved("link-mut"), isFalse);
        final itemG2 = set.items["link-mut"]!.value;
        expect(itemG2.displayName, equals("G2 Name"));
        expect(itemG2.notes, isNull); // old G1 notes wiped on re-add baseline
        expect(itemG2.incarnationTimestamp, equals(ts30));

        // 5. Active G2 then stale G1 update -> G2 unchanged
        final afterOldUpdate = set.update("link-mut", staleG1, ts40);
        expect(afterOldUpdate, equals(set));
        expect(afterOldUpdate.items["link-mut"]!.value.displayName, equals("G2 Name"));

        // 6. Active G2 @50 then same-G2 snapshot @40 -> newer state retained
        final g2Edit50 = itemG2.copyWith(displayName: "G2 Name @50", displayNameTimestamp: ts50);
        set = set.update("link-mut", g2Edit50, ts50);
        expect(set.items["link-mut"]!.value.displayName, equals("G2 Name @50"));

        final g2Snapshot40 = itemG2.copyWith(displayName: "G2 Snapshot @40", displayNameTimestamp: ts40);
        final afterOlderSnapshot = set.update("link-mut", g2Snapshot40, ts40);
        expect(afterOlderSnapshot.items["link-mut"]!.value.displayName, equals("G2 Name @50"));

        // 7. Active G2 then ordinary update carrying G3 -> does NOT silently create G3
        final g3Candidate = RoomEntityLink(
          entityId: "link-mut",
          displayName: "G3 Candidate",
          displayNameTimestamp: ts60,
          incarnationTimestamp: ts60,
        );
        final afterG3Update = set.update("link-mut", g3Candidate, ts60);
        expect(afterG3Update, equals(set));
        expect(afterG3Update.items["link-mut"]!.value.incarnationTimestamp, equals(ts30));

        // 8. Repeated same mutation -> idempotent
        final repeatUpdate = set.update("link-mut", g2Edit50, ts50);
        expect(repeatUpdate, equals(set));
      });

      test('X. RoomNodeState constructor & copyWith strict invalid input type rejection', () {
        // Constructor rejects invalid non-null entityLinksCrdt
        expect(
          () => RoomNodeState(
            roomId: "r1",
            roomCode: "RC",
            entityLinksCrdt: "invalid_string",
          ),
          throwsArgumentError,
        );
        expect(
          () => RoomNodeState(
            roomId: "r1",
            roomCode: "RC",
            entityLinksCrdt: 42,
          ),
          throwsArgumentError,
        );

        // Constructor accepts valid EntityLinkCrdtSet
        final validSet = const EntityLinkCrdtSet.empty();
        final room = RoomNodeState(
          roomId: "r1",
          roomCode: "RC",
          entityLinksCrdt: validSet,
        );
        expect(room.entityLinksCrdt, equals(validSet));

        // Constructor accepts valid CrdtOrSet via explicit legacy migration boundary
        final legacyOrSet = const CrdtOrSet<RoomEntityLink>.empty();
        final roomFromLegacy = RoomNodeState(
          roomId: "r1",
          roomCode: "RC",
          entityLinksCrdt: legacyOrSet,
        );
        expect(roomFromLegacy.entityLinksCrdt, isA<EntityLinkCrdtSet>());

        // copyWith rejects invalid non-null entityLinksCrdt
        expect(
          () => room.copyWith(entityLinksCrdt: "invalid_string"),
          throwsArgumentError,
        );
        expect(
          () => room.copyWith(entityLinksCrdt: null),
          throwsArgumentError,
        );

        // copyWith preserves current state when omitted
        final copied = room.copyWith(title: "New Title", titleTimestamp: const HybridLogicalClock(physicalTime: 10, logicalCounter: 0, nodeId: "n1"));
        expect(copied.entityLinksCrdt, equals(validSet));

        // Explicit converter
        final converted = EntityLinkCrdtSet.fromCrdtOrSet(legacyOrSet);
        expect(converted, isA<EntityLinkCrdtSet>());
      });

      test('P. Mutation sequence property tests with merge consistency over 100 transitions', () {
        for (int i = 0; i < 100; i++) {
          final t1 = (i * 10) + 1;
          final t2 = t1 + 2;
          final t3 = t2 + 2;
          final t4 = t3 + 2;
          final t5 = t4 + 2;

          final hlc1 = HybridLogicalClock(physicalTime: t1, logicalCounter: 0, nodeId: "n1");
          final hlc2 = HybridLogicalClock(physicalTime: t2, logicalCounter: 0, nodeId: "n2");
          final hlc3 = HybridLogicalClock(physicalTime: t3, logicalCounter: 0, nodeId: "n3");
          final hlc4 = HybridLogicalClock(physicalTime: t4, logicalCounter: 0, nodeId: "n4");
          final hlc5 = HybridLogicalClock(physicalTime: t5, logicalCounter: 0, nodeId: "n5");

          final l1 = RoomEntityLink(
            entityId: "link-prop",
            displayName: "Initial $t1",
            displayNameTimestamp: hlc1,
            incarnationTimestamp: hlc1,
          );

          // Replica A: create G1 -> edit G1
          var repA = const EntityLinkCrdtSet.empty().createOrReadd("link-prop", l1, hlc1);
          repA = repA.update("link-prop", l1.copyWith(displayName: "Edit A $t2", displayNameTimestamp: hlc2), hlc2);

          // Replica B: create G1 -> remove G1
          var repB = const EntityLinkCrdtSet.empty().createOrReadd("link-prop", l1, hlc1);
          repB = repB.remove("link-prop", hlc3);

          // Replica C: create G1 -> remove G1 -> readd G2
          var repC = const EntityLinkCrdtSet.empty().createOrReadd("link-prop", l1, hlc1);
          repC = repC.remove("link-prop", hlc3);
          final l2 = RoomEntityLink(
            entityId: "link-prop",
            displayName: "Readded G2 $t4",
            displayNameTimestamp: hlc4,
            incarnationTimestamp: hlc4,
          );
          repC = repC.createOrReadd("link-prop", l2, hlc4);
          if (i % 2 == 0) {
            repC = repC.update("link-prop", l2.copyWith(notes: "Notes G2 $t5", notesTimestamp: hlc5), hlc5);
          }

          // Merge consistency: Idempotence, Commutativity, Associativity
          expect(repA.merge(repA), equals(repA));
          expect(repB.merge(repB), equals(repB));
          expect(repC.merge(repC), equals(repC));

          expect(repA.merge(repB), equals(repB.merge(repA)));
          expect(repB.merge(repC), equals(repC.merge(repB)));
          expect(repA.merge(repC), equals(repC.merge(repA)));

          final abThenC = (repA.merge(repB)).merge(repC);
          final aThenBc = repA.merge(repB.merge(repC));
          final cbThenA = (repC.merge(repB)).merge(repA);
          final cThenBa = repC.merge(repB.merge(repA));

          expect(abThenC, equals(aThenBc));
          expect(abThenC, equals(cbThenA));
          expect(abThenC, equals(cThenBa));

          // In this history, G2 is the latest active incarnation
          expect(abThenC.items.containsKey("link-prop"), isTrue);
          expect(abThenC.items["link-prop"]!.value.incarnationTimestamp, equals(hlc4));
        }
      });
    });
  });
}
