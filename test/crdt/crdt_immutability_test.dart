import 'package:vtt_engine_core/crdt/replica_id.dart';
import 'package:vtt_engine_core/utils/deep_immutable.dart';
import 'package:vtt_engine_core/models/core_types.dart';
import 'package:vtt_engine_core/models/entity_reference.dart';
import 'package:vtt_engine_core/models/character_models.dart';
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
        final counter = PnCounter.withInitialValue(10, replicaId: ReplicaId('node-a'));

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
          'gp': PnCounter.withInitialValue(50, replicaId: ReplicaId('node-a')),
        };
        final purse = PartyPurse(denominationCounters: sourceMap);

        sourceMap['gp'] = PnCounter.withInitialValue(999, replicaId: ReplicaId('node-a'));
        sourceMap['sp'] = PnCounter.withInitialValue(100, replicaId: ReplicaId('node-a'));

        expect(purse.getCounter('gp').value, 50);
        expect(purse.getCounter('sp').value, 0);

        expect(
          () => purse.denominationCounters['gp'] = PnCounter.withInitialValue(1, replicaId: ReplicaId('node-a')),
          throwsUnsupportedError,
        );
        expect(
          () => purse.allCounters['gp'] = PnCounter.withInitialValue(1, replicaId: ReplicaId('node-a')),
          throwsUnsupportedError,
        );
      });

      test('PartyPurse.fromCounters and copyWith protect against external mutable map aliases', () {
        final sourceMap = <String, PnCounter>{
          'gp': PnCounter.withInitialValue(25, replicaId: ReplicaId('node-a')),
        };
        final purse = PartyPurse.fromCounters(sourceMap);
        sourceMap['gp'] = PnCounter.withInitialValue(1000, replicaId: ReplicaId('node-a'));

        expect(purse.getCounter('gp').value, 25);

        final copyMap = <String, PnCounter>{
          'pp': PnCounter.withInitialValue(5, replicaId: ReplicaId('node-a')),
        };
        final copiedPurse = purse.copyWith(denominationCounters: copyMap);
        copyMap['pp'] = PnCounter.withInitialValue(500, replicaId: ReplicaId('node-a'));

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

    group('9. Deep Immutability & Nested Alias Safety (Pass 2.1)', () {
      test('InventoryItemInstance.customProperties cannot be mutated through external alias', () {
        final props = <String, dynamic>{
          'charges': 3,
        };
        final item = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            slug: 'wand-1',
            refType: EntityType.item,
            displayName: 'Wand of Wonder',
          ),
          instanceId: 'wand-inst-1',
          customProperties: props,
        );

        props['charges'] = 0;
        expect(item.customProperties['charges'], 3);
        expect(() => item.customProperties['charges'] = 0, throwsUnsupportedError);
      });

      test('Nested Map in dynamic metadata is recursively defensive-copied and unmodifiable', () {
        final source = <String, dynamic>{
          'stats': <String, dynamic>{
            'hp': 10,
          }
        };

        final item = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            slug: 'amulet',
            refType: EntityType.item,
            displayName: 'Amulet',
          ),
          instanceId: 'am-1',
          customProperties: source,
        );

        (source['stats'] as Map<String, dynamic>)['hp'] = 999;
        expect((item.customProperties['stats'] as Map)['hp'], 10);
        expect(
          () => (item.customProperties['stats'] as Map)['hp'] = 999,
          throwsUnsupportedError,
        );
      });

      test('Nested List in dynamic metadata is recursively defensive-copied and unmodifiable', () {
        final source = <String, dynamic>{
          'inventory': <dynamic>[
            {'name': 'Sword'}
          ]
        };

        final item = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            slug: 'bag',
            refType: EntityType.item,
            displayName: 'Bag of Holding',
          ),
          instanceId: 'bag-1',
          customProperties: source,
        );

        (source['inventory'] as List).clear();
        expect((item.customProperties['inventory'] as List).length, 1);
        expect(
          ((item.customProperties['inventory'] as List).first as Map)['name'],
          'Sword',
        );

        expect(
          () => (item.customProperties['inventory'] as List).clear(),
          throwsUnsupportedError,
        );
        expect(
          () => ((item.customProperties['inventory'] as List).first as Map)['name'] = 'Dagger',
          throwsUnsupportedError,
        );
      });

      test('copyWith preserves deep defensive copy invariant for nested metadata', () {
        final original = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            slug: 'ring',
            refType: EntityType.item,
            displayName: 'Ring',
          ),
          instanceId: 'ring-1',
        );

        final nested = <String, dynamic>{
          'stats': <String, dynamic>{
            'hp': 10,
          }
        };

        final updated = original.copyWith(customProperties: nested);
        (nested['stats'] as Map<String, dynamic>)['hp'] = 999;

        expect((updated.customProperties['stats'] as Map)['hp'], 10);
        expect(
          () => (updated.customProperties['stats'] as Map)['hp'] = 999,
          throwsUnsupportedError,
        );
      });

      test('End-to-end CRDT aliasing chain: deep nested mutations cannot alter CRDT-stamped state', () {
        final props = <String, dynamic>{
          'magic': <String, dynamic>{
            'charges': <dynamic>[1, 2, 3],
          }
        };

        final item = InventoryItemInstance(
          itemRef: const EntityReference.empty(
            slug: 'wand_of_magic_missiles',
            refType: EntityType.item,
            displayName: 'Wand of Magic Missiles',
          ),
          instanceId: 'wand-1',
          customProperties: props,
        );

        final container = LootContainer(
          containerId: 'chest-1',
          name: 'Treasure Chest',
          items: [item],
        );

        final room = RoomNodeState(
          roomId: 'room-1',
          roomCode: 'ABCD',
          title: 'Dungeon Room',
          containers: [container],
        );

        final set = const CrdtOrSet<RoomNodeState>.empty().add(
          'room-1',
          room,
          clock,
        );

        // Mutate original deeply nested collection
        ((props['magic'] as Map)['charges'] as List).clear();
        (props['magic'] as Map)['overcharged'] = true;

        // Verify CRDT-stamped state remains unpolluted and intact
        final stampedRoom = set.items['room-1']!.value;
        final stampedItem = stampedRoom.containers.first.items.first;
        final magicMap = stampedItem.customProperties['magic'] as Map;

        expect(magicMap['charges'], [1, 2, 3]);
        expect(magicMap.containsKey('overcharged'), isFalse);
        expect(
          () => (magicMap['charges'] as List).add(4),
          throwsUnsupportedError,
        );
        expect(
          () => magicMap['overcharged'] = true,
          throwsUnsupportedError,
        );
      });
    });

    group('10. Transitive Replicated Payload Immutability Closure (Pass 2.2)', () {
      test('deepFreeze runtime-type preservation for non-empty collections', () {
        final listStr = deepFreezeList(<String>['a', 'b']);
        expect(listStr, isA<List<String>>());
        expect(() => listStr.add('c'), throwsUnsupportedError);

        final listInt = deepFreezeList(<int>[1, 2]);
        expect(listInt, isA<List<int>>());
        expect(() => listInt.add(3), throwsUnsupportedError);

        final listDouble = deepFreezeList(<double>[1.1, 2.2]);
        expect(listDouble, isA<List<double>>());
        expect(() => listDouble.add(3.3), throwsUnsupportedError);

        final listNum = deepFreezeList(<num>[1, 2.5]);
        expect(listNum, isA<List<num>>());
        expect(() => listNum.add(3), throwsUnsupportedError);

        final listBool = deepFreezeList(<bool>[true, false]);
        expect(listBool, isA<List<bool>>());
        expect(() => listBool.add(true), throwsUnsupportedError);

        final setStr = deepFreezeSet(<String>{'a', 'b'});
        expect(setStr, isA<Set<String>>());
        expect(() => setStr.add('c'), throwsUnsupportedError);

        final setInt = deepFreezeSet(<int>{1, 2});
        expect(setInt, isA<Set<int>>());
        expect(() => setInt.add(3), throwsUnsupportedError);

        final setDouble = deepFreezeSet(<double>{1.1, 2.2});
        expect(setDouble, isA<Set<double>>());
        expect(() => setDouble.add(3.3), throwsUnsupportedError);

        final setNum = deepFreezeSet(<num>{1, 2.5});
        expect(setNum, isA<Set<num>>());
        expect(() => setNum.add(3), throwsUnsupportedError);

        final setBool = deepFreezeSet(<bool>{true, false});
        expect(setBool, isA<Set<bool>>());
        expect(() => setBool.add(true), throwsUnsupportedError);
      });

      test('deepFreeze runtime-type preservation for empty typed collections', () {
        final emptyStrList = deepFreezeList(<String>[]);
        expect(emptyStrList, isA<List<String>>());
        expect(() => emptyStrList.add('a'), throwsUnsupportedError);

        final emptyIntList = deepFreezeList(<int>[]);
        expect(emptyIntList, isA<List<int>>());
        expect(() => emptyIntList.add(1), throwsUnsupportedError);

        final emptyDoubleList = deepFreezeList(<double>[]);
        expect(emptyDoubleList, isA<List<double>>());
        expect(() => emptyDoubleList.add(1.0), throwsUnsupportedError);

        final emptyNumList = deepFreezeList(<num>[]);
        expect(emptyNumList, isA<List<num>>());
        expect(() => emptyNumList.add(1), throwsUnsupportedError);

        final emptyBoolList = deepFreezeList(<bool>[]);
        expect(emptyBoolList, isA<List<bool>>());
        expect(() => emptyBoolList.add(true), throwsUnsupportedError);

        final emptyStrSet = deepFreezeSet(<String>{});
        expect(emptyStrSet, isA<Set<String>>());
        expect(() => emptyStrSet.add('a'), throwsUnsupportedError);

        final emptyIntSet = deepFreezeSet(<int>{});
        expect(emptyIntSet, isA<Set<int>>());
        expect(() => emptyIntSet.add(1), throwsUnsupportedError);

        final emptyDoubleSet = deepFreezeSet(<double>{});
        expect(emptyDoubleSet, isA<Set<double>>());
        expect(() => emptyDoubleSet.add(1.0), throwsUnsupportedError);

        final emptyNumSet = deepFreezeSet(<num>{});
        expect(emptyNumSet, isA<Set<num>>());
        expect(() => emptyNumSet.add(1), throwsUnsupportedError);

        final emptyBoolSet = deepFreezeSet(<bool>{});
        expect(emptyBoolSet, isA<Set<bool>>());
        expect(() => emptyBoolSet.add(true), throwsUnsupportedError);
      });

      test('Direct EntityReference immutability and anti-aliasing', () {
        final props = <String, dynamic>{
          'weapon': <String, dynamic>{
            'tags': <dynamic>['magic'],
          },
        };
        final skills = <dynamic>['athletics', 'acrobatics'];

        final ref = EntityReference<DomainEntity>(
          refType: EntityType.item,
          slug: 'sunblade',
          displayName: 'Sun Blade',
          grantedSkills: skills,
          customProperties: props,
        );

        // Mutate original input collections
        ((props['weapon'] as Map)['tags'] as List).clear();
        skills.add('stealth');

        // Ref remains unchanged
        expect((ref.customProperties['weapon'] as Map)['tags'], ['magic']);
        expect(ref.grantedSkills, ['athletics', 'acrobatics']);

        // Mutations through ref collections throw
        expect(
          () => ((ref.customProperties['weapon'] as Map)['tags'] as List).add('radiant'),
          throwsUnsupportedError,
        );
        expect(
          () => (ref.customProperties['weapon'] as Map)['extra'] = 'val',
          throwsUnsupportedError,
        );
        expect(
          () => ref.grantedSkills.add('stealth'),
          throwsUnsupportedError,
        );

        // copyWith and cast preserve defensive copying
        final copied = ref.copyWith(
          customProperties: {
            'sub': {'val': 1}
          },
        );
        expect(() => (copied.customProperties['sub'] as Map)['val'] = 2, throwsUnsupportedError);

        final castRef = ref.cast<DomainEntity>();
        expect(() => ((castRef.customProperties['weapon'] as Map)['tags'] as List).add('x'), throwsUnsupportedError);
      });

      test('Transitive EntityReference -> InventoryItemInstance -> LootContainer -> RoomNodeState -> CrdtOrSet', () {
        final refProps = <String, dynamic>{
          'weapon': <String, dynamic>{
            'tags': <dynamic>['magic', 'finesse'],
          }
        };

        final ref = EntityReference<DomainEntity>(
          refType: EntityType.item,
          slug: 'rapier-plus-1',
          displayName: 'Rapier +1',
          customProperties: refProps,
        );

        final item = InventoryItemInstance(
          itemRef: ref,
          instanceId: 'rapier-inst-1',
        );

        final container = LootContainer(
          containerId: 'armory-1',
          name: 'Armory Locker',
          items: [item],
        );

        final room = RoomNodeState(
          roomId: 'room-armory',
          roomCode: 'ARMR',
          title: 'The Armory',
          containers: [container],
        );

        final crdt = const CrdtOrSet<RoomNodeState>.empty().add(
          'room-armory',
          room,
          clock,
        );

        // Mutate original EntityReference input collections
        ((refProps['weapon'] as Map)['tags'] as List).add('corrupted');

        // Verify CRDT-stamped state is unchanged and unmodifiable
        final stampedRoom = crdt.items['room-armory']!.value;
        final stampedItem = stampedRoom.containers.first.items.first;
        final stampedRef = stampedItem.itemRef;
        final tags = (stampedRef.customProperties['weapon'] as Map)['tags'] as List;

        expect(tags, ['magic', 'finesse']);
        expect(() => tags.add('corrupted'), throwsUnsupportedError);
      });

      test('RoomNodeState.fromMap fallback deserializes deep-frozen activeMinions', () {
        final rawMinion = <String, dynamic>{
          'id': 'minion-raw-1',
          'name': 'Animated Armor',
          'traits': <String, dynamic>{
            'resistances': <dynamic>['poison', 'psychic'],
          },
        };

        final rawPayload = <String, dynamic>{
          'roomId': 'room-arena',
          'roomCode': 'ARNA',
          'title': 'The Arena',
          'activeMinions': [rawMinion],
        };

        // Deserialize WITHOUT passing any custom minionParser
        final room = RoomNodeState.fromMap(rawPayload);

        // Mutate original input raw map
        ((rawMinion['traits'] as Map)['resistances'] as List).clear();
        rawMinion['name'] = 'Mutated Armor';

        // Check activeMinions in room
        expect(room.activeMinions.activeValues.length, 1);
        final minionInCrdt = room.activeMinions.activeValues.first as Map;
        expect(minionInCrdt['name'], 'Animated Armor');
        expect(
          (minionInCrdt['traits'] as Map)['resistances'],
          ['poison', 'psychic'],
        );

        // Verify that mutations through activeMinions throw
        expect(
          () => minionInCrdt['name'] = 'Changed',
          throwsUnsupportedError,
        );
        expect(
          () => ((minionInCrdt['traits'] as Map)['resistances'] as List).add('fire'),
          throwsUnsupportedError,
        );
      });

      test('RoomNodeState.fromLists and copyWith deep-freeze Map/List/Set in activeMinions', () {
        final mutableMinion = <String, dynamic>{
          'id': 'm1',
          'tags': ['flying'],
        };

        final fromListsRoom = RoomNodeState.fromLists(
          roomId: 'r1',
          roomCode: 'R101',
          title: 'Room 1',
          activeMinions: [mutableMinion],
        );

        (mutableMinion['tags'] as List).add('invisible');

        final minionFromLists = fromListsRoom.activeMinions.activeValues.first as Map;
        expect(minionFromLists['tags'], ['flying']);
        expect(() => (minionFromLists['tags'] as List).add('x'), throwsUnsupportedError);

        final minionSet = const CrdtOrSet<dynamic>.empty().add(
          'm1',
          deepFreezeValue(mutableMinion),
          const HybridLogicalClock(physicalTime: 1, logicalCounter: 0, nodeId: 'node-test-1'),
        );
        final copyWithRoom = const RoomNodeState.empty().copyWith(
          roomId: 'r2',
          roomCode: 'R102',
          title: 'Room 2',
          activeMinions: minionSet,
        );

        (mutableMinion['tags'] as List).clear();

        final minionFromCopy = copyWithRoom.activeMinions.activeValues.first as Map;
        expect(minionFromCopy['tags'], ['flying', 'invisible']);
        expect(() => (minionFromCopy['tags'] as List).add('y'), throwsUnsupportedError);
      });
    });
  });
}
