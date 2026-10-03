import 'package:test/test.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';

import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/models/party_purse.dart';


extension on PartyPurse {
  PartyPurse setCoins({int? gp, int? sp, required String nodeId}) {
    var p = this;
    if (gp != null) p = p.setDenomination('gp', gp, nodeId: nodeId);
    if (sp != null) p = p.setDenomination('sp', sp, nodeId: nodeId);
    return p;
  }
}

void main() {
  group('CampaignProfile Deep Equality Tests', () {
    final baseDate = DateTime.utc(2024, 1, 1);
    const room = RoomNodeState(
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
      partyPurse: const PartyPurse().setCoins(gp: 50, sp: 10, nodeId: 'test-node'),
      nodeId: 'test-node',
    );

    test('identical or cloned instance with matching fields evaluates equal',
        () {
      final profileB = CampaignProfile(
        id: 'camp-1',
        name: 'Dragon Hunt',
        edition: 'dnd5e_2024',
        createdAt: DateTime.utc(
            2025, 1, 1), // timestamps differ but aren't equality gated
        lastPlayedAt: DateTime.utc(2025, 1, 2),
        roomState: room,
        partyCharacterIds: const ['char-1', 'char-2'],
        pinnedRuleIds: const {'cover', 'grapple_shove'},
        notesRegister: profileA.notesRegister,
        partyPurse: const PartyPurse().setCoins(gp: 50, sp: 10, nodeId: 'test-node'),
        nodeId: 'test-node',
      );

      expect(profileA, equals(profileB));
      expect(profileA.hashCode, equals(profileB.hashCode));
    });

    test('detects differences in name despite same id', () {
      final modified = profileA.copyWith(name: 'Dragon Hunt (Renamed)');
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
      final modified = profileA.copyWith(notesMarkdown: 'Updated notes');
      expect(profileA == modified, isFalse);
    });

    test('detects differences in partyPurse despite same id', () {
      final modified =
          profileA.copyWith(partyPurse: const PartyPurse().setCoins(gp: 100, nodeId: 'test-node'));
      expect(profileA == modified, isFalse);
    });
  });
}
