import 'dart:math';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/party_event.dart';
import 'package:vtt_engine_core/models/party_purse.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/rules/ruleset_edition.dart';
import 'package:test/test.dart';
import 'package:vtt_engine_core/models/value_objects/blob_ref.dart';
import 'package:vtt_engine_core/models/value_objects/map_grid.dart';

MapGrid _randomValidGrid(Random rng) {
  const hexChars = '0123456789abcdef';
  final sha = List.generate(64, (_) => hexChars[rng.nextInt(16)]).join();
  final cell = 1000 + rng.nextInt(51200 - 1000 + 1);
  final offX = rng.nextInt(cell);
  final offY = rng.nextInt(cell);
  final feet = 1 + rng.nextInt(100);
  final vis = rng.nextBool();
  return MapGrid(
    mapSha256Hex: sha,
    cellCentiPx: cell,
    offsetXCentiPx: offX,
    offsetYCentiPx: offY,
    feetPerCell: feet,
    visible: vis,
  );
}

BlobRef _randomValidRef(Random rng) {
  const hexChars = '0123456789abcdef';
  final sha = List.generate(64, (_) => hexChars[rng.nextInt(16)]).join();
  return BlobRef(
    sha256Hex: sha,
    byteSize: rng.nextInt(BlobRef.maxByteSize) + 1,
    width: rng.nextInt(BlobRef.maxLongestSidePx) + 1,
    height: rng.nextInt(BlobRef.maxLongestSidePx) + 1,
    format: rng.nextBool() ? BlobFormat.webp : BlobFormat.jpeg,
  );
}

