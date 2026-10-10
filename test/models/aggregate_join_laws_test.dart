import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/models/party_purse.dart';
import 'package:vtt_engine_core/rules/ruleset_edition.dart';

void main() {
  group('Cold Iron Birdcage — Pass 4.0: Canonical Aggregate Join Laws', () {
    test('Idempotence: join(A, A) == A for RoomNodeState and CampaignProfile', () {
      final room = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-101',
        title: 'Ancient Crypt',
        description: 'Dusty stone walls with ancient carvings.',
        customProperties: {'lightLevel': 'dim', 'danger': 3},
      );
      final profile = CampaignProfile.raw(
        id: 'camp_1',
        name: 'The Lost Expedition',
        edition: const RulesetIdentifier('generic_tabletop'),
        createdAt: DateTime.utc(2026, 1, 1),
        lastPlayedAt: DateTime.utc(2026, 3, 1),
        roomState: room,
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Found an iron key in the wall.',
          timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
        ),
        partyPurse: const PartyPurse.empty().modifyDenomination('gold', 50, replicaId: ReplicaId('node_1')),
        partyCharacterIds: const ['c1', 'c2'],
        pinnedRuleIds: const {'cover', 'resting'},
      );

      expect(RoomNodeState.join(room, room), equals(room));
      expect(room.merge(room), equals(room));
      expect(CampaignProfile.join(profile, profile), equals(profile));
      expect(profile.merge(profile), equals(profile));
    });

    test('Commutativity: join(A, B) == join(B, A) across valid independent updates', () {
      final baseRoom = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-101',
        title: 'Ancient Crypt',
        description: 'Dusty stone walls.',
        customProperties: const {'baseProp': 'value'},
      );

      final enc1 = EncounterParticipant(
        participantId: 'p1',
        entityLink: RoomEntityLink(entityId: 'e1', displayName: 'Guard'),
      );
      final enc2 = EncounterParticipant(
        participantId: 'p2',
        entityLink: RoomEntityLink(entityId: 'e2', displayName: 'Archer'),
      );

      final roomA = baseRoom.copyWith(
        activeEncounter: const CrdtOrSet<EncounterParticipant>.empty().add(
          'p1',
          enc1,
          const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'replica_a'),
        ),
        customProperties: {'baseProp': 'value', 'a_discovered': true},
      );

      final roomB = baseRoom.copyWith(
        activeEncounter: const CrdtOrSet<EncounterParticipant>.empty().add(
          'p2',
          enc2,
          const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'replica_b'),
        ),
        customProperties: {'baseProp': 'value', 'b_discovered': false},
      );

      final joinAB = RoomNodeState.join(roomA, roomB);
      final joinBA = RoomNodeState.join(roomB, roomA);

      expect(joinAB, equals(joinBA));
      expect(joinAB.hashCode, equals(joinBA.hashCode));
      expect(joinAB.customProperties, equals({'a_discovered': true, 'b_discovered': false, 'baseProp': 'value'}));
      expect(joinAB.activeEncounter.activeValues.length, equals(2));
    });

    test('Associativity: join(join(A, B), C) == join(A, join(B, C)) across 3 branches', () {
      final baseProfile = CampaignProfile.raw(
        id: 'camp_1',
        name: 'The Lost Expedition',
        edition: const RulesetIdentifier('generic_tabletop'),
        createdAt: DateTime.utc(2026, 1, 1),
        lastPlayedAt: DateTime.utc(2026, 1, 1),
        roomState: RoomNodeState(roomId: 'r1', roomCode: 'RC-101', title: 'Crypt'),
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Base notes',
          timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
        ),
        partyPurse: const PartyPurse.empty(),
        partyCharacterIds: const ['c1'],
        pinnedRuleIds: const {'cover'},
      );

      // Branch A: updates notes at T=1500, adds character c2
      final profA = baseProfile.copyWith(
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Branch A notes',
          timestamp: HybridLogicalClock(physicalTime: 1500, logicalCounter: 0, nodeId: 'rep_a'),
        ),
        partyCharacterIds: const ['c1', 'c2'],
        partyPurse: baseProfile.partyPurse.modifyDenomination('gold', 100, replicaId: ReplicaId('rep_a')),
      );

      // Branch B: deposits SP, pins 'resting'
      final profB = baseProfile.copyWith(
        pinnedRuleIds: const {'cover', 'resting'},
        partyPurse: baseProfile.partyPurse.modifyDenomination('silver', 50, replicaId: ReplicaId('rep_b')),
      );

      // Branch C: updates notes at T=2000 (wins LWW), adds character c3
      final profC = baseProfile.copyWith(
        notesRegister: const CrdtLwwRegister<String>(
          value: 'Branch C notes (final)',
          timestamp: HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'rep_c'),
        ),
        partyCharacterIds: const ['c1', 'c3'],
        partyPurse: baseProfile.partyPurse.modifyDenomination('gold', 25, replicaId: ReplicaId('rep_c')),
      );

      final abThenC = CampaignProfile.join(CampaignProfile.join(profA, profB), profC);
      final aThenBc = CampaignProfile.join(profA, CampaignProfile.join(profB, profC));

      expect(abThenC, equals(aThenBc));
      expect(abThenC.notesMarkdown, equals('Branch C notes (final)'));
      expect(abThenC.partyPurse.getBalance('gold'), equals(125));
      expect(abThenC.partyPurse.getBalance('silver'), equals(50));
      expect(abThenC.partyCharacterIds, equals(['c1', 'c2', 'c3']));
      expect(abThenC.pinnedRuleIds, equals({'cover', 'resting'}));
    });

    test('Input Immutability: join does not mutate input instances or collections', () {
      final customPropsA = {'keyA': 'valA', 'shared': 1};
      final customPropsB = {'keyB': 'valB', 'shared': 1};

      final roomA = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-101',
        title: 'Crypt',
        customProperties: customPropsA,
      );
      final roomB = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-101',
        title: 'Crypt',
        customProperties: customPropsB,
      );

      final preAProps = Map.from(roomA.customProperties);
      final preBProps = Map.from(roomB.customProperties);

      final merged = RoomNodeState.join(roomA, roomB);

      expect(roomA.customProperties, equals(preAProps));
      expect(roomB.customProperties, equals(preBProps));
      expect(merged.customProperties.containsKey('keyA'), isTrue);
      expect(merged.customProperties.containsKey('keyB'), isTrue);
    });

    group('Symmetric Failure on Invalid State', () {
      test('Immutable ID disagreement throws StateError symmetrically', () {
        final rA = RoomNodeState(roomId: 'r1', roomCode: 'RC-1', title: 'A');
        final rB = RoomNodeState(roomId: 'r2', roomCode: 'RC-1', title: 'A');

        expect(() => RoomNodeState.join(rA, rB), throwsA(isA<StateError>()));
        expect(() => RoomNodeState.join(rB, rA), throwsA(isA<StateError>()));

        final pA = CampaignProfile.initial(id: 'camp_1', name: 'Name', nodeId: 'n1');
        final pB = CampaignProfile.initial(id: 'camp_2', name: 'Name', nodeId: 'n1');

        expect(() => CampaignProfile.join(pA, pB), throwsA(isA<StateError>()));
        expect(() => CampaignProfile.join(pB, pA), throwsA(isA<StateError>()));
      });

      test('Ruleset Edition disagreement throws StateError symmetrically', () {
        final pA = CampaignProfile.initial(
          id: 'camp_1',
          name: 'Name',
          rulesetId: 'ruleset_alpha',
          nodeId: 'n1',
        );
        final pB = CampaignProfile.initial(
          id: 'camp_1',
          name: 'Name',
          rulesetId: 'ruleset_beta',
          nodeId: 'n1',
        );

        expect(() => CampaignProfile.join(pA, pB), throwsA(isA<StateError>()));
        expect(() => CampaignProfile.join(pB, pA), throwsA(isA<StateError>()));
      });

      test('Divergent unversioned scalar throws StateError symmetrically', () {
        final rA = RoomNodeState(roomId: 'r1', roomCode: 'RC-1', title: 'Dungeon Alpha');
        final rB = RoomNodeState(roomId: 'r1', roomCode: 'RC-1', title: 'Dungeon Beta');

        expect(() => RoomNodeState.join(rA, rB), throwsA(isA<StateError>()));
        expect(() => RoomNodeState.join(rB, rA), throwsA(isA<StateError>()));

        final pA = CampaignProfile.initial(id: 'camp_1', name: 'Alpha Expedition', nodeId: 'n1');
        final pB = CampaignProfile.initial(id: 'camp_1', name: 'Beta Expedition', nodeId: 'n1');

        expect(() => CampaignProfile.join(pA, pB), throwsA(isA<StateError>()));
        expect(() => CampaignProfile.join(pB, pA), throwsA(isA<StateError>()));
      });

      test('customProperties same-key divergent value throws StateError symmetrically', () {
        final rA = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC-1',
          title: 'Room',
          customProperties: {'weather': 'rainy'},
        );
        final rB = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC-1',
          title: 'Room',
          customProperties: {'weather': 'sunny'},
        );

        expect(() => RoomNodeState.join(rA, rB), throwsA(isA<StateError>()));
        expect(() => RoomNodeState.join(rB, rA), throwsA(isA<StateError>()));
      });

      test('Exact-HLC divergent LWW notes payload throws StateError symmetrically', () {
        const exactHlc = HybridLogicalClock(physicalTime: 5000, logicalCounter: 1, nodeId: 'n1');
        final pA = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1').copyWith(
          notesRegister: const CrdtLwwRegister<String>(value: 'Payload A', timestamp: exactHlc),
        );
        final pB = CampaignProfile.initial(id: 'camp_1', name: 'Campaign', nodeId: 'n1').copyWith(
          notesRegister: const CrdtLwwRegister<String>(value: 'Payload B', timestamp: exactHlc),
        );

        expect(() => CampaignProfile.join(pA, pB), throwsA(isA<StateError>()));
        expect(() => CampaignProfile.join(pB, pA), throwsA(isA<StateError>()));
      });

      test('Exact-HLC divergent OR-Set participant payload throws StateError symmetrically', () {
        const exactHlc = HybridLogicalClock(physicalTime: 5000, logicalCounter: 1, nodeId: 'n1');
        final p1 = EncounterParticipant(
          participantId: 'p1',
          entityLink: RoomEntityLink(entityId: 'e1', displayName: 'Paladin'),
          currentHp: 20,
        );
        final p2 = EncounterParticipant(
          participantId: 'p1',
          entityLink: RoomEntityLink(entityId: 'e1', displayName: 'Paladin'),
          currentHp: 10, // Divergent HP payload at exact same HLC
        );

        final rA = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC-1',
          title: 'Room',
          activeEncounter: const CrdtOrSet<EncounterParticipant>.empty().add('p1', p1, exactHlc),
        );
        final rB = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC-1',
          title: 'Room',
          activeEncounter: const CrdtOrSet<EncounterParticipant>.empty().add('p1', p2, exactHlc),
        );

        expect(() => RoomNodeState.join(rA, rB), throwsA(isA<StateError>()));
        expect(() => RoomNodeState.join(rB, rA), throwsA(isA<StateError>()));
      });
    });

    test('Randomized Aggregate Law Tests over 100 deterministic iterations', () {
      final rng = Random(424242);

      for (var iter = 0; iter < 100; iter++) {
        final seed = rng.nextInt(1000000);
        final subRng = Random(seed);

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
            customProperties: {'seed': seed},
          ),
          notesRegister: const CrdtLwwRegister<String>(
            value: 'Genesis Notes',
            timestamp: HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'genesis'),
          ),
          partyPurse: const PartyPurse.empty(),
          partyCharacterIds: const ['c_base'],
          pinnedRuleIds: const {'base_rule'},
        );

        // Fork replica A
        final repA = ReplicaId('rep_a_$iter');
        var branchA = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('gold', subRng.nextInt(50) + 1, replicaId: repA),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes A $iter',
            timestamp: HybridLogicalClock(physicalTime: 1100 + iter, logicalCounter: 1, nodeId: repA.value),
          ),
          pinnedRuleIds: {'base_rule', 'rule_a_$iter'},
          partyCharacterIds: ['c_base', 'c_a_$iter'],
          roomState: base.roomState.copyWith(
            customProperties: {'seed': seed, 'a_prop': iter},
          ),
        );

        // Fork replica B
        final repB = ReplicaId('rep_b_$iter');
        var branchB = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('silver', subRng.nextInt(50) + 1, replicaId: repB),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes B $iter',
            timestamp: HybridLogicalClock(physicalTime: 1200 + iter, logicalCounter: 1, nodeId: repB.value),
          ),
          pinnedRuleIds: {'base_rule', 'rule_b_$iter'},
          partyCharacterIds: ['c_base', 'c_b_$iter'],
          roomState: base.roomState.copyWith(
            customProperties: {'seed': seed, 'b_prop': iter},
          ),
        );

        // Fork replica C
        final repC = ReplicaId('rep_c_$iter');
        var branchC = base.copyWith(
          partyPurse: base.partyPurse.modifyDenomination('copper', subRng.nextInt(50) + 1, replicaId: repC),
          notesRegister: CrdtLwwRegister<String>(
            value: 'Notes C $iter',
            timestamp: HybridLogicalClock(physicalTime: 1300 + iter, logicalCounter: 1, nodeId: repC.value),
          ),
          pinnedRuleIds: {'base_rule', 'rule_c_$iter'},
          partyCharacterIds: ['c_base', 'c_c_$iter'],
          roomState: base.roomState.copyWith(
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
      }
    });
  });
}
