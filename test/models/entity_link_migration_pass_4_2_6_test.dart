import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  HybridLogicalClock makeHlc(int pt, [String nodeId = 'node1', int lc = 0]) {
    return HybridLogicalClock(physicalTime: pt, logicalCounter: lc, nodeId: nodeId);
  }

  RoomEntityLink makeLink(String id, {String name = 'Test Link', HybridLogicalClock? incarnation}) {
    return RoomEntityLink(
      entityId: id,
      displayName: name,
      notes: 'Initial notes',
      incarnationTimestamp: incarnation,
    );
  }

  group('Pass 4.2.6: Fix 1 - Preserve legacy CrdtOrSet<RoomEntityLink> semantics during migration', () {
    test('legacy item newer than tombstone -> remains ACTIVE', () {
      final link = makeLink('e1', name: 'Item @30');
      final tsItem = makeHlc(30);
      final tsTomb = makeHlc(20);

      var orSet = CrdtOrSet<RoomEntityLink>();
      orSet = orSet.remove('e1', tsTomb);
      orSet = orSet.add('e1', link, tsItem);

      expect(orSet.items.containsKey('e1'), isTrue);

      final migrated = EntityLinkCrdtSet.fromCrdtOrSet(orSet);
      expect(migrated.items.containsKey('e1'), isTrue);
      expect(migrated.items['e1']?.value.displayName, 'Item @30');
      expect(migrated.tombstones.containsKey('e1'), isFalse);
    });

    test('legacy item older than tombstone -> REMOVED', () {
      final link = makeLink('e1', name: 'Item @10');
      final tsItem = makeHlc(10);
      final tsTomb = makeHlc(20);

      var orSet = CrdtOrSet<RoomEntityLink>();
      orSet = orSet.add('e1', link, tsItem);
      orSet = orSet.remove('e1', tsTomb);

      expect(orSet.items.containsKey('e1'), isFalse);

      final migrated = EntityLinkCrdtSet.fromCrdtOrSet(orSet);
      expect(migrated.items.containsKey('e1'), isFalse);
      expect(migrated.tombstones.containsKey('e1'), isTrue);
      expect(migrated.tombstones['e1']!.targetGeneration.physicalTime, 20);
    });

    test('legacy equal item/tombstone timestamps -> legacy ADD-WINS preserved (ACTIVE)', () {
      final ts = makeHlc(20);
      final link = makeLink('e1', name: 'Item @20', incarnation: ts);

      // When an item @20 is migrated, its generation is @20.
      // When an equal tombstone @20 is migrated from a legacy replica, legacyAddWins is true.
      final tombstone = EntityLinkTombstone(
        targetGeneration: ts,
        timestamp: ts,
        legacyAddWins: true,
      );
      final itemRegister = CrdtLwwRegister<RoomEntityLink>(value: link, timestamp: ts);

      final set = EntityLinkCrdtSet(
        items: {'e1': itemRegister},
        tombstones: {'e1': tombstone},
      );

      expect(set.items.containsKey('e1'), isTrue);
      expect(set.items['e1']?.value.displayName, 'Item @20');
      expect(set.tombstones.containsKey('e1'), isFalse);
    });

    test('legacy item-only migration', () {
      var orSet = CrdtOrSet<RoomEntityLink>();
      final link = makeLink('e1', name: 'Item Only');
      orSet = orSet.add('e1', link, makeHlc(15));

      final migrated = EntityLinkCrdtSet.fromCrdtOrSet(orSet);
      expect(migrated.items.containsKey('e1'), isTrue);
      expect(migrated.items['e1']?.value.displayName, 'Item Only');
      expect(migrated.tombstones.containsKey('e1'), isFalse);
    });

    test('legacy tombstone-only migration', () {
      var orSet = CrdtOrSet<RoomEntityLink>();
      final link = makeLink('e1', name: 'Tombstone Only');
      orSet = orSet.add('e1', link, makeHlc(10));
      orSet = orSet.remove('e1', makeHlc(20));

      final migrated = EntityLinkCrdtSet.fromCrdtOrSet(orSet);
      expect(migrated.items.containsKey('e1'), isFalse);
      expect(migrated.tombstones.containsKey('e1'), isTrue);
      expect(migrated.tombstones['e1']!.targetGeneration.physicalTime, 20);
    });

    test('independently migrated replicas merged afterward maintain correct active state', () {
      // Replica A has item @30, tombstone @20 -> migrated to EntityLinkCrdtSet
      var orSetA = CrdtOrSet<RoomEntityLink>();
      final linkA = makeLink('e1', name: 'Item A @30');
      orSetA = orSetA.remove('e1', makeHlc(20));
      orSetA = orSetA.add('e1', linkA, makeHlc(30));
      final migratedA = EntityLinkCrdtSet.fromCrdtOrSet(orSetA);

      // Replica B has tombstone @20 only
      var orSetB = CrdtOrSet<RoomEntityLink>();
      final linkB = makeLink('e1', name: 'Item B @10');
      orSetB = orSetB.add('e1', linkB, makeHlc(10));
      orSetB = orSetB.remove('e1', makeHlc(20));
      final migratedB = EntityLinkCrdtSet.fromCrdtOrSet(orSetB);

      // Merge migratedA and migratedB in both directions
      final mergedAB = migratedA.merge(migratedB);
      final mergedBA = migratedB.merge(migratedA);

      expect(mergedAB.items.containsKey('e1'), isTrue);
      expect(mergedBA.items.containsKey('e1'), isTrue);
      expect(mergedAB.items['e1']?.value.displayName, 'Item A @30');
      expect(mergedBA.items['e1']?.value.displayName, 'Item A @30');
    });

    test('independently migrated replicas with equal timestamps merge as ADD-WINS', () {
      final ts = makeHlc(20);
      // Replica A has item @20
      final linkA = makeLink('e1', name: 'Item A @20');
      var orSetA = CrdtOrSet<RoomEntityLink>();
      orSetA = orSetA.add('e1', linkA, ts);
      final migratedA = EntityLinkCrdtSet.fromCrdtOrSet(orSetA);

      // Replica B has tombstone @20
      final legacyTombB = CrdtOrSet<RoomEntityLink>(
        items: const {},
        tombstones: {'e1': ts},
      );
      final migratedB = EntityLinkCrdtSet.fromCrdtOrSet(legacyTombB);

      // Migrated B should have legacyAddWins flag set
      expect(migratedB.tombstones['e1']?.legacyAddWins, isTrue);

      // Merge A and B
      final merged = migratedA.merge(migratedB);
      expect(merged.items.containsKey('e1'), isTrue);
      expect(merged.items['e1']?.value.displayName, 'Item A @20');
    });
  });

  group('Pass 4.2.6: Fix 2 - Legacy entityLinks List migration is order-independent', () {
    test('duplicate ID with different generations: [G10, G20] vs [G20, G10] produces identical state', () {
      final linkG10 = makeLink('e1', name: 'G10', incarnation: makeHlc(10)).toMap();
      final linkG20 = makeLink('e1', name: 'G20', incarnation: makeHlc(20)).toMap();

      final mapOrder1 = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': [linkG10, linkG20],
      };

      final mapOrder2 = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': [linkG20, linkG10],
      };

      final state1 = RoomNodeState.fromMap(mapOrder1);
      final state2 = RoomNodeState.fromMap(mapOrder2);

      expect(state1.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(state2.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(state1.entityLinksCrdt.items['e1']?.value.displayName, 'G20');
      expect(state2.entityLinksCrdt.items['e1']?.value.displayName, 'G20');
      expect(state1.entityLinksCrdt.items['e1']?.value.incarnationTimestamp.physicalTime, 20);
      expect(state2.entityLinksCrdt.items['e1']?.value.incarnationTimestamp.physicalTime, 20);
      expect(state1.entityLinksCrdt.toMap(), state2.entityLinksCrdt.toMap());
    });

    test('same generation / same payload is deduplicated order-independently', () {
      final linkA = makeLink('e1', name: 'Same', incarnation: makeHlc(15)).toMap();
      final linkB = makeLink('e1', name: 'Same', incarnation: makeHlc(15)).toMap();

      final map = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': [linkA, linkB],
      };

      final state = RoomNodeState.fromMap(map);
      expect(state.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(state.entityLinksCrdt.items['e1']?.value.displayName, 'Same');
    });

    test('same generation / divergent payload fails deterministically with FormatException', () {
      final linkA = makeLink('e1', name: 'Payload A', incarnation: makeHlc(15)).toMap();
      final linkB = makeLink('e1', name: 'Payload B', incarnation: makeHlc(15)).toMap();

      final map1 = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': [linkA, linkB],
      };
      final map2 = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': [linkB, linkA],
      };

      expect(() => RoomNodeState.fromMap(map1), throwsA(isA<FormatException>()));
      expect(() => RoomNodeState.fromMap(map2), throwsA(isA<FormatException>()));
    });
  });

  group('Pass 4.2.6: Fix 3 - Explicit legacy compatibility boundary', () {
    test('normal constructor rejects non-EntityLinkCrdtSet dynamic value with ArgumentError', () {
      final legacyOrSet = CrdtOrSet<RoomEntityLink>();
      expect(
        () => RoomNodeState(
          roomId: 'room-1',
          roomCode: 'ROOM1',
          title: 'Room 1',
          entityLinksCrdt: legacyOrSet as dynamic,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copyWith rejects non-EntityLinkCrdtSet dynamic value with ArgumentError', () {
      final state = RoomNodeState(roomId: 'room-1', roomCode: 'ROOM1', title: 'Room 1');
      final legacyOrSet = CrdtOrSet<RoomEntityLink>();
      expect(
        () => state.copyWith(entityLinksCrdt: legacyOrSet as dynamic),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('RoomNodeState.fromLegacyCrdtOrSet explicitly accepts CrdtOrSet<RoomEntityLink>', () {
      var legacyOrSet = CrdtOrSet<RoomEntityLink>();
      final link = makeLink('e1', name: 'Legacy Link');
      legacyOrSet = legacyOrSet.add('e1', link, makeHlc(25));

      final state = RoomNodeState.fromLegacyCrdtOrSet(
        roomId: 'room-1',
        roomCode: 'ROOM1',
        title: 'Room 1',
        entityLinksCrdt: legacyOrSet,
      );

      expect(state.entityLinksCrdt, isA<EntityLinkCrdtSet>());
      expect(state.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(state.entityLinksCrdt.items['e1']?.value.displayName, 'Legacy Link');
    });

    test('fromMap with genuine legacy serialized CrdtOrSet remains supported', () {
      final legacyMap = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': {
          'items': {
            'e1': {
              'value': makeLink('e1', name: 'Serialized Legacy Link').toMap(),
              'timestamp': makeHlc(18).toMap(),
            }
          },
          'tombstones': <String, dynamic>{},
        },
      };

      final state = RoomNodeState.fromMap(legacyMap);
      expect(state.entityLinksCrdt, isA<EntityLinkCrdtSet>());
      expect(state.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(state.entityLinksCrdt.items['e1']?.value.displayName, 'Serialized Legacy Link');
    });
  });

  group('Pass 4.2.6: Fix 4 - Fresh re-add baseline semantics', () {
    test('stale full G1 snapshot passed to createOrReadd(..., freshTs) yields G2 baseline with fresh causal timestamps', () {
      final tsG1 = makeHlc(100);
      final initialLink = RoomEntityLink(
        entityId: 'e1',
        displayName: 'Hero G1',
        notes: 'Notes G1',
        incarnationTimestamp: tsG1,
        displayNameRegister: CrdtLwwRegister<String>(value: 'Hero G1', timestamp: tsG1),
        notesRegister: CrdtLwwRegister<String?>(value: 'Notes G1', timestamp: tsG1),
      );

      var set = EntityLinkCrdtSet();
      set = set.createOrReadd('e1', initialLink, tsG1);

      // Now tombstone at ts150
      final tsTomb = makeHlc(150);
      set = set.remove('e1', tsTomb);
      expect(set.items.containsKey('e1'), isFalse);

      // Caller creates fresh generation G2 at ts200, passing stale full snapshot of G1
      final tsG2 = makeHlc(200);
      final staleG1Snapshot = RoomEntityLink(
        entityId: 'e1',
        displayName: 'Hero G2',
        notes: 'Notes G2',
        incarnationTimestamp: tsG1, // Stale incarnation
        displayNameRegister: CrdtLwwRegister<String>(value: 'Hero G2', timestamp: tsG1), // Stale ts
        notesRegister: CrdtLwwRegister<String?>(value: 'Notes G2', timestamp: tsG1), // Stale ts
      );

      // Verify that stale snapshot has old G1 register timestamps
      expect(staleG1Snapshot.displayNameRegister.timestamp.physicalTime, 100);
      expect(staleG1Snapshot.notesRegister.timestamp.physicalTime, 100);

      final readdedSet = set.createOrReadd('e1', staleG1Snapshot, tsG2);

      expect(readdedSet.items.containsKey('e1'), isTrue);
      final g2Link = readdedSet.items['e1']!.value;

      // Invariant: old-generation replicated field timestamps must NOT masquerade as timestamps of the fresh generation
      expect(g2Link.displayName, 'Hero G2');
      expect(g2Link.notes, 'Notes G2');
      expect(g2Link.incarnationTimestamp, tsG2);
      expect(g2Link.displayNameRegister.timestamp, tsG2);
      expect(g2Link.notesRegister.timestamp, tsG2);

      // The item register in EntityLinkCrdtSet must also be stamped at tsG2
      expect(readdedSet.items['e1']!.timestamp, tsG2);
    });
  });

  group('Pass 4.2.6: Fix 6 - Serialization roundtrip', () {
    test('EntityLinkTombstone with legacyAddWins serialization roundtrip', () {
      final tombstone = EntityLinkTombstone(
        targetGeneration: makeHlc(42),
        timestamp: makeHlc(42),
        legacyAddWins: true,
      );
      final map = tombstone.toMap();
      expect(map['legacyAddWins'], isTrue);

      final restored = EntityLinkTombstone.fromMap(map);
      expect(restored.targetGeneration.physicalTime, 42);
      expect(restored.legacyAddWins, isTrue);

      final defaultTombstone = EntityLinkTombstone(
        targetGeneration: makeHlc(50),
        timestamp: makeHlc(50),
      );
      final defaultMap = defaultTombstone.toMap();
      expect(defaultMap.containsKey('legacyAddWins'), isFalse);
      final restoredDefault = EntityLinkTombstone.fromMap(defaultMap);
      expect(restoredDefault.legacyAddWins, isFalse);
    });

    test('Migrated EntityLinkCrdtSet serialization roundtrip', () {
      var orSet = CrdtOrSet<RoomEntityLink>();
      final link1 = makeLink('e1', name: 'Link 1');
      final link2 = makeLink('e2', name: 'Link 2');
      orSet = orSet.add('e1', link1, makeHlc(20));
      orSet = orSet.add('e2', link2, makeHlc(10));
      orSet = orSet.remove('e2', makeHlc(30));

      final migrated = EntityLinkCrdtSet.fromCrdtOrSet(orSet);
      final map = migrated.toMap();
      final restored = EntityLinkCrdtSet.fromMap(map);

      expect(restored.items.containsKey('e1'), isTrue);
      expect(restored.items.containsKey('e2'), isFalse);
      expect(restored.items['e1']?.value.displayName, 'Link 1');
      expect(restored.tombstones.containsKey('e2'), isTrue);
      expect(restored.tombstones['e2']!.targetGeneration.physicalTime, 30);
    });
  });

  group('Pass 4.2.6b - Collapse Legacy Entity-Link Migration to One-Time Explicit Upgrade Path', () {
    test('1. outer @30 / payload incarnation @10 vs tombstone @20 => ACTIVE after independent migration + merge', () {
      final linkA = makeLink('e1', name: 'Item @30', incarnation: makeHlc(10));
      var orSetA = CrdtOrSet<RoomEntityLink>();
      orSetA = orSetA.add('e1', linkA, makeHlc(30));
      final migratedA = EntityLinkCrdtSet.fromCrdtOrSet(orSetA);

      final legacyTombB = CrdtOrSet<RoomEntityLink>(
        items: const {},
        tombstones: {'e1': makeHlc(20)},
      );
      final migratedB = EntityLinkCrdtSet.fromCrdtOrSet(legacyTombB);

      final mergedAB = migratedA.merge(migratedB);
      final mergedBA = migratedB.merge(migratedA);

      expect(mergedAB.items.containsKey('e1'), isTrue);
      expect(mergedBA.items.containsKey('e1'), isTrue);
      expect(mergedAB.items['e1']?.value.displayName, 'Item @30');
      expect(mergedBA.items['e1']?.value.displayName, 'Item @30');
      expect(mergedAB.items['e1']?.value.incarnationTimestamp.physicalTime, 30);
    });

    test('2. outer @10 / payload incarnation @30 vs tombstone @20 => REMOVED after independent migration + merge', () {
      final linkA = makeLink('e1', name: 'Item @10', incarnation: makeHlc(30));
      var orSetA = CrdtOrSet<RoomEntityLink>();
      orSetA = orSetA.add('e1', linkA, makeHlc(10));
      final migratedA = EntityLinkCrdtSet.fromCrdtOrSet(orSetA);

      final legacyTombB = CrdtOrSet<RoomEntityLink>(
        items: const {},
        tombstones: {'e1': makeHlc(20)},
      );
      final migratedB = EntityLinkCrdtSet.fromCrdtOrSet(legacyTombB);

      final mergedAB = migratedA.merge(migratedB);
      final mergedBA = migratedB.merge(migratedA);

      expect(mergedAB.items.containsKey('e1'), isFalse);
      expect(mergedBA.items.containsKey('e1'), isFalse);
      expect(mergedAB.tombstones.containsKey('e1'), isTrue);
      expect(mergedBA.tombstones.containsKey('e1'), isTrue);
      expect(mergedAB.tombstones['e1']!.targetGeneration.physicalTime, 20);
    });

    test('3. same cases through legacy serialized RoomNodeState.fromMap', () {
      // Case 1: outer 30, payload incarnation 10 vs tombstone 20 => active
      final mapA1 = {
        'roomId': 'room-1',
        'roomCode': 'RC1',
        'entityLinks': {
          'items': {
            'e1': {
              'v': makeLink('e1', name: 'Item', incarnation: makeHlc(10)).toMap(),
              'ts': makeHlc(30).toMap(),
            },
          },
          'tombstones': <String, dynamic>{},
        },
      };
      final mapB1 = {
        'roomId': 'room-1',
        'roomCode': 'RC1',
        'entityLinks': {
          'items': <String, dynamic>{},
          'tombstones': {
            'e1': makeHlc(20).toMap(),
          },
        },
      };
      final stateA1 = RoomNodeState.fromMap(mapA1);
      final stateB1 = RoomNodeState.fromMap(mapB1);
      final merged1 = RoomNodeState.join(stateA1, stateB1);
      expect(merged1.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(merged1.entityLinksCrdt.items['e1']?.value.incarnationTimestamp.physicalTime, 30);

      // Case 2: outer 10, payload incarnation 30 vs tombstone 20 => removed
      final mapA2 = {
        'roomId': 'room-1',
        'roomCode': 'RC1',
        'entityLinks': {
          'items': {
            'e1': {
              'v': makeLink('e1', name: 'Item', incarnation: makeHlc(30)).toMap(),
              'ts': makeHlc(10).toMap(),
            },
          },
          'tombstones': <String, dynamic>{},
        },
      };
      final stateA2 = RoomNodeState.fromMap(mapA2);
      final stateB2 = RoomNodeState.fromMap(mapB1);
      final merged2 = RoomNodeState.join(stateA2, stateB2);
      expect(merged2.entityLinksCrdt.items.containsKey('e1'), isFalse);
      expect(merged2.entityLinksCrdt.tombstones.containsKey('e1'), isTrue);
      expect(merged2.entityLinksCrdt.tombstones['e1']!.targetGeneration.physicalTime, 20);
    });

    test('4. equal-timestamp legacy add-wins remains active', () {
      final ts = makeHlc(20);
      final linkA = makeLink('e1', name: 'Item @20', incarnation: makeHlc(15));
      var orSetA = CrdtOrSet<RoomEntityLink>();
      orSetA = orSetA.add('e1', linkA, ts);
      final migratedA = EntityLinkCrdtSet.fromCrdtOrSet(orSetA);

      final legacyTombB = CrdtOrSet<RoomEntityLink>(
        items: const {},
        tombstones: {'e1': ts},
      );
      final migratedB = EntityLinkCrdtSet.fromCrdtOrSet(legacyTombB);

      final merged = migratedA.merge(migratedB);
      expect(merged.items.containsKey('e1'), isTrue);
      expect(merged.items['e1']?.value.displayName, 'Item @20');
      expect(merged.items['e1']?.value.incarnationTimestamp, ts);
    });

    test('5. upgraded state serializes and reloads as native state without needing legacy migration again', () {
      final legacyMap = {
        'roomId': 'room-1',
        'roomCode': 'ROOM1',
        'title': 'Room 1',
        'entityLinks': {
          'items': {
            'e1': {
              'v': makeLink('e1', name: 'Legacy Link', incarnation: makeHlc(10)).toMap(),
              'ts': makeHlc(30).toMap(),
            }
          },
          'tombstones': {
            'e2': makeHlc(25).toMap(),
          },
        },
      };

      // 1. One-time upgrade from legacy format
      final upgradedState = RoomNodeState.fromMap(legacyMap);
      expect(upgradedState.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(upgradedState.entityLinksCrdt.items['e1']?.value.incarnationTimestamp.physicalTime, 30);
      expect(upgradedState.entityLinksCrdt.tombstones.containsKey('e2'), isTrue);

      // 2. Serializes as native state
      final nativeSerializedMap = upgradedState.toMap();
      expect(nativeSerializedMap.containsKey('entityLinks_crdt'), isTrue);
      final rawCrdt = nativeSerializedMap['entityLinks_crdt'] as Map;
      expect(rawCrdt.containsKey('items'), isTrue);
      expect(rawCrdt.containsKey('tombstones'), isTrue);
      final e2TombMap = (rawCrdt['tombstones'] as Map)['e2'] as Map;
      expect(e2TombMap.containsKey('targetGeneration'), isTrue);

      // 3. Reloads as native state without needing legacy migration
      final reloadedState = RoomNodeState.fromMap(nativeSerializedMap);
      expect(reloadedState.entityLinksCrdt.items.containsKey('e1'), isTrue);
      expect(reloadedState.entityLinksCrdt.items['e1']?.value.displayName, 'Legacy Link');
      expect(reloadedState.entityLinksCrdt.tombstones.containsKey('e2'), isTrue);
      expect(reloadedState, equals(upgradedState));
    });
  });
}