void main() {
  group('Cold Iron Birdcage — Pass 4.1: Canonical Aggregate Join Laws', () {
    test('PartyEvent value identity and deterministic deserialization', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final event1 = PartyEvent(
        id: 'ev-1',
        roomCode: 'RC-100',
        type: 'coinDeposit',
        playerName: 'Alice',
        details: 'Deposited 50 GP',
        entityId: 'char-1',
        timestamp: now,
      );

      final map = event1.toMap();
      final event2 = PartyEvent.fromMap(map);

      expect(event2, equals(event1));
      expect(event2.hashCode, equals(event1.hashCode));
      expect(PartyEvent.fromJson(event1.toJson()), equals(event1));

      // Malformed timestamp fails loud
      expect(
        () => PartyEvent.fromMap({...map, 'timestamp': 'invalid-date'}),
        throwsA(isA<FormatException>()),
      );

      // Absent timestamp fails loud
      final absentMap = Map<String, dynamic>.from(map)..remove('timestamp');
      expect(
        () => PartyEvent.fromMap(absentMap),
        throwsA(isA<FormatException>()),
      );
    });

    test('CampaignProfile differing only in changeLog does not trigger early return and merges symmetrically', () {
      final base = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1');
      final evA = PartyEvent(
        id: 'ev-a',
        roomCode: 'RC-1',
        type: 'info',
        playerName: 'PlayerA',
        details: 'Event A',
        timestamp: DateTime.utc(2026, 1, 1, 10, 0),
      );
      final evB = PartyEvent(
        id: 'ev-b',
        roomCode: 'RC-1',
        type: 'info',
        playerName: 'PlayerB',
        details: 'Event B',
        timestamp: DateTime.utc(2026, 1, 1, 11, 0),
      );

      final pA = base.copyWith(changeLog: [evA]);
      final pB = base.copyWith(changeLog: [evB]);

      expect(pA == pB, isFalse);

      final joinAB = CampaignProfile.join(pA, pB);
      final joinBA = CampaignProfile.join(pB, pA);

      expect(joinAB, equals(joinBA));
      expect(joinAB.changeLog.length, equals(2));
      expect(joinAB.changeLog.map((e) => e.id), containsAll(['ev-a', 'ev-b']));
    });

    test('Identical event ID with divergent payload throws StateError in both directions', () {
      final base = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1');
      final ev1 = PartyEvent(
        id: 'ev-conflict',
        roomCode: 'RC-1',
        type: 'coinDeposit',
        playerName: 'Alice',
        details: '10 GP',
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final ev2 = PartyEvent(
        id: 'ev-conflict',
        roomCode: 'RC-1',
        type: 'coinDeposit',
        playerName: 'Bob', // Divergent payload
        details: '20 GP',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      final pA = base.copyWith(changeLog: [ev1]);
      final pB = base.copyWith(changeLog: [ev2]);

      expect(() => CampaignProfile.join(pA, pB), throwsA(isA<StateError>()));
      expect(() => CampaignProfile.join(pB, pA), throwsA(isA<StateError>()));
    });

    test('Pinned rule deletion via CrdtOrSet tombstone survives reconnection and does not resurrect', () {
      final base = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1')
          .copyWith(pinnedRuleIds: {'cover', 'flanking'});

      // Replica A unpins 'cover' at authoritative HLC
      const unpinHlc = HybridLogicalClock(physicalTime: 1000, logicalCounter: 1, nodeId: 'nodeA');
      final pA = base.copyWith(
        pinnedRules: base.pinnedRules.remove('cover', unpinHlc),
      );

      // Replica B remains offline with stale 'cover' (genesis timestamp)
      final pB = base;

      final joinAB = CampaignProfile.join(pA, pB);
      final joinBA = CampaignProfile.join(pB, pA);

      expect(joinAB, equals(joinBA));
      expect(joinAB.pinnedRuleIds, contains('flanking'));
      expect(joinAB.pinnedRuleIds.contains('cover'), isFalse);

      // Concurrent re-add with newer HLC than tombstone: ADD WINS
      const readdHlc = HybridLogicalClock(physicalTime: 1100, logicalCounter: 1, nodeId: 'nodeB');
      final pBReadd = base.copyWith(
        pinnedRules: base.pinnedRules.add('cover', 'cover', readdHlc),
      );
      final joinReadd = CampaignProfile.join(pA, pBReadd);
      expect(joinReadd.pinnedRuleIds, contains('cover'));
    });

    test('Entity link unbind via CrdtOrSet tombstone survives reconnection and does not resurrect', () {
      final link1 = RoomEntityLink(entityId: 'goblin-1', displayName: 'Goblin Scout');
      final link2 = RoomEntityLink(entityId: 'goblin-2', displayName: 'Goblin Archer');
      final baseRoom = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-1',
        title: 'Cave',
        entityLinks: [link1, link2],
      );

      // Replica A unbinds 'goblin-1' at authoritative HLC
      const unbindHlc = HybridLogicalClock(physicalTime: 1000, logicalCounter: 1, nodeId: 'nodeA');
      final roomA = baseRoom.copyWith(
        entityLinksCrdt: baseRoom.entityLinksCrdt.remove('goblin-1', unbindHlc),
      );

      // Replica B remains offline with stale goblin-1
      final roomB = baseRoom;

      final joinAB = RoomNodeState.join(roomA, roomB);
      final joinBA = RoomNodeState.join(roomB, roomA);

      expect(joinAB, equals(joinBA));
      expect(joinAB.entityLinks.map((l) => l.entityId), contains('goblin-2'));
      expect(joinAB.entityLinks.map((l) => l.entityId).contains('goblin-1'), isFalse);

      // Concurrent re-add with newer HLC than tombstone: ADD WINS
      const readdHlc = HybridLogicalClock(physicalTime: 1200, logicalCounter: 1, nodeId: 'nodeB');
      final roomBReadd = baseRoom.copyWith(
        entityLinksCrdt: baseRoom.entityLinksCrdt.createOrReadd('goblin-1', link1, readdHlc),
      );
      final joinReadd = RoomNodeState.join(roomA, roomBReadd);
      expect(joinReadd.entityLinks.map((l) => l.entityId), contains('goblin-1'));
    });

    test('Party roster removal uses CRDT tombstone, preserves audit events, and allows intentional re-add', () {
      final base = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1')
          .copyWith(partyCharacterIds: ['cleric-1', 'fighter-1']);

      const rmTs = HybridLogicalClock(physicalTime: 100, logicalCounter: 0, nodeId: 'nodeA');
      final removeEvent = PartyEvent(
        id: 'ev-rm-1',
        roomCode: 'RC-1',
        type: 'characterRemove',
        playerName: 'DM',
        details: 'The player for cleric-1 has retired their hero from the quest.',
        entityId: 'cleric-1',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      final pA = base.copyWith(
        partyRoster: base.partyRoster.remove('cleric-1', rmTs),
        changeLog: [removeEvent],
      );
      final pB = base; // Stale replica still containing cleric-1

      final joinAB = CampaignProfile.join(pA, pB);
      final joinBA = CampaignProfile.join(pB, pA);

      expect(joinAB, equals(joinBA));
      // cleric-1 was removed via tombstone
      expect(joinAB.partyCharacterIds.contains('cleric-1'), isFalse);
      expect(joinAB.partyCharacterIds, contains('fighter-1'));

      // Later intentional re-add at newer HLC
      const readdTs = HybridLogicalClock(physicalTime: 200, logicalCounter: 0, nodeId: 'nodeA');
      final pAReadd = joinAB.copyWith(
        partyRoster: joinAB.partyRoster.add('cleric-1', 'cleric-1', readdTs),
      );
      final joinReadd = CampaignProfile.join(pAReadd, pB);
      expect(joinReadd.partyCharacterIds, contains('cleric-1'),
          reason: 'Intentional re-add must succeed over stale replica and historical tombstone');
    });

    test('Edition canonicalization produces direction-independent representation', () {
      final pA = CampaignProfile.initial(
        id: 'camp_1',
        name: 'Expedition',
        edition: const RulesetIdentifier('dnd5e_2024'),
        nodeId: 'n1',
      );
      final pB = CampaignProfile.initial(
        id: 'camp_1',
        name: 'Expedition',
        edition: const RulesetIdentifier('dnd5e_2024'),
        nodeId: 'n1',
      );

      expect(pA.rulesetId, equals(pB.rulesetId));
      final joinAB = CampaignProfile.join(pA, pB);
      final joinBA = CampaignProfile.join(pB, pA);

      expect(joinAB, equals(joinBA));
      expect(joinAB.edition, equals(joinBA.edition));
    });

    test('Three-replica delete and reconnect scenario converges with all deletions preserved', () {
      final link1 = RoomEntityLink(entityId: 'goblin-1', displayName: 'Goblin');
      final base = CampaignProfile.raw(
        id: 'camp_multi',
        name: 'Dungeon Run',
        edition: const RulesetIdentifier('generic_tabletop'),
        createdAt: DateTime.utc(2026, 1, 1),
        lastPlayedAt: DateTime.utc(2026, 1, 1),
        roomState: RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC-1',
          title: 'Room',
          entityLinks: [link1],
        ),
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Start notes',
          timestamp: HybridLogicalClock(physicalTime: 100, logicalCounter: 0, nodeId: 'genesis'),
        ),
        partyPurse: const PartyPurse.empty(),
        partyCharacterIds: const ['cleric-1', 'wizard-1'],
        pinnedRuleIds: const {'cover', 'stealth'},
      );

      // Replica A unpins 'cover'
      final repA = base.copyWith(
        pinnedRules: base.pinnedRules.remove(
          'cover',
          const HybridLogicalClock(physicalTime: 200, logicalCounter: 1, nodeId: 'nodeA'),
        ),
      );

      // Replica B unbinds 'goblin-1'
      final repB = base.copyWith(
        roomState: base.roomState.copyWith(
          entityLinksCrdt: base.roomState.entityLinksCrdt.remove(
            'goblin-1',
            const HybridLogicalClock(physicalTime: 300, logicalCounter: 1, nodeId: 'nodeB'),
          ),
        ),
      );

      // Replica C removes 'cleric-1' via roster tombstone
      final repC = base.copyWith(
        partyRoster: base.partyRoster.remove(
          'cleric-1',
          const HybridLogicalClock(physicalTime: 400, logicalCounter: 1, nodeId: 'nodeC'),
        ),
        changeLog: [
          PartyEvent(
            id: 'ev-rm-cleric',
            roomCode: 'RC-1',
            type: 'characterRemove',
            playerName: 'DM',
            details: 'Cleric dismissed',
            entityId: 'cleric-1',
            timestamp: DateTime.utc(2026, 1, 1, 12, 0),
          ),
        ],
      );

      // Merge in order (A + B) + C
      final joinAbThenC = CampaignProfile.join(CampaignProfile.join(repA, repB), repC);

      // Merge in order (C + B) + A
      final joinCbThenA = CampaignProfile.join(CampaignProfile.join(repC, repB), repA);

      // Merge in order (A + C) + B
      final joinAcThenB = CampaignProfile.join(CampaignProfile.join(repA, repC), repB);

      expect(joinAbThenC, equals(joinCbThenA));
      expect(joinAbThenC, equals(joinAcThenB));

      // Assert all intended deletions are preserved:
      expect(joinAbThenC.pinnedRuleIds.contains('cover'), isFalse);
      expect(joinAbThenC.pinnedRuleIds, contains('stealth'));
      expect(joinAbThenC.roomState.entityLinks.map((l) => l.entityId).contains('goblin-1'), isFalse);
      expect(joinAbThenC.partyCharacterIds.contains('cleric-1'), isFalse);
      expect(joinAbThenC.partyCharacterIds, contains('wizard-1'));
    });

    test('Randomized Aggregate Law Tests over 100 deterministic iterations with deletions and scalar mutations', () {
      final rng = Random(424242);

      for (var iter = 0; iter < 100; iter++) {
        final seed = rng.nextInt(1000000);
        final subRng = Random(seed);

        final linkBase = RoomEntityLink(
          entityId: 'link_base',
          displayName: 'Base Link',
          notes: 'Genesis Link Notes',
          notesTimestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
        );
        final base = CampaignProfile.raw(
          id: 'camp_test',
          name: 'Randomized Campaign',
          nameTimestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
          edition: const RulesetIdentifier('generic_tabletop'),
          createdAt: DateTime.utc(2026, 1, 1),
          lastPlayedAt: DateTime.utc(2026, 1, 1),
          roomState: RoomNodeState(
            roomId: 'room_test',
            roomCode: 'RC-TEST',
            title: 'Base Room',
            titleTimestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
            description: 'Base Description',
            descriptionTimestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
            entityLinks: [linkBase],
            customProperties: {'seed': seed},
          ),
          notesRegister: const CrdtLwwRegister<String>(
            value: 'Genesis Notes',
            timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
          ),
          partyPurse: const PartyPurse.empty(),
          memberPurses: {
            'c_base': const PartyPurse.empty().modifyDenomination('gold', 10, replicaId: ReplicaId('genesis')),
          },
          partyCharacterIds: const ['c_base', 'c_extra'],
          pinnedRuleIds: const {'base_rule', 'unpin_target'},
        );

        // Replica A unpins 'unpin_target' and unbinds 'link_base', may mutate name, title, description
        final repA = ReplicaId('rep_a_');
        final unpinHlc = HybridLogicalClock(physicalTime: 1100 + iter, logicalCounter: 1, nodeId: repA.value);
        final mutateNameA = subRng.nextBool();
        final mutateTitleA = subRng.nextBool();
        final mutateDescA = subRng.nextBool();

        ({BlobRef? ref, HybridLogicalClock timestamp})? latestMapWrite;

        void recordWrite(BlobRef? ref, HybridLogicalClock ts) {
          final current = latestMapWrite;
          if (current == null || ts.isAfter(current.timestamp)) {
            latestMapWrite = (ref: ref, timestamp: ts);
          }
        }

        ({MapGrid? grid, HybridLogicalClock timestamp})? latestGridWrite;

        void recordGridWrite(MapGrid? grid, HybridLogicalClock ts) {
          final current = latestGridWrite;
          if (current == null || ts.isAfter(current.timestamp)) {
            latestGridWrite = (grid: grid, timestamp: ts);
          }
        }

        var branchA = base.copyWith(
          name: mutateNameA ? 'Campaign A ' : base.name,
          nameTimestamp: mutateNameA ? unpinHlc : base.nameRegister.timestamp,
          partyPurse: base.partyPurse.modifyDenomination('gold', subRng.nextInt(50) + 1, replicaId: repA),
          memberPurses: {
            'c_base': base.memberPurses['c_base']!.modifyDenomination('gold', subRng.nextInt(30) + 1, replicaId: repA),
            'c_a_': const PartyPurse.empty().modifyDenomination('silver', 5, replicaId: repA),
          },
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes A ',
            timestamp: unpinHlc,
          ),
          pinnedRules: base.pinnedRules.remove('unpin_target', unpinHlc),
          partyRoster: base.partyRoster.add('c_a_', 'c_a_', unpinHlc),
          roomState: base.roomState.copyWith(
            title: mutateTitleA ? 'Room Title A ' : base.roomState.title,
            titleTimestamp: mutateTitleA ? unpinHlc : base.roomState.titleRegister.timestamp,
            description: mutateDescA ? 'Room Desc A ' : base.roomState.description,
            descriptionTimestamp: mutateDescA ? unpinHlc : base.roomState.descriptionRegister.timestamp,
            entityLinksCrdt: base.roomState.entityLinksCrdt.remove('link_base', unpinHlc),
            customProperties: {'seed': seed, 'a_prop': iter},
          ),
        );

        final mapActionA = subRng.nextInt(3);
        if (mapActionA == 1) {
          final refA = _randomValidRef(subRng);
          branchA = branchA.withActiveMap(refA, unpinHlc);
          recordWrite(refA, unpinHlc);
        } else if (mapActionA == 2) {
          final refA = _randomValidRef(subRng);
          final clearHlcA = HybridLogicalClock(
            physicalTime: unpinHlc.physicalTime + 10,
            logicalCounter: 1,
            nodeId: repA.value,
          );
          branchA = branchA.withActiveMap(refA, unpinHlc).withActiveMap(null, clearHlcA);
          recordWrite(null, clearHlcA);
        }

        final gridActionA = subRng.nextInt(3);
        if (gridActionA == 1) {
          final gridA = _randomValidGrid(subRng);
          branchA = branchA.withMapGrid(gridA, unpinHlc);
          recordGridWrite(gridA, unpinHlc);
        } else if (gridActionA == 2) {
          final gridA = _randomValidGrid(subRng);
          final clearGridHlcA = HybridLogicalClock(
            physicalTime: unpinHlc.physicalTime + 20,
            logicalCounter: 1,
            nodeId: repA.value,
          );
          branchA = branchA.withMapGrid(gridA, unpinHlc).withMapGrid(null, clearGridHlcA);
          recordGridWrite(null, clearGridHlcA);
        }

        // Replica B removes 'c_extra' via changelog, may mutate name, title, description
        final repB = ReplicaId('rep_b_');
        final hlcB = HybridLogicalClock(physicalTime: 1200 + iter, logicalCounter: 1, nodeId: repB.value);
        final mutateNameB = subRng.nextBool();
        final mutateTitleB = subRng.nextBool();
        final mutateDescB = subRng.nextBool();

        var branchB = base.copyWith(
          name: mutateNameB ? 'Campaign B ' : base.name,
          nameTimestamp: mutateNameB ? hlcB : base.nameRegister.timestamp,
          partyPurse: base.partyPurse.modifyDenomination('silver', subRng.nextInt(50) + 1, replicaId: repB),
          memberPurses: {
            'c_base': base.memberPurses['c_base']!.modifyDenomination('gold', subRng.nextInt(30) + 1, replicaId: repB),
            'c_b_': const PartyPurse.empty().modifyDenomination('copper', 12, replicaId: repB),
          },
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes B ',
            timestamp: hlcB,
          ),
          changeLog: [
            PartyEvent(
              id: 'ev_rm_',
              roomCode: 'RC-TEST',
              type: 'characterRemove',
              playerName: 'B',
              details: 'Removed extra',
              entityId: 'c_extra',
              timestamp: DateTime.utc(2026, 1, 1, iter ~/ 60, iter % 60),
            ),
          ],
          partyRoster: base.partyRoster.remove('c_extra', hlcB).add('c_b_', 'c_b_', hlcB),
          roomState: base.roomState.copyWith(
            title: mutateTitleB ? 'Room Title B ' : base.roomState.title,
            titleTimestamp: mutateTitleB ? hlcB : base.roomState.titleRegister.timestamp,
            description: mutateDescB ? 'Room Desc B ' : base.roomState.description,
            descriptionTimestamp: mutateDescB ? hlcB : base.roomState.descriptionRegister.timestamp,
            customProperties: {'seed': seed, 'b_prop': iter},
          ),
        );

        final mapActionB = subRng.nextInt(3);
        if (mapActionB == 1) {
          final refB = _randomValidRef(subRng);
          branchB = branchB.withActiveMap(refB, hlcB);
          recordWrite(refB, hlcB);
        } else if (mapActionB == 2) {
          final refB = _randomValidRef(subRng);
          final clearHlcB = HybridLogicalClock(
            physicalTime: hlcB.physicalTime + 10,
            logicalCounter: 1,
            nodeId: repB.value,
          );
          branchB = branchB.withActiveMap(refB, hlcB).withActiveMap(null, clearHlcB);
          recordWrite(null, clearHlcB);
        }

        final gridActionB = subRng.nextInt(3);
        if (gridActionB == 1) {
          final gridB = _randomValidGrid(subRng);
          branchB = branchB.withMapGrid(gridB, hlcB);
          recordGridWrite(gridB, hlcB);
        } else if (gridActionB == 2) {
          final gridB = _randomValidGrid(subRng);
          final clearGridHlcB = HybridLogicalClock(
            physicalTime: hlcB.physicalTime + 20,
            logicalCounter: 1,
            nodeId: repB.value,
          );
          branchB = branchB.withMapGrid(gridB, hlcB).withMapGrid(null, clearGridHlcB);
          recordGridWrite(null, clearGridHlcB);
        }

        // Replica C adds a new rule and link, may mutate name, title, description
        final repC = ReplicaId('rep_c_');
        final addHlc = HybridLogicalClock(physicalTime: 1300 + iter, logicalCounter: 1, nodeId: repC.value);
        final newLink = RoomEntityLink(
          entityId: 'link_c_',
          displayName: 'Link C',
          notes: 'Notes C ',
          notesTimestamp: addHlc,
        );
        final mutateNameC = subRng.nextBool();
        final mutateTitleC = subRng.nextBool();
        final mutateDescC = subRng.nextBool();

        var branchC = base.copyWith(
          name: mutateNameC ? 'Campaign C ' : base.name,
          nameTimestamp: mutateNameC ? addHlc : base.nameRegister.timestamp,
          partyPurse: base.partyPurse.modifyDenomination('copper', subRng.nextInt(50) + 1, replicaId: repC),
          memberPurses: {
            'c_base': base.memberPurses['c_base']!.modifyDenomination('silver', subRng.nextInt(30) + 1, replicaId: repC),
            'c_c_': const PartyPurse.empty().modifyDenomination('platinum', 2, replicaId: repC),
          },
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes C ',
            timestamp: addHlc,
          ),
          pinnedRules: base.pinnedRules.add('rule_c_', 'rule_c_', addHlc),
          partyRoster: base.partyRoster.add('c_c_', 'c_c_', addHlc),
          roomState: base.roomState.copyWith(
            title: mutateTitleC ? 'Room Title C ' : base.roomState.title,
            titleTimestamp: mutateTitleC ? addHlc : base.roomState.titleRegister.timestamp,
            description: mutateDescC ? 'Room Desc C ' : base.roomState.description,
            descriptionTimestamp: mutateDescC ? addHlc : base.roomState.descriptionRegister.timestamp,
            entityLinksCrdt: base.roomState.entityLinksCrdt.add('link_c_', newLink, addHlc),
            customProperties: {'seed': seed, 'c_prop': iter},
          ),
        );

        final mapActionC = subRng.nextInt(3);
        if (mapActionC == 1) {
          final refC = _randomValidRef(subRng);
          branchC = branchC.withActiveMap(refC, addHlc);
          recordWrite(refC, addHlc);
        } else if (mapActionC == 2) {
          final refC = _randomValidRef(subRng);
          final clearHlcC = HybridLogicalClock(
            physicalTime: addHlc.physicalTime + 10,
            logicalCounter: 1,
            nodeId: repC.value,
          );
          branchC = branchC.withActiveMap(refC, addHlc).withActiveMap(null, clearHlcC);
          recordWrite(null, clearHlcC);
        }

        final gridActionC = subRng.nextInt(3);
        if (gridActionC == 1) {
          final gridC = _randomValidGrid(subRng);
          branchC = branchC.withMapGrid(gridC, addHlc);
          recordGridWrite(gridC, addHlc);
        } else if (gridActionC == 2) {
          final gridC = _randomValidGrid(subRng);
          final clearGridHlcC = HybridLogicalClock(
            physicalTime: addHlc.physicalTime + 20,
            logicalCounter: 1,
            nodeId: repC.value,
          );
          branchC = branchC.withMapGrid(gridC, addHlc).withMapGrid(null, clearGridHlcC);
          recordGridWrite(null, clearGridHlcC);
        }

        // 1. Idempotence: join(A, A) == A
        final idempA = CampaignProfile.join(branchA, branchA);
        expect(idempA, equals(branchA), reason: 'Idempotence failed at iter  with seed ');

        // 2. Commutativity: join(A, B) == join(B, A)
        final joinAB = CampaignProfile.join(branchA, branchB);
        final joinBA = CampaignProfile.join(branchB, branchA);
        expect(joinAB, equals(joinBA), reason: 'Commutativity failed at iter  with seed ');

        // Repeated join convergence
        final repeatedJoinAB = CampaignProfile.join(joinAB, branchB);
        expect(repeatedJoinAB, equals(joinAB), reason: 'Repeated join idempotence failed at iter ');

        // 3. Associativity: join(join(A, B), C) == join(A, join(B, C))
        final joinAbThenC = CampaignProfile.join(joinAB, branchC);
        final joinBC = CampaignProfile.join(branchB, branchC);
        final joinAThenBc = CampaignProfile.join(branchA, joinBC);
        expect(joinAbThenC, equals(joinAThenBc), reason: 'Associativity failed at iter  with seed ');

        // Reconnection permutations: (B+C)+A and (C+A)+B must converge identically
        final joinCaThenB = CampaignProfile.join(CampaignProfile.join(branchC, branchA), branchB);
        final joinBcThenA = CampaignProfile.join(joinBC, branchA);
        expect(joinCaThenB, equals(joinAbThenC), reason: 'Reconnection permutation (C+A)+B failed at iter ');
        expect(joinBcThenA, equals(joinAbThenC), reason: 'Reconnection permutation (B+C)+A failed at iter ');

        // Verify single-writer / LWW propagation for scalar fields:
        // C has highest HLC (1300 + iter), then B (1200 + iter), then A (1100 + iter).
        if (mutateNameC) {
          expect(joinAbThenC.name, equals('Campaign C '));
        } else if (mutateNameB) {
          expect(joinAbThenC.name, equals('Campaign B '));
        } else if (mutateNameA) {
          expect(joinAbThenC.name, equals('Campaign A '));
        } else {
          expect(joinAbThenC.name, equals(base.name));
        }

        if (mutateTitleC) {
          expect(joinAbThenC.roomState.title, equals('Room Title C '));
        } else if (mutateTitleB) {
          expect(joinAbThenC.roomState.title, equals('Room Title B '));
        } else if (mutateTitleA) {
          expect(joinAbThenC.roomState.title, equals('Room Title A '));
        } else {
          expect(joinAbThenC.roomState.title, equals(base.roomState.title));
        }

        if (mutateDescC) {
          expect(joinAbThenC.roomState.description, equals('Room Desc C '));
        } else if (mutateDescB) {
          expect(joinAbThenC.roomState.description, equals('Room Desc B '));
        } else if (mutateDescA) {
          expect(joinAbThenC.roomState.description, equals('Room Desc A '));
        } else {
          expect(joinAbThenC.roomState.description, equals(base.roomState.description));
        }

        // Ensure intended deletions survived
        expect(joinAbThenC.pinnedRuleIds.contains('unpin_target'), isFalse);
        expect(joinAbThenC.partyCharacterIds.contains('c_extra'), isFalse);
        expect(joinAbThenC.roomState.entityLinks.map((l) => l.entityId).contains('link_base'), isFalse);

        // L1: assert joined map equals branch write with greatest timestamp (or null if none wrote)
        expect(joinAbThenC.activeMap, equals(latestMapWrite?.ref));
        expect(joinAbThenC.mapGrid, equals(latestGridWrite?.grid));
      }
    });
  });
}
