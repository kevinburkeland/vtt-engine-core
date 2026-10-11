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
        entityLinksCrdt: baseRoom.entityLinksCrdt.add('goblin-1', link1, readdHlc),
      );
      final joinReadd = RoomNodeState.join(roomA, roomBReadd);
      expect(joinReadd.entityLinks.map((l) => l.entityId), contains('goblin-1'));
    });

    test('Party roster removal uses typed entityId and does not parse display prose', () {
      final base = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1')
          .copyWith(partyCharacterIds: ['cleric-1', 'fighter-1']);

      // Removal event with explicit typed entityId
      final removeEvent = PartyEvent(
        id: 'ev-rm-1',
        roomCode: 'RC-1',
        type: 'characterRemove',
        playerName: 'DM',
        details: 'The player for cleric-1 has retired their hero from the quest.',
        entityId: 'cleric-1',
        timestamp: DateTime.utc(2026, 1, 1),
      );

      // Unrelated event that mentions 'fighter-1' in prose but is not a deletion event for it
      final chatEvent = PartyEvent(
        id: 'ev-chat-1',
        roomCode: 'RC-1',
        type: 'info',
        playerName: 'DM',
        details: 'fighter-1 characterRemove rogue-1',
        timestamp: DateTime.utc(2026, 1, 1, 0, 1),
      );

      final pA = base.copyWith(changeLog: [removeEvent, chatEvent]);
      final pB = base; // Stale replica still containing cleric-1

      final joinAB = CampaignProfile.join(pA, pB);
      final joinBA = CampaignProfile.join(pB, pA);

      expect(joinAB, equals(joinBA));
      // cleric-1 was removed via typed entityId
      expect(joinAB.partyCharacterIds.contains('cleric-1'), isFalse);
      // fighter-1 was NOT removed despite prose containing 'characterRemove'
      expect(joinAB.partyCharacterIds, contains('fighter-1'));
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
        edition: 'dnd5e_2024',
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

      // Replica C removes 'cleric-1' via typed changelog event
      final repC = base.copyWith(
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

    test('Randomized Aggregate Law Tests over 100 deterministic iterations with deletions', () {
      final rng = Random(424242);

      for (var iter = 0; iter < 100; iter++) {
        final seed = rng.nextInt(1000000);
        final subRng = Random(seed);

        final linkBase = RoomEntityLink(entityId: 'link_base', displayName: 'Base Link');
        final base = CampaignProfile.raw(
          id: 'camp_test',
          name: 'Randomized Campaign',
          edition: const RulesetIdentifier('generic_tabletop'),
          createdAt: DateTime.utc(2026, 1, 1),
          lastPlayedAt: DateTime.utc(2026, 1, 1),
          roomState: RoomNodeState(
            roomId: 'room_test',
            roomCode: 'RC-TEST',
            title: 'Base Room',
            entityLinks: [linkBase],
            customProperties: {'seed': seed},
          ),
          notesRegister: const CrdtLwwRegister<String>(
            value: 'Genesis Notes',
            timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
          ),
          partyPurse: const PartyPurse.empty(),
          partyCharacterIds: const ['c_base', 'c_extra'],
          pinnedRuleIds: const {'base_rule', 'unpin_target'},
        );

        // Replica A unpins 'unpin_target' and unbinds 'link_base'
        final repA = ReplicaId('rep_a_$iter');
        final unpinHlc = HybridLogicalClock(physicalTime: 1100 + iter, logicalCounter: 1, nodeId: repA.value);
        var branchA = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('gold', subRng.nextInt(50) + 1, replicaId: repA),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes A $iter',
            timestamp: unpinHlc,
          ),
          pinnedRules: base.pinnedRules.remove('unpin_target', unpinHlc),
          partyCharacterIds: ['c_base', 'c_extra', 'c_a_$iter'],
          roomState: base.roomState.copyWith(
            entityLinksCrdt: base.roomState.entityLinksCrdt.remove('link_base', unpinHlc),
            customProperties: {'seed': seed, 'a_prop': iter},
          ),
        );

        // Replica B removes 'c_extra' via changelog
        final repB = ReplicaId('rep_b_$iter');
        var branchB = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('silver', subRng.nextInt(50) + 1, replicaId: repB),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes B $iter',
            timestamp: HybridLogicalClock(physicalTime: 1200 + iter, logicalCounter: 1, nodeId: repB.value),
          ),
          changeLog: [
            PartyEvent(
              id: 'ev_rm_$iter',
              roomCode: 'RC-TEST',
              type: 'characterRemove',
              playerName: 'B',
              details: 'Removed extra',
              entityId: 'c_extra',
              timestamp: DateTime.utc(2026, 1, 1, iter ~/ 60, iter % 60),
            ),
          ],
          partyCharacterIds: ['c_base', 'c_b_$iter'],
          roomState: base.roomState.copyWith(
            customProperties: {'seed': seed, 'b_prop': iter},
          ),
        );

        // Replica C adds a new rule and link
        final repC = ReplicaId('rep_c_$iter');
        final addHlc = HybridLogicalClock(physicalTime: 1300 + iter, logicalCounter: 1, nodeId: repC.value);
        final newLink = RoomEntityLink(entityId: 'link_c_$iter', displayName: 'Link C');
        var branchC = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('copper', subRng.nextInt(50) + 1, replicaId: repC),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes C $iter',
            timestamp: addHlc,
          ),
          pinnedRules: base.pinnedRules.add('rule_c_$iter', 'rule_c_$iter', addHlc),
          partyCharacterIds: ['c_base', 'c_c_$iter'],
          roomState: base.roomState.copyWith(
            entityLinksCrdt: base.roomState.entityLinksCrdt.add('link_c_$iter', newLink, addHlc),
            customProperties: {'seed': seed, 'c_prop': iter},
          ),
        );

        // 1. Idempotence: join(A, A) == A
        final idempA = CampaignProfile.join(branchA, branchA);
        expect(idempA, equals(branchA), reason: 'Idempotence failed at iter $iter with seed $seed');

        // 2. Commutativity: join(A, B) == join(B, A)
        final joinAB = CampaignProfile.join(branchA, branchB);
        final joinBA = CampaignProfile.join(branchB, branchA);
        expect(joinAB, equals(joinBA), reason: 'Commutativity failed at iter $iter with seed $seed');

        // 3. Associativity: join(join(A, B), C) == join(A, join(B, C))
        final joinAbThenC = CampaignProfile.join(joinAB, branchC);
        final joinBC = CampaignProfile.join(branchB, branchC);
        final joinAThenBc = CampaignProfile.join(branchA, joinBC);
        expect(joinAbThenC, equals(joinAThenBc), reason: 'Associativity failed at iter $iter with seed $seed');

        // Ensure intended deletions survived
        expect(joinAbThenC.pinnedRuleIds.contains('unpin_target'), isFalse);
        expect(joinAbThenC.partyCharacterIds.contains('c_extra'), isFalse);
        expect(joinAbThenC.roomState.entityLinks.map((l) => l.entityId).contains('link_base'), isFalse);
      }
    });
  });
}
