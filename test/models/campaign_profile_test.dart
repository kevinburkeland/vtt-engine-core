import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/replica_id.dart';
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
      edition: 'dnd5e_2024',
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
        edition: 'dnd5e_2024',
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
      final modified = profileA.copyWith(edition: 'dnd5e_2014');
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
  });
}
