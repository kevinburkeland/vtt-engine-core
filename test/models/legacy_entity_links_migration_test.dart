import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';

void main() {
  group('Legacy Entity Link Migration (Pass 4.2.7)', () {
    final fixturesDir = Directory('test/fixtures/legacy_entity_links');

    Map<String, dynamic> loadFixtureJson(String filename) {
      final file = File('${fixturesDir.path}/$filename');
      expect(file.existsSync(), isTrue, reason: 'Fixture $filename must exist');
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }

    test('1. Golden Fixture: item_only loads with incarnationTimestamp == outer ts and active', () {
      final json = loadFixtureJson('item_only.json');
      final room = RoomNodeState.fromMap(json);

      expect(room.entityLinks.length, 1);
      final link = room.entityLinks.first;
      expect(link.entityId, 'X');
      expect(link.displayName, 'Goblin');
      expect(link.incarnationTimestamp.physicalTime, 30);
      expect(room.entityLinksCrdt.items.containsKey('X'), isTrue);
      expect(room.entityLinksCrdt.tombstones.containsKey('X'), isFalse);
    });

    test('2. Golden Fixture: tombstone_only loads with legacyAddWins tombstone and removed', () {
      final json = loadFixtureJson('tombstone_only.json');
      final room = RoomNodeState.fromMap(json);

      expect(room.entityLinks.isEmpty, isTrue);
      expect(room.entityLinksCrdt.isRemoved('X'), isTrue);
      final tomb = room.entityLinksCrdt.tombstones['X']!;
      expect(tomb.targetGeneration.physicalTime, 20);
      expect(tomb.timestamp.physicalTime, 20);
      expect(tomb.legacyAddWins, isTrue);
    });

    test('3. Golden Fixture: item30_tomb20 raw map loads with item winning', () {
      final json = loadFixtureJson('item30_tomb20.json');
      final room = RoomNodeState.fromMap(json);

      expect(room.entityLinks.length, 1);
      final link = room.entityLinks.first;
      expect(link.entityId, 'X');
      expect(link.incarnationTimestamp.physicalTime, 30);
      expect(room.entityLinksCrdt.items.containsKey('X'), isTrue);
    });

    test('4. Golden Fixture: item20_tomb20 raw map loads with item winning on tie (Add-Wins)', () {
      final json = loadFixtureJson('item20_tomb20.json');
      final room = RoomNodeState.fromMap(json);

      expect(room.entityLinks.length, 1);
      final link = room.entityLinks.first;
      expect(link.entityId, 'X');
      expect(link.incarnationTimestamp.physicalTime, 20);
      expect(room.entityLinksCrdt.items.containsKey('X'), isTrue);
    });

    test('5. Golden Fixture: item10_tomb20 raw map loads with tombstone winning (removed)', () {
      final json = loadFixtureJson('item10_tomb20.json');
      final room = RoomNodeState.fromMap(json);

      expect(room.entityLinks.isEmpty, isTrue);
      expect(room.entityLinksCrdt.isRemoved('X'), isTrue);
      final tomb = room.entityLinksCrdt.tombstones['X']!;
      expect(tomb.targetGeneration.physicalTime, 20);
      expect(tomb.legacyAddWins, isTrue);
    });

    test('6. Golden Fixture: mixed.json correctly reconciles all IDs', () {
      final json = loadFixtureJson('mixed.json');
      final room = RoomNodeState.fromMap(json);

      final activeIds = room.entityLinks.map((l) => l.entityId).toSet();
      expect(activeIds, contains('id_item_only'));
      expect(activeIds, contains('id_item30_tomb20'));
      expect(activeIds, contains('id_item20_tomb20'));
      expect(activeIds, isNot(contains('id_tomb_only')));
      expect(activeIds, isNot(contains('id_item10_tomb20')));

      expect(room.entityLinksCrdt.isRemoved('id_tomb_only'), isTrue);
      expect(room.entityLinksCrdt.isRemoved('id_item10_tomb20'), isTrue);
    });

    test('7. Cross-replica merge of loaded fixtures matches expected semantics', () {
      final item30Json = Map<String, dynamic>.from(loadFixtureJson('item_only.json'))
        ..['roomId'] = 'common_room'
        ..['roomCode'] = 'RM-common'
        ..['title'] = 'Common Room';
      final tomb20Json = Map<String, dynamic>.from(loadFixtureJson('tombstone_only.json'))
        ..['roomId'] = 'common_room'
        ..['roomCode'] = 'RM-common'
        ..['title'] = 'Common Room';

      final repA30 = RoomNodeState.fromMap(item30Json);
      final repB20 = RoomNodeState.fromMap(tomb20Json);

      // Replica A (@30) + Replica B (@20) -> Item wins
      final joined30_20 = RoomNodeState.join(repA30, repB20);
      expect(joined30_20.entityLinks.map((l) => l.entityId), contains('X'));

      // Replica with item @20 vs tomb @20 -> Item wins on tie
      final item20Json = {
        ...item30Json,
        'entityLinks_crdt': {
          'items': {
            'X': {
              'v': {'entityId': 'X', 'displayName': 'Goblin', 'refType': 'npc'},
              'ts': {'pt': 20, 'lc': 0, 'node': 'b'},
            },
          },
          'tombstones': {},
        },
      };
      final repA20 = RoomNodeState.fromMap(item20Json);
      final joined20_20 = RoomNodeState.join(repA20, repB20);
      expect(joined20_20.entityLinks.map((l) => l.entityId), contains('X'));

      // Replica with item @10 vs tomb @20 -> Tombstone wins
      final item10Json = {
        ...item30Json,
        'entityLinks_crdt': {
          'items': {
            'X': {
              'v': {'entityId': 'X', 'displayName': 'Goblin', 'refType': 'npc'},
              'ts': {'pt': 10, 'lc': 0, 'node': 'a'},
            },
          },
          'tombstones': {},
        },
      };
      final repA10 = RoomNodeState.fromMap(item10Json);
      final joined10_20 = RoomNodeState.join(repA10, repB20);
      expect(joined10_20.entityLinks.map((l) => l.entityId), isNot(contains('X')));
      expect(joined10_20.entityLinksCrdt.isRemoved('X'), isTrue);
    });

    test('8. Round trip: migrated record saves with format marker and reloads equal without migrating', () {
      final legacyJson = loadFixtureJson('mixed.json');
      final migrated = RoomNodeState.fromMap(legacyJson);

      final savedMap = migrated.toMap();
      expect(savedMap['entityLinks_format'], 2);

      final reloaded = RoomNodeState.fromMap(savedMap);
      expect(reloaded, equals(migrated));
      expect(reloaded.entityLinksCrdt, equals(migrated.entityLinksCrdt));
      expect(reloaded.entityLinks, equals(migrated.entityLinks));
    });

    test('9. Native records saved by starting head 9252069 still load unchanged', () {
      final nativeJson = loadFixtureJson('native_starting_head.json');
      final room = RoomNodeState.fromMap(nativeJson);

      expect(room.entityLinks.length, 1);
      final link = room.entityLinks.first;
      expect(link.entityId, 'native_1');
      expect(link.displayName, 'Native Goblin');
      expect(link.incarnationTimestamp.physicalTime, 50);

      expect(room.entityLinksCrdt.isRemoved('native_tomb'), isTrue);
      final tomb = room.entityLinksCrdt.tombstones['native_tomb']!;
      expect(tomb.targetGeneration.physicalTime, 40);
      expect(tomb.timestamp.physicalTime, 45);
      expect(tomb.legacyAddWins, isFalse);
    });

    test('10. Malformed entityLinks_crdt fails loudly without silent fallback', () {
      expect(
        () => RoomNodeState.fromMap({
          'roomId': 'r1',
          'roomCode': 'RM-1',
          'title': 'R1',
          'entityLinks_crdt': 'not-a-map',
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => RoomNodeState.fromMap({
          'roomId': 'r1',
          'roomCode': 'RM-1',
          'title': 'R1',
          'entityLinks_crdt': {
            'items': {'X': 'not-a-map'},
          },
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => RoomNodeState.fromMap({
          'roomId': 'r1',
          'roomCode': 'RM-1',
          'title': 'R1',
          'entityLinks_crdt': {
            'tombstones': {'X': 'not-a-map'},
          },
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => RoomNodeState.fromMap({
          'roomId': 'r1',
          'roomCode': 'RM-1',
          'title': 'R1',
          'entityLinks_crdt': {
            'tombstones': {'X': {'invalid': 'hlc'}},
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('11. Law test over >= 500 seeded random legacy states: visible(load(A) ⊔ load(B)) == visible(load(A ⊔_legacy B))', () {
      final random = Random(42);
      int checkedCount = 0;
      int skippedCount = 0;

      final entityPool = ['link_alpha', 'link_beta', 'link_gamma', 'link_delta', 'link_epsilon'];
      final nodePool = ['node_a', 'node_b', 'node_c'];

      CrdtOrSet<RoomEntityLink> generateLegacySet() {
        final items = <String, CrdtLwwRegister<RoomEntityLink>>{};
        final tombstones = <String, HybridLogicalClock>{};

        for (final id in entityPool) {
          final choice = random.nextInt(4); // 0: none, 1: item only, 2: tomb only, 3: both
          final ptItem = 10 * (1 + random.nextInt(5)); // 10, 20, 30, 40, 50
          final ptTomb = 10 * (1 + random.nextInt(5));

          final nodeItem = nodePool[random.nextInt(nodePool.length)];
          final nodeTomb = nodePool[random.nextInt(nodePool.length)];

          final tsItem = HybridLogicalClock(physicalTime: ptItem, logicalCounter: 0, nodeId: nodeItem);
          final tsTomb = HybridLogicalClock(physicalTime: ptTomb, logicalCounter: 0, nodeId: nodeTomb);

          if (choice == 1 || choice == 3) {
            final link = RoomEntityLink(
              entityId: id,
              displayName: 'Name_$id',
              refType: 'npc',
            );
            items[id] = CrdtLwwRegister<RoomEntityLink>(value: link, timestamp: tsItem);
          }
          if (choice == 2 || choice == 3) {
            tombstones[id] = tsTomb;
          }
        }

        return CrdtOrSet<RoomEntityLink>(items: items, tombstones: tombstones);
      }

      Map<String, dynamic> serializeLegacyRoom(String id, CrdtOrSet<RoomEntityLink> set) {
        final itemsMap = <String, dynamic>{};
        set.items.forEach((key, reg) {
          itemsMap[key] = {
            'v': {
              'entityId': reg.value.entityId,
              'displayName': reg.value.displayName,
              'refType': 'npc',
            },
            'ts': reg.timestamp.toMap(),
          };
        });

        final tombsMap = <String, dynamic>{};
        set.tombstones.forEach((key, ts) {
          tombsMap[key] = ts.toMap();
        });

        return {
          'roomId': id,
          'roomCode': 'RM-$id',
          'title': 'Room $id',
          'entityLinks': <dynamic>[],
          'entityLinks_crdt': {
            'items': itemsMap,
            'tombstones': tombsMap,
          },
        };
      }

      const int totalIterations = 550;
      for (int i = 0; i < totalIterations; i++) {
        final legacySetA = generateLegacySet();
        final legacySetB = generateLegacySet();

        CrdtOrSet<RoomEntityLink> legacyMerged;
        try {
          legacyMerged = legacySetA.merge(legacySetB);
        } catch (_) {
          // Identical timestamp collision with divergent payload: skip
          skippedCount++;
          continue;
        }

        const commonRoomId = 'common_law_room';
        final roomA = RoomNodeState.fromMap(serializeLegacyRoom(commonRoomId, legacySetA));
        final roomB = RoomNodeState.fromMap(serializeLegacyRoom(commonRoomId, legacySetB));

        final migratedJoined = RoomNodeState.join(roomA, roomB);
        final legacyMergedLoaded = RoomNodeState.fromMap(serializeLegacyRoom(commonRoomId, legacyMerged));

        final visibleMigrated = migratedJoined.entityLinks.map((l) => l.entityId).toSet();
        final visibleLegacy = legacyMergedLoaded.entityLinks.map((l) => l.entityId).toSet();

        expect(
          visibleMigrated,
          equals(visibleLegacy),
          reason: 'Lattice equivalence violated on iteration $i: migrated=$visibleMigrated, legacy=$visibleLegacy',
        );

        // Also assert all visible link payloads match
        for (final id in visibleMigrated) {
          final linkMigrated = migratedJoined.entityLinks.firstWhere((l) => l.entityId == id);
          final linkLegacy = legacyMergedLoaded.entityLinks.firstWhere((l) => l.entityId == id);
          expect(linkMigrated.displayName, equals(linkLegacy.displayName));
        }

        checkedCount++;
      }

      expect(checkedCount, greaterThanOrEqualTo(500));
      expect(skippedCount, greaterThanOrEqualTo(0));
    });
  });
}
