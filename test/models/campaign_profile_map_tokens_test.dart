import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('CampaignProfile Map Tokens & Minion Owners Tests (PT1 - PT2)', () {
    const validSha1 =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const validSha2 =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('PT1 (profile): initial state, copyWith, write methods, timestamps, hashCode, tokensOnMap', () {
      final now = DateTime.utc(2026, 1, 1);
      const room = RoomNodeState.empty();

      // 1. All three fields start empty from every constructor
      final pRaw = CampaignProfile.raw(
        id: 'c_raw',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
      );
      expect(pRaw.mapTokens.isEmpty, isTrue);
      expect(pRaw.mapTokenCells.isEmpty, isTrue);
      expect(pRaw.minionOwners.isEmpty, isTrue);

      final pFactory = CampaignProfile(
        id: 'c_fac',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        nodeId: 'node_1',
      );
      expect(pFactory.mapTokens.isEmpty, isTrue);
      expect(pFactory.mapTokenCells.isEmpty, isTrue);
      expect(pFactory.minionOwners.isEmpty, isTrue);

      final pInitial = CampaignProfile.initial(
        id: 'c_init',
        name: 'Initial',
        nodeId: 'node_1',
        now: now,
      );
      expect(pInitial.mapTokens.isEmpty, isTrue);
      expect(pInitial.mapTokenCells.isEmpty, isTrue);
      expect(pInitial.minionOwners.isEmpty, isTrue);

      final pDefault = CampaignProfile.defaultProfile(
        id: 'c_def',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );
      expect(pDefault.mapTokens.isEmpty, isTrue);
      expect(pDefault.mapTokenCells.isEmpty, isTrue);
      expect(pDefault.minionOwners.isEmpty, isTrue);

      final pPlaceholder = CampaignProfile.placeholder(
        id: 'c_ph',
        roomCode: 'RC-1',
        name: 'Placeholder',
        stagingTitle: 'Staging',
      );
      expect(pPlaceholder.mapTokens.isEmpty, isTrue);
      expect(pPlaceholder.mapTokenCells.isEmpty, isTrue);
      expect(pPlaceholder.minionOwners.isEmpty, isTrue);

      // Populate base profile with items
      const t1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 1, nodeId: 'node_1');
      final tok1 = MapToken(
        id: 'tok_00000000000000000000000000000001',
        mapSha256Hex: validSha1,
        kind: MapTokenKind.character,
        refId: 'hero-1',
        label: 'H1',
      );
      final cell1 = MapTokenCell(col: 5, row: 5);

      final pBaseWithTokens = pDefault
          .withTokenPlaced(tok1, cell1, t1)
          .withMinionOwner('minion_1', 'hero-1', t1);

      // 2. copyWith with every other named parameter keeps all three
      // NOTE: If a new copyWith parameter is added to CampaignProfile, it must also be added here!
      final pCopied = pBaseWithTokens.copyWith(
        id: 'c_def_new',
        name: 'New Name',
        nameTimestamp: const HybridLogicalClock(physicalTime: 1005, logicalCounter: 0, nodeId: 'node_1'),
        edition: const RulesetIdentifier('dnd5e'),
        createdAt: now.add(const Duration(days: 1)),
        lastPlayedAt: now.add(const Duration(days: 2)),
        roomState: const RoomNodeState.empty(),
        partyCharacterIds: ['c1'],
        pinnedRuleIds: {'r1'},
        notesMarkdown: 'New notes',
        notesTimestamp: const HybridLogicalClock(physicalTime: 1006, logicalCounter: 0, nodeId: 'node_1'),
        activeMapRegister: CampaignProfile.noActiveMap,
        mapGridRegister: CampaignProfile.noMapGrid,
        partyPurse: const PartyPurse.empty(),
        memberPurses: const {},
        changeLog: const [],
      );
      expect(pCopied.mapTokens, equals(pBaseWithTokens.mapTokens));
      expect(pCopied.mapTokenCells, equals(pBaseWithTokens.mapTokenCells));
      expect(pCopied.minionOwners, equals(pBaseWithTokens.minionOwners));

      // 3. Each write method refuses genesis and physicalTime == 0
      const tZero = HybridLogicalClock(physicalTime: 0, logicalCounter: 1, nodeId: 'node_1');
      const tGenesis = HybridLogicalClock.genesis;

      for (final badTs in [tZero, tGenesis]) {
        expect(() => pDefault.withTokenPlaced(tok1, cell1, badTs), throwsArgumentError);
        expect(() => pBaseWithTokens.withTokenMoved(tok1.id, cell1, badTs), throwsArgumentError);
        expect(() => pBaseWithTokens.withTokenRemoved(tok1.id, badTs), throwsArgumentError);
        expect(() => pDefault.withMinionOwner('m1', 'slug', badTs), throwsArgumentError);
        expect(() => pDefault.withMinionOwner('m1', null, badTs), throwsArgumentError);
      }

      // 4. withTokenPlaced refuses a reused id, both while active and after removed
      const t2 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 1, nodeId: 'node_1');
      expect(() => pBaseWithTokens.withTokenPlaced(tok1, cell1, t2), throwsStateError);

      final pRemoved = pBaseWithTokens.withTokenRemoved(tok1.id, t2);
      const t3 = HybridLogicalClock(physicalTime: 3000, logicalCounter: 1, nodeId: 'node_1');
      expect(() => pRemoved.withTokenPlaced(tok1, cell1, t3), throwsStateError);

      // 5. withTokenMoved for unknown or removed id returns profile == input
      final pMovedUnknown = pBaseWithTokens.withTokenMoved('tok_unknown0000000000000000000000', cell1, t2);
      expect(pMovedUnknown, equals(pBaseWithTokens));

      final pMovedRemoved = pRemoved.withTokenMoved(tok1.id, cell1, t3);
      expect(pMovedRemoved, equals(pRemoved));

      // 6. withMinionOwner sets, changes and clears
      expect(pDefault.minionOwner('m1'), isNull);
      final pOwned = pDefault.withMinionOwner('m1', 'slug-1', t1);
      expect(pOwned.minionOwner('m1'), equals('slug-1'));
      final pOwnerChanged = pOwned.withMinionOwner('m1', 'slug-2', t2);
      expect(pOwnerChanged.minionOwner('m1'), equals('slug-2'));
      final pOwnerCleared = pOwnerChanged.withMinionOwner('m1', null, t3);
      expect(pOwnerCleared.minionOwner('m1'), isNull);

      expect(() => pDefault.withMinionOwner('', 'slug', t1), throwsArgumentError);
      expect(() => pDefault.withMinionOwner('m1', '', t1), throwsArgumentError);

      // 7. Extractor includes timestamps from all three fields, tombstones included
      final stamps = extractCampaignProfileTimestamps(pRemoved);
      expect(stamps.contains(t1), isTrue); // tok1 placed & cell1
      expect(stamps.contains(t2), isTrue); // tok1 removed tombstone

      // 8. Two profiles that differ only in one of the three fields are not ==
      final pDiffTokens = pDefault.copyWith(mapTokens: pBaseWithTokens.mapTokens);
      expect(pDiffTokens == pDefault, isFalse);

      final pDiffCells = pDefault.copyWith(mapTokenCells: pBaseWithTokens.mapTokenCells);
      expect(pDiffCells == pDefault, isFalse);

      final pDiffOwners = pDefault.copyWith(minionOwners: pBaseWithTokens.minionOwners);
      expect(pDiffOwners == pDefault, isFalse);

      // 9. For each field, 200 profiles that differ only in that field have at least 2 distinct hashCode values
      final tokenHashes = <int>{};
      final cellHashes = <int>{};
      final ownerHashes = <int>{};

      for (var i = 0; i < 200; i++) {
        final hexId = i.toRadixString(16).padLeft(32, '0');
        final t = MapToken(
          id: 'tok_$hexId',
          mapSha256Hex: validSha1,
          kind: MapTokenKind.character,
          refId: 'ref_$i',
          label: 'T',
        );
        final c = MapTokenCell(col: i % 100, row: (i * 2) % 100);
        final ts = HybridLogicalClock(physicalTime: 1000 + i, logicalCounter: 0, nodeId: 'node_1');

        tokenHashes.add(pDefault.copyWith(mapTokens: pDefault.mapTokens.add(t.id, t, ts)).hashCode);
        cellHashes.add(pDefault.copyWith(mapTokenCells: pDefault.mapTokenCells.add(t.id, c, ts)).hashCode);
        ownerHashes.add(pDefault.copyWith(minionOwners: pDefault.minionOwners.add('m_$i', 'slug_$i', ts)).hashCode);
      }
      expect(tokenHashes.length, greaterThanOrEqualTo(2));
      expect(cellHashes.length, greaterThanOrEqualTo(2));
      expect(ownerHashes.length, greaterThanOrEqualTo(2));

      // 10. tokensOnMap leaves out tokens of another map, tokens with no cell and removed tokens,
      // and orders by placement timestamp then id (include two tokens placed at timestamps that compare
      // in the opposite order to their ids).
      // tokA: id 'tok_aaaa...', placed at ts = 2000
      // tokB: id 'tok_bbbb...', placed at ts = 1000
      // tokA.id < tokB.id, but ts(tokB) < ts(tokA).
      // Expect tokensOnMap order: [tokB, tokA]!
      final tokA = MapToken(
        id: 'tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        mapSha256Hex: validSha1,
        kind: MapTokenKind.character,
        refId: 'hero-a',
        label: 'A',
      );
      final tokB = MapToken(
        id: 'tok_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        mapSha256Hex: validSha1,
        kind: MapTokenKind.character,
        refId: 'hero-b',
        label: 'B',
      );
      // Other map token
      final tokOtherMap = MapToken(
        id: 'tok_cccccccccccccccccccccccccccccccc',
        mapSha256Hex: validSha2,
        kind: MapTokenKind.character,
        refId: 'hero-c',
        label: 'C',
      );
      // Token with no cell
      final tokNoCell = MapToken(
        id: 'tok_dddddddddddddddddddddddddddddddd',
        mapSha256Hex: validSha1,
        kind: MapTokenKind.character,
        refId: 'hero-d',
        label: 'D',
      );
      // Removed token
      final tokRemoved = MapToken(
        id: 'tok_eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        mapSha256Hex: validSha1,
        kind: MapTokenKind.character,
        refId: 'hero-e',
        label: 'E',
      );

      const tsB = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1');
      const tsA = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'node_1');
      const tsOther = HybridLogicalClock(physicalTime: 1500, logicalCounter: 0, nodeId: 'node_1');
      const tsNoCell = HybridLogicalClock(physicalTime: 1600, logicalCounter: 0, nodeId: 'node_1');
      const tsRem = HybridLogicalClock(physicalTime: 1700, logicalCounter: 0, nodeId: 'node_1');
      const tsRemAct = HybridLogicalClock(physicalTime: 2500, logicalCounter: 0, nodeId: 'node_1');

      var pMulti = pDefault
          .withTokenPlaced(tokA, MapTokenCell(col: 1, row: 1), tsA)
          .withTokenPlaced(tokB, MapTokenCell(col: 2, row: 2), tsB)
          .withTokenPlaced(tokOtherMap, MapTokenCell(col: 3, row: 3), tsOther)
          .withTokenPlaced(tokRemoved, MapTokenCell(col: 4, row: 4), tsRem)
          .withTokenRemoved(tokRemoved.id, tsRemAct);

      // Add tokNoCell to mapTokens only, without cell
      pMulti = pMulti.copyWith(
        mapTokens: pMulti.mapTokens.add(tokNoCell.id, tokNoCell, tsNoCell),
      );

      final onMap1 = pMulti.tokensOnMap(validSha1);
      expect(onMap1.length, equals(2));
      expect(onMap1[0].token.id, equals(tokB.id)); // Placed first by timestamp!
      expect(onMap1[1].token.id, equals(tokA.id));

      final onMap2 = pMulti.tokensOnMap(validSha2);
      expect(onMap2.length, equals(1));
      expect(onMap2[0].token.id, equals(tokOtherMap.id));
    });

    test('PT2 (law: removal is final, at least 300 seeds)', () {
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed * 31337 + 7);
        const mapSha = validSha1;

        // Base profile with a few placed tokens and owners
        var base = CampaignProfile.defaultProfile(
          id: 'c_law_$seed',
          nodeId: 'base_node',
          timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'base_node'),
        );

        final knownTokens = <String, MapToken>{};
        for (var i = 0; i < 3; i++) {
          final tok = MapToken(
            id: "tok_${((seed + 1) * 1000000 + i).toRadixString(16).padLeft(32, '0')}",
            mapSha256Hex: mapSha,
            kind: MapTokenKind.character,
            refId: 'base_ref_$i',
            label: 'B$i',
          );
          knownTokens[tok.id] = tok;
          base = base.withTokenPlaced(
            tok,
            MapTokenCell(col: i, row: i),
            HybridLogicalClock(physicalTime: 1100 + i, logicalCounter: 0, nodeId: 'base_node'),
          );
        }
        for (var i = 0; i < 2; i++) {
          base = base.withMinionOwner(
            'minion_base_$i',
            'owner_$i',
            HybridLogicalClock(physicalTime: 1200 + i, logicalCounter: 0, nodeId: 'base_node'),
          );
        }

        final branchCount = rng.nextInt(3) + 2; // 2 to 4 branches
        final branches = <CampaignProfile>[];

        // Track expectations
        final expectedActiveTokens = <String, bool>{};
        final expectedLatestCell = <String, ({MapTokenCell cell, HybridLogicalClock ts})>{};
        final expectedMinionOwner = <String, ({String? owner, HybridLogicalClock ts})>{};

        for (final tok in base.mapTokens.items.values) {
          expectedActiveTokens[tok.value.id] = true;
          final cell = base.mapTokenCells.items[tok.value.id]!;
          expectedLatestCell[tok.value.id] = (cell: cell.value, ts: cell.timestamp);
        }
        for (final entry in base.minionOwners.items.entries) {
          expectedMinionOwner[entry.key] = (owner: entry.value.value, ts: entry.value.timestamp);
        }

        var globalTokenCounter = 0;

        for (var b = 0; b < branchCount; b++) {
          final branchClock = StatefulHlcClock(replicaId: ReplicaId('branch_${seed}_$b'));
          var branchProfile = base;
          final stepCount = rng.nextInt(11) + 5; // 5 to 15 steps

          for (var s = 0; s < stepCount; s++) {
            final action = rng.nextInt(4);
            final ts = branchClock.nextTimestamp();

            switch (action) {
              case 0: // place new token
                final tokId = "tok_${((seed + 1) * 1000000 + 100000 + globalTokenCounter).toRadixString(16).padLeft(32, '0')}";
                globalTokenCounter++;
                final tok = MapToken(
                  id: tokId,
                  mapSha256Hex: mapSha,
                  kind: MapTokenKind.monster,
                  refId: 'ref_$tokId',
                  label: 'N',
                );
                final cell = MapTokenCell(col: rng.nextInt(100), row: rng.nextInt(100));
                knownTokens[tokId] = tok;
                branchProfile = branchProfile.withTokenPlaced(tok, cell, ts);

                expectedActiveTokens[tokId] = true;
                final curCell = expectedLatestCell[tokId];
                if (curCell == null || ts.isAfter(curCell.ts)) {
                  expectedLatestCell[tokId] = (cell: cell, ts: ts);
                }

              case 1: // move any token the branch knows about
                final activeForMove = branchProfile.mapTokens.items.keys.toList();
                if (activeForMove.isNotEmpty) {
                  final targetId = activeForMove[rng.nextInt(activeForMove.length)];
                  final cell = MapTokenCell(col: rng.nextInt(100), row: rng.nextInt(100));
                  branchProfile = branchProfile.withTokenMoved(targetId, cell, ts);
                  final curCell = expectedLatestCell[targetId];
                  if (curCell == null || ts.isAfter(curCell.ts)) {
                    expectedLatestCell[targetId] = (cell: cell, ts: ts);
                  }
                }

              case 2: // remove one
                final activeForRemove = branchProfile.mapTokens.items.keys.toList();
                if (activeForRemove.isNotEmpty) {
                  final targetId = activeForRemove[rng.nextInt(activeForRemove.length)];
                  branchProfile = branchProfile.withTokenRemoved(targetId, ts);
                  expectedActiveTokens[targetId] = false;
                }

              case 3: // set or clear minion owner
                final minionId = 'minion_${rng.nextInt(5)}';
                final isClear = rng.nextBool();
                final ownerSlug = isClear ? null : 'owner_${rng.nextInt(5)}';
                branchProfile = branchProfile.withMinionOwner(minionId, ownerSlug, ts);

                final curOwner = expectedMinionOwner[minionId];
                if (curOwner == null || ts.isAfter(curOwner.ts)) {
                  expectedMinionOwner[minionId] = (owner: ownerSlug, ts: ts);
                }
            }
          }

          branches.add(branchProfile);
        }

        // Check join idempotence, commutativity, associativity on first 3 branches
        final b0 = branches[0];
        final b1 = branches[1];
        expect(CampaignProfile.join(b0, b0), equals(b0), reason: 'Idempotence failed seed $seed');
        expect(CampaignProfile.join(b0, b1), equals(CampaignProfile.join(b1, b0)), reason: 'Commutativity failed seed $seed');

        if (branches.length >= 3) {
          final b2 = branches[2];
          final j01_2 = CampaignProfile.join(CampaignProfile.join(b0, b1), b2);
          final j0_12 = CampaignProfile.join(b0, CampaignProfile.join(b1, b2));
          expect(j01_2, equals(j0_12), reason: 'Associativity failed seed $seed');
        }

        // Join all branches
        var joined = branches.first;
        for (var i = 1; i < branches.length; i++) {
          joined = CampaignProfile.join(joined, branches[i]);
        }

        // Check:
        // 1. A token is active in the result exactly when it was placed and no branch removed it.
        // In particular, a move with newer timestamp than removal in another branch does not bring token back!
        for (final entry in expectedActiveTokens.entries) {
          final tokId = entry.key;
          final shouldBeActive = entry.value;
          final isActuallyActive = joined.mapTokens.items.containsKey(tokId);
          expect(
            isActuallyActive,
            equals(shouldBeActive),
            reason: 'Token $tokId active state mismatch at seed $seed: expected $shouldBeActive, got $isActuallyActive',
          );
        }

        // 2. An active token's cell is the cell written with the greatest timestamp for it across all branches.
        for (final placed in joined.tokensOnMap(mapSha)) {
          final tokId = placed.token.id;
          final expCell = expectedLatestCell[tokId]!;
          expect(
            placed.cell,
            equals(expCell.cell),
            reason: 'Cell mismatch for active token $tokId at seed $seed',
          );
        }

        // 3. Each minion's owner is the set or clear with greatest timestamp across all branches.
        for (final entry in expectedMinionOwner.entries) {
          final minionId = entry.key;
          final expOwner = entry.value.owner;
          final actualOwner = joined.minionOwner(minionId);
          expect(
            actualOwner,
            equals(expOwner),
            reason: 'Minion $minionId owner mismatch at seed $seed: expected $expOwner, got $actualOwner',
          );
        }
      }
    });
  });
}
