import 'package:vtt_engine_core/crdt/stateful_hlc_clock.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/rules/ruleset_edition.dart';
import 'package:test/test.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/party_event.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/models/party_purse.dart';

extension on PartyPurse {
  PartyPurse setCoins({int? gp, int? sp, required ReplicaId replicaId}) {
    var p = this;
    if (gp != null) p = p.setDenomination('gp', gp, replicaId: replicaId);
    if (sp != null) p = p.setDenomination('sp', sp, replicaId: replicaId);
    return p;
  }
}

void main() {
  group('CampaignProfile Deep Equality Tests', () {
    final baseDate = DateTime.utc(2024, 1, 1);
    final room = RoomNodeState(
      roomId: 'room-1',
      roomCode: 'CR-101',
      title: 'Dungeon Room',
    );

    final profileA = CampaignProfile(
      id: 'camp-1',
      name: 'Dragon Hunt',
      edition: const RulesetIdentifier('dnd5e_2024'),
      createdAt: baseDate,
      lastPlayedAt: baseDate,
      roomState: room,
      partyCharacterIds: const ['char-1', 'char-2'],
      pinnedRuleIds: const {'cover', 'grapple_shove'},
      notesMarkdown: 'Session 1 notes',
      partyPurse: const PartyPurse.empty().setCoins(gp: 50, sp: 10, replicaId: ReplicaId('test-node')),
      nodeId: 'test-node',
    );

    test('identical or cloned instance with matching fields evaluates equal',
        () {
      final profileB = CampaignProfile(
        id: 'camp-1',
        name: 'Dragon Hunt',
        edition: const RulesetIdentifier('dnd5e_2024'),
        createdAt: baseDate,
        lastPlayedAt: baseDate,
        roomState: room,
        partyCharacterIds: const ['char-1', 'char-2'],
        pinnedRuleIds: const {'cover', 'grapple_shove'},
        notesRegister: profileA.notesRegister,
        partyPurse: const PartyPurse.empty().setCoins(gp: 50, sp: 10, replicaId: ReplicaId('test-node')),
        nodeId: 'test-node',
      );

      expect(profileA, equals(profileB));
      expect(profileA.hashCode, equals(profileB.hashCode));
    });

    test('detects differences in createdAt despite same id', () {
      final modified = profileA.copyWith(createdAt: DateTime.utc(2025, 1, 1));
      expect(profileA == modified, isFalse);
    });

    test('detects differences in lastPlayedAt despite same id', () {
      final modified = profileA.copyWith(lastPlayedAt: DateTime.utc(2025, 1, 2));
      expect(profileA == modified, isFalse);
    });

    test('detects differences in changeLog despite same id', () {
      final modified = profileA.copyWith(
        changeLog: [
          PartyEvent(
            id: 'ev-1',
            roomCode: 'CR-101',
            type: 'coinDeposit',
            playerName: 'Player1',
            details: 'Deposited 10gp',
            timestamp: DateTime.utc(2024, 1, 1),
          ),
        ],
      );
      expect(profileA == modified, isFalse);
    });

    test('detects differences in name despite same id', () {
      final modified = profileA.copyWith(
        name: 'Dragon Hunt (Renamed)',
        nameTimestamp: const HybridLogicalClock(
          physicalTime: 10,
          logicalCounter: 0,
          nodeId: 'test-node',
        ),
      );
      expect(profileA == modified, isFalse);
    });

    test('detects differences in edition despite same id', () {
      final modified = profileA.copyWith(edition: const RulesetIdentifier('dnd5e_2014'));
      expect(profileA == modified, isFalse);
    });

    test('detects differences in partyCharacterIds despite same id', () {
      final modified =
          profileA.copyWith(partyCharacterIds: ['char-1', 'char-3']);
      expect(profileA == modified, isFalse);
    });

    test('detects differences in pinnedRuleIds despite same id', () {
      final modified = profileA.copyWith(pinnedRuleIds: {'cover'});
      expect(profileA == modified, isFalse);
    });

    test('detects differences in notesMarkdown despite same id', () {
      final modified = profileA.copyWith(
        notesMarkdown: 'Updated notes',
        notesTimestamp: const HybridLogicalClock(
          physicalTime: 10,
          logicalCounter: 0,
          nodeId: 'test-node',
        ),
      );
      expect(profileA == modified, isFalse);
    });

    test('updating notesMarkdown without notesTimestamp throws ArgumentError', () {
      expect(
        () => profileA.copyWith(notesMarkdown: 'Updated notes'),
        throwsArgumentError,
      );
    });

    test('detects differences in partyPurse despite same id', () {
      final modified =
          profileA.copyWith(partyPurse: const PartyPurse.empty().setCoins(gp: 100, replicaId: ReplicaId('test-node')));
      expect(profileA == modified, isFalse);
    });

    test('detects differences in memberPurses despite same id', () {
      final modified = profileA.copyWith(
        memberPurses: {
          'char-1': const PartyPurse.empty().setCoins(gp: 25, replicaId: ReplicaId('test-node')),
        },
      );
      expect(profileA == modified, isFalse);
    });

    test('RoomNodeState detects entityInstances and description differences', () {
      final room1 = RoomNodeState(
        roomId: 'r1',
        roomCode: 'C1',
        title: 'Room 1',
        description: 'Original description',
      );
      final room2 = room1.copyWith(
        description: 'Modified description',
        descriptionTimestamp: const HybridLogicalClock(
          physicalTime: 10,
          logicalCounter: 0,
          nodeId: 'test-node',
        ),
      );
      expect(room1 == room2, isFalse);

      final room3 = room1.copyWith(
        entityInstances: [
          EntityInstance(
            instanceId: 'inst-1',
            entityDefinitionId: 'bp-1',
            entityType: 'character',
            displayName: 'Goblin 1',
          ),
        ],
      );
      expect(room1 == room3, isFalse);
    });

    test('updating name without nameTimestamp throws ArgumentError', () {
      expect(
        () => profileA.copyWith(name: 'Renamed Campaign'),
        throwsArgumentError,
      );
    });

    test('updating title without titleTimestamp throws ArgumentError', () {
      final room = RoomNodeState(roomId: 'r1', roomCode: 'C1', title: 'R1');
      expect(
        () => room.copyWith(title: 'Renamed Room'),
        throwsArgumentError,
      );
    });

    test('updating description without descriptionTimestamp throws ArgumentError', () {
      final room = RoomNodeState(roomId: 'r1', roomCode: 'C1', title: 'R1');
      expect(
        () => room.copyWith(description: 'Renamed Description'),
        throwsArgumentError,
      );
    });
     test('defaultProfile requires authoritative timestamp or clock', () {
      expect(
        () => CampaignProfile.defaultProfile(nodeId: 'test-node'),
        throwsArgumentError,
      );
    });

    test('defaultProfile rejects genesis sentinel timestamp', () {
      expect(
        () => CampaignProfile.defaultProfile(
          nodeId: 'genesis',
          timestamp: const HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('defaultProfile rejects writer identity mismatch', () {
      final clock = StatefulHlcClock(replicaId: ReplicaId('node-a'));
      expect(
        () => CampaignProfile.defaultProfile(
          nodeId: 'node-b',
          clock: clock,
        ),
        throwsArgumentError,
      );
    });

    test('defaultProfile stamps active CRDT membership with runtime writer causality', () {
      final clock = StatefulHlcClock(replicaId: ReplicaId('authoritative-node'));
      final profile = CampaignProfile.defaultProfile(
        id: 'camp-fresh',
        name: 'Fresh Campaign',
        nodeId: 'authoritative-node',
        clock: clock,
        defaultPinnedRules: {'cover', 'grapple_shove'},
      );

      expect(profile.nameRegister.timestamp.nodeId, equals('authoritative-node'));
      expect(profile.nameRegister.timestamp.physicalTime, greaterThan(0));
      expect(profile.notesRegister.timestamp.nodeId, equals('authoritative-node'));
      expect(profile.notesRegister.timestamp.physicalTime, greaterThan(0));
      expect(profile.pinnedRules.items.values.isNotEmpty, isTrue);
      for (final entry in profile.pinnedRules.items.values) {
        expect(entry.timestamp.nodeId, equals('authoritative-node'));
        expect(entry.timestamp.physicalTime, greaterThan(0));
        expect(entry.timestamp.nodeId, isNot(equals('genesis')));
      }
    });

    test('placeholder stamps all authored-text registers at HybridLogicalClock.genesis', () {
      final p = CampaignProfile.placeholder(
        id: 'camp_placeholder',
        roomCode: 'ROOM1',
        name: 'Lobby Name',
        stagingTitle: 'Campaign ROOM1 Staging',
      );

      expect(p.nameRegister.value, equals('Lobby Name'));
      expect(p.nameRegister.timestamp, equals(HybridLogicalClock.genesis));
      expect(p.roomState.titleRegister.value, equals('Campaign ROOM1 Staging'));
      expect(p.roomState.titleRegister.timestamp, equals(HybridLogicalClock.genesis));
      expect(p.roomState.descriptionRegister.value, equals(''));
      expect(p.roomState.descriptionRegister.timestamp, equals(HybridLogicalClock.genesis));
      expect(p.notesRegister.value, equals(''));
      expect(p.notesRegister.timestamp, equals(HybridLogicalClock.genesis));
    });

    test('placeholder loses to authored profile stamped at physical time 1 in both merge orders', () {
      final placeholder = CampaignProfile.placeholder(
        id: 'camp_1',
        roomCode: 'ROOM1',
        name: 'Placeholder Name',
        stagingTitle: 'Placeholder Staging',
      );

      const t1 = HybridLogicalClock(
        physicalTime: 1,
        logicalCounter: 0,
        nodeId: 'dm_device',
      );
      final authored = CampaignProfile.raw(
        id: 'camp_1',
        nameRegister: const CrdtLwwRegister<String>(
          value: 'The Dragon Hunt',
          timestamp: t1,
        ),
        edition: const RulesetIdentifier('generic_tabletop'),
        createdAt: DateTime.utc(2026, 1, 1),
        lastPlayedAt: DateTime.utc(2026, 1, 1),
        roomState: RoomNodeState(
          roomId: 'room_ROOM1',
          roomCode: 'ROOM1',
          title: 'Dragon Lair',
          titleTimestamp: t1,
          description: 'Real DM description',
          descriptionTimestamp: t1,
        ),
        partyRoster: const CrdtOrSet<String>.empty(),
        partyCharacterIds: const [],
        pinnedRuleIds: const {},
        pinnedRules: const CrdtOrSet<String>.empty(),
        notesRegister: const CrdtLwwRegister<String>(
          value: 'DM notes',
          timestamp: t1,
        ),
        partyPurse: const PartyPurse.empty(),
        memberPurses: const {},
        changeLog: const [],
      );

      final merged1 = CampaignProfile.join(placeholder, authored);
      final merged2 = CampaignProfile.join(authored, placeholder);

      expect(merged1, equals(merged2));
      expect(merged1.nameRegister.value, equals('The Dragon Hunt'));
      expect(merged1.nameRegister.timestamp, equals(t1));
      expect(merged1.roomState.titleRegister.value, equals('Dragon Lair'));
      expect(merged1.roomState.titleRegister.timestamp, equals(t1));
      expect(merged1.roomState.descriptionRegister.value, equals('Real DM description'));
      expect(merged1.roomState.descriptionRegister.timestamp, equals(t1));
      expect(merged1.notesRegister.value, equals('DM notes'));
      expect(merged1.notesRegister.timestamp, equals(t1));
    });
  });
}
