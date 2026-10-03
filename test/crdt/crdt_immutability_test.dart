import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/models/party_purse.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/homebrew/models/homebrew_entity.dart';
import 'package:vtt_engine_core/homebrew/value_objects/ruleset_version.dart';

void main() {
  const clock = HybridLogicalClock(
    physicalTime: 1000000,
    logicalCounter: 0,
    nodeId: 'test-node-1',
  );

  group('Cold Iron Birdcage — Pass 2: CRDT Immutability', () {
    group('1 & 2. PnCounter Immutability & Anti-Aliasing', () {
      test('PnCounter constructor input maps cannot mutate the constructed counter', () {
        final sourcePos = <String, int>{'node-a': 10};
        final sourceNeg = <String, int>{'node-a': 2};
        final counter = PnCounter(positive: sourcePos, negative: sourceNeg);

        sourcePos['node-a'] = 999;
        sourceNeg['node-a'] = 888;

        expect(counter.positive['node-a'], 10);
        expect(counter.negative['node-a'], 2);
        expect(counter.value, 8);
      });

      test('PnCounter.positive and .negative cannot be mutated externally', () {
        final counter = PnCounter.withInitialValue(10, nodeId: 'node-a');

        expect(
          () => counter.positive['node-a'] = 999,
          throwsUnsupportedError,
        );
        expect(
          () => counter.negative['node-a'] = 999,
          throwsUnsupportedError,
        );
      });
    });

    group('3, 4, 5. CrdtOrSet Immutability & Anti-Aliasing', () {
      test('CrdtOrSet constructor maps cannot mutate the constructed set', () {
        const reg = CrdtLwwRegister(value: 'initial', timestamp: clock);
        final itemsMap = <String, CrdtLwwRegister<String>>{'item-1': reg};
        final tombstonesMap = <String, HybridLogicalClock>{'old-item': clock};

        final set = CrdtOrSet<String>(
          items: itemsMap,
          tombstones: tombstonesMap,
        );

        itemsMap['item-1'] = CrdtLwwRegister(
          value: 'mutated',
          timestamp: clock.tick(timeProvider: () => 1000001),
        );
        tombstonesMap['new-tombstone'] = clock;

        expect(set.items['item-1']!.value, 'initial');
        expect(set.tombstones.containsKey('new-tombstone'), isFalse);
      });

      test('CrdtOrSet.items and .tombstones cannot be externally mutated', () {
        final set = const CrdtOrSet<String>.empty().add('item-1', 'value-1', clock);

        expect(
          () => set.items['item-1'] = const CrdtLwwRegister(value: 'hacked', timestamp: clock),
          throwsUnsupportedError,
        );
        expect(
          () => set.tombstones['item-1'] = clock,
          throwsUnsupportedError,
        );
        expect(
          () => set.activeValues.add('external'),
          throwsUnsupportedError,
        );
      });

      test('Mutation of input collections after merge or addBatch cannot alter CRDT instance', () {
        final entries = [
          (id: 'batch-1', item: 'val-1', timestamp: clock),
        ];
        final set = const CrdtOrSet<String>.empty().addBatch(entries);

        // Mutating external batch list after addBatch
        entries.add((id: 'batch-2', item: 'val-2', timestamp: clock));

        expect(set.length, 1);
        expect(set.items.containsKey('batch-2'), isFalse);

        // Merge preserves immutability
        final remote = const CrdtOrSet<String>.empty().add(
          'batch-2',
          'val-2',
          clock.tick(timeProvider: () => 1000002),
        );
        final merged = set.merge(remote);

        expect(
          () => merged.items['batch-1'] = const CrdtLwwRegister(value: 'x', timestamp: clock),
          throwsUnsupportedError,
        );
      });
    });

    group('6. PartyPurse Immutability & Anti-Aliasing', () {
      test('PartyPurse cannot be mutated through constructor input map or denominationCounters', () {
        final sourceMap = <String, PnCounter>{
          'gp': PnCounter.withInitialValue(50, nodeId: 'node-a'),
        };
        final purse = PartyPurse(denominationCounters: sourceMap);

        sourceMap['gp'] = PnCounter.withInitialValue(999, nodeId: 'node-a');
        sourceMap['sp'] = PnCounter.withInitialValue(100, nodeId: 'node-a');

        expect(purse.getCounter('gp').value, 50);
        expect(purse.getCounter('sp').value, 0);

        expect(
          () => purse.denominationCounters['gp'] = PnCounter.withInitialValue(1, nodeId: 'node-a'),
          throwsUnsupportedError,
        );
        expect(
          () => purse.allCounters['gp'] = PnCounter.withInitialValue(1, nodeId: 'node-a'),
          throwsUnsupportedError,
        );
      });

      test('PartyPurse.fromCounters and copyWith protect against external mutable map aliases', () {
        final sourceMap = <String, PnCounter>{
          'gp': PnCounter.withInitialValue(25, nodeId: 'node-a'),
        };
        final purse = PartyPurse.fromCounters(sourceMap);
        sourceMap['gp'] = PnCounter.withInitialValue(1000, nodeId: 'node-a');

        expect(purse.getCounter('gp').value, 25);

        final copyMap = <String, PnCounter>{
          'pp': PnCounter.withInitialValue(5, nodeId: 'node-a'),
        };
        final copiedPurse = purse.copyWith(denominationCounters: copyMap);
        copyMap['pp'] = PnCounter.withInitialValue(500, nodeId: 'node-a');

        expect(copiedPurse.getCounter('pp').value, 5);
      });
    });

    group('7. Representative Replicated Payload Types Immutability', () {
      test('CampaignProfile collections cannot be mutated externally or through original aliases', () {
        final partyIds = <String>['char-1', 'char-2'];
        final pinned = <String>{'cover', 'flanking'};
        final profile = CampaignProfile(
          id: 'camp-1',
          name: 'My Campaign',
          createdAt: DateTime.now(),
          lastPlayedAt: DateTime.now(),
          roomState: const RoomNodeState.empty(),
          partyCharacterIds: partyIds,
          pinnedRuleIds: pinned,
          nodeId: 'node-a',
        );

        partyIds.add('char-3');
        pinned.add('inspiration');

        expect(profile.partyCharacterIds, ['char-1', 'char-2']);
        expect(profile.pinnedRuleIds, {'cover', 'flanking'});

        expect(
          () => profile.partyCharacterIds.add('char-x'),
          throwsUnsupportedError,
        );
        expect(
          () => profile.pinnedRuleIds.add('rule-x'),
          throwsUnsupportedError,
        );

        final updated = profile.copyWith(partyCharacterIds: ['new-char']);
        expect(
          () => updated.partyCharacterIds.add('fail'),
          throwsUnsupportedError,
        );
      });

      test('RoomNodeState collections cannot be mutated externally or through original aliases', () {
        final links = <RoomEntityLink>[
          RoomEntityLink(entityId: 'e-1', displayName: 'Door'),
        ];
        final instances = <EntityInstance>[
          EntityInstance(instanceId: 'inst-1', displayName: 'Token'),
        ];
        final containers = <LootContainer>[
          LootContainer(containerId: 'chest-1', name: 'Chest'),
        ];
        final customProps = <String, dynamic>{'theme': 'dungeon'};

        final room = RoomNodeState(
          roomId: 'r-1',
          roomCode: 'ROOM1',
          title: 'Dungeon Room',
          entityLinks: links,
          entityInstances: instances,
          containers: containers,
          customProperties: customProps,
        );

        links.add(RoomEntityLink(entityId: 'e-2', displayName: 'Trap'));
        instances.add(EntityInstance(instanceId: 'inst-2', displayName: 'Monster'));
        containers.add(LootContainer(containerId: 'chest-2', name: 'Vase'));
        customProps['theme'] = 'castle';

        expect(room.entityLinks.length, 1);
        expect(room.entityInstances.length, 1);
        expect(room.containers.length, 1);
        expect(room.customProperties['theme'], 'dungeon');

        expect(() => room.entityLinks.add(links.last), throwsUnsupportedError);
        expect(() => room.entityInstances.add(instances.last), throwsUnsupportedError);
        expect(() => room.containers.add(containers.last), throwsUnsupportedError);
        expect(() => room.customProperties['new'] = 'val', throwsUnsupportedError);
      });

      test('EncounterParticipant collections cannot be mutated externally or through original aliases', () {
        final conditions = <String>['blinded', 'poisoned'];
        final props = <String, dynamic>{'boss': true};

        final participant = EncounterParticipant(
          participantId: 'p-1',
          entityLink: RoomEntityLink(entityId: 'e-1', displayName: 'Villain'),
          activeConditions: conditions,
          customProperties: props,
        );

        conditions.add('stunned');
        props['boss'] = false;

        expect(participant.activeConditions, ['blinded', 'poisoned']);
        expect(participant.customProperties['boss'], true);

        expect(() => participant.activeConditions.add('prone'), throwsUnsupportedError);
        expect(() => participant.customProperties['x'] = 1, throwsUnsupportedError);
      });

      test('LootContainer and HomebrewEntity collections cannot be mutated externally', () {
        final perms = <String, dynamic>{'owner': 'dm'};
        final loot = LootContainer(
          containerId: 'c-1',
          name: 'Hoard',
          permissions: perms,
        );
        perms['owner'] = 'player';
        expect(loot.permissions['owner'], 'dm');
        expect(() => loot.permissions['key'] = 'val', throwsUnsupportedError);

        final raw = <String, dynamic>{'stat': 'str'};
        final homebrew = HomebrewEntity(
          id: 'hb-1',
          name: 'Homebrew Feat',
          entityType: 'feat',
          ruleset: RulesetVersion.v2024,
          rawPayload: raw,
        );
        raw['stat'] = 'dex';
        expect(homebrew.rawPayload['stat'], 'stat' == 'dex' ? 'dex' : 'str');
        expect(homebrew.rawPayload['stat'], 'str');
        expect(() => homebrew.rawPayload['new'] = 1, throwsUnsupportedError);
      });
    });

    group('8. Invariant: Value already stored inside CRDT cannot be mutated through external alias', () {
      test('CrdtOrSet<EncounterParticipant> prevents mutation through input collection alias', () {
        final conditions = <String>['poisoned'];
        final participant = EncounterParticipant(
          participantId: 'p1',
          entityLink: RoomEntityLink(
            entityId: 'e1',
            displayName: 'Hero',
          ),
          activeConditions: conditions,
        );

        final set = const CrdtOrSet<EncounterParticipant>.empty().add(
          'p1',
          participant,
          clock,
        );

        // Mutating caller list originally passed into participant
        conditions.add('stunned');

        // CRDT value remains clean and unpolluted
        expect(
          set.items['p1']!.value.activeConditions,
          ['poisoned'],
        );
      });

      test('CrdtOrSet<RoomNodeState> preserves immutability through nested structures', () {
        final links = <RoomEntityLink>[
          RoomEntityLink(entityId: 'e1', displayName: 'Altar'),
        ];
        final room = RoomNodeState(
          roomId: 'r1',
          roomCode: 'ALTAR',
          title: 'Altar Room',
          entityLinks: links,
        );

        final set = const CrdtOrSet<RoomNodeState>.empty().add('r1', room, clock);
        links.add(RoomEntityLink(entityId: 'e2', displayName: 'Pedestal'));

        expect(set.items['r1']!.value.entityLinks.length, 1);
        expect(set.items['r1']!.value.entityLinks.first.displayName, 'Altar');
      });
    });
  });
}
