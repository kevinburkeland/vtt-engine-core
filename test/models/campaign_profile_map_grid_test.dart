import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('CampaignProfile Map Grid Tests (G4)', () {
    const validSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const validSha2 =
        'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e';

    final testGrid = MapGrid(
      mapSha256Hex: validSha,
      cellCentiPx: 5000,
      offsetXCentiPx: 100,
      offsetYCentiPx: 200,
      feetPerCell: 5,
      visible: true,
    );

    final testGrid2 = MapGrid(
      mapSha256Hex: validSha2,
      cellCentiPx: 2500,
      offsetXCentiPx: 50,
      offsetYCentiPx: 75,
      feetPerCell: 10,
      visible: false,
    );

    test('P1 (defaults): raw, CampaignProfile, initial, defaultProfile, placeholder', () {
      final now = DateTime.utc(2026, 1, 1);
      final room = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-1',
        title: 'Title',
        titleTimestamp: const HybridLogicalClock(physicalTime: 100, logicalCounter: 0, nodeId: 'node_1'),
      );

      final pRaw = CampaignProfile.raw(
        id: 'c_raw',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock.genesis,
        ),
      );
      expect(pRaw.mapGrid, isNull);
      expect(pRaw.mapGridRegister, equals(CampaignProfile.noMapGrid));

      final pFactory = CampaignProfile(
        id: 'c_factory',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        nodeId: 'node_1',
      );
      expect(pFactory.mapGrid, isNull);
      expect(pFactory.mapGridRegister, equals(CampaignProfile.noMapGrid));

      final pInitial = CampaignProfile.initial(
        id: 'c_initial',
        name: 'Initial',
        nodeId: 'node_1',
      );
      expect(pInitial.mapGrid, isNull);
      expect(pInitial.mapGridRegister, equals(CampaignProfile.noMapGrid));

      final pDefault = CampaignProfile.defaultProfile(
        id: 'c_default',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );
      expect(pDefault.mapGrid, isNull);
      expect(pDefault.mapGridRegister, equals(CampaignProfile.noMapGrid));

      final pPlaceholder = CampaignProfile.placeholder(
        id: 'c_placeholder',
        roomCode: 'RC-P',
        name: 'Placeholder',
        stagingTitle: 'Staging',
      );
      expect(pPlaceholder.mapGrid, isNull);
      expect(pPlaceholder.mapGridRegister, equals(CampaignProfile.noMapGrid));
    });

    test('P2 (copyWith retention): copyWith with every other named parameter keeps mapGridRegister', () {
      const stamp = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'dm_node');
      final expectedReg = CrdtLwwRegister<MapGrid?>(
        value: testGrid,
        timestamp: stamp,
      );

      final base = CampaignProfile.defaultProfile(
        id: 'c1',
        nodeId: 'dm_node',
        timestamp: stamp,
      ).copyWith(mapGridRegister: expectedReg);

      expect(base.mapGrid, equals(testGrid));
      expect(base.mapGridRegister, equals(expectedReg));

      // Exhaustive named parameter map. If a new parameter is added to copyWith,
      // it MUST be added to this map to ensure mapGridRegister is retained!
      final copyInvocations = <String, CampaignProfile Function()>{
        'id': () => base.copyWith(id: 'new_id'),
        'name': () => base.copyWith(
              name: 'New Name',
              nameTimestamp: const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
            ),
        'nameRegister': () => base.copyWith(
              nameRegister: const CrdtLwwRegister(
                value: 'New Name Reg',
                timestamp: HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'edition': () => base.copyWith(edition: const RulesetIdentifier('dnd5e_2024')),
        'rulesetId': () => base.copyWith(rulesetId: 'dnd5e_2014'),
        'createdAt': () => base.copyWith(createdAt: DateTime.utc(2026, 2, 1)),
        'lastPlayedAt': () => base.copyWith(lastPlayedAt: DateTime.utc(2026, 2, 2)),
        'roomState': () => base.copyWith(
              roomState: RoomNodeState(
                roomId: 'r_new',
                roomCode: 'RC-2',
                title: 'New Room',
                titleTimestamp: const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'partyRoster': () => base.copyWith(
              partyRoster: const CrdtOrSet<String>.empty().add(
                'char_1',
                'char_1',
                const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'partyCharacterIds': () => base.copyWith(partyCharacterIds: ['char_2']),
        'pinnedRuleIds': () => base.copyWith(pinnedRuleIds: {'rule_1'}),
        'pinnedRules': () => base.copyWith(
              pinnedRules: const CrdtOrSet<String>.empty().add(
                'rule_1',
                'rule_1',
                const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'notesMarkdown': () => base.copyWith(
              notesMarkdown: 'New notes',
              notesTimestamp: const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
            ),
        'notesRegister': () => base.copyWith(
              notesRegister: const CrdtLwwRegister(
                value: 'New notes reg',
                timestamp: HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'activeMapRegister': () => base.copyWith(
              activeMapRegister: const CrdtLwwRegister<BlobRef?>(
                value: null,
                timestamp: HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'partyPurse': () => base.copyWith(
              partyPurse: const PartyPurse.empty().modifyDenomination('gold', 10, replicaId: ReplicaId('dm_node')),
            ),
        'memberPurses': () => base.copyWith(
              memberPurses: const {'char_1': PartyPurse.empty()},
            ),
        'changeLog': () => base.copyWith(
              changeLog: [
                PartyEvent(
                  id: 'ev1',
                  roomCode: 'RC-1',
                  type: 'test',
                  playerName: 'Player',
                  details: 'Event',
                  timestamp: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
      };

      for (final entry in copyInvocations.entries) {
        final copied = entry.value();
        expect(
          copied.mapGridRegister,
          equals(expectedReg),
          reason: 'copyWith(${entry.key}) lost mapGridRegister',
        );
        expect(
          copied.mapGrid,
          equals(testGrid),
          reason: 'copyWith(${entry.key}) lost mapGrid',
        );
      }
    });

    test('P3 (write method): withMapGrid transitions and rejects invalid timestamps', () {
      final base = CampaignProfile.defaultProfile(
        id: 'c1',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );

      const t1 = HybridLogicalClock(physicalTime: 1100, logicalCounter: 0, nodeId: 'node_1');
      const t2 = HybridLogicalClock(physicalTime: 1200, logicalCounter: 0, nodeId: 'node_1');

      final withGrid = base.withMapGrid(testGrid, t1);
      expect(withGrid.mapGrid, equals(testGrid));
      expect(withGrid.mapGridRegister.value, equals(testGrid));
      expect(withGrid.mapGridRegister.timestamp, equals(t1));

      final clearedGrid = withGrid.withMapGrid(null, t2);
      expect(clearedGrid.mapGrid, isNull);
      expect(clearedGrid.mapGridRegister.value, isNull);
      expect(clearedGrid.mapGridRegister.timestamp, equals(t2));

      // Throws ArgumentError for genesis
      expect(
        () => base.withMapGrid(testGrid, HybridLogicalClock.genesis),
        throwsArgumentError,
      );

      // Throws ArgumentError for physicalTime == 0
      expect(
        () => base.withMapGrid(
          testGrid,
          const HybridLogicalClock(physicalTime: 0, logicalCounter: 1, nodeId: 'node_1'),
        ),
        throwsArgumentError,
      );
    });

    test('P4 (extractor): extractCampaignProfileTimestamps includes mapGridRegister', () {
      final base = CampaignProfile.defaultProfile(
        id: 'c1',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );

      // Default profile mapGridRegister is genesis (physicalTime == 0) -> not extracted
      final baseTimestamps = extractCampaignProfileTimestamps(base);
      expect(baseTimestamps.contains(CampaignProfile.noMapGrid.timestamp), isFalse);

      const tGrid = HybridLogicalClock(physicalTime: 2500, logicalCounter: 1, nodeId: 'node_1');
      final withGrid = base.withMapGrid(testGrid, tGrid);

      final withGridTimestamps = extractCampaignProfileTimestamps(withGrid);
      expect(withGridTimestamps.contains(tGrid), isTrue);
    });

    test('P5 (join): deterministic join semantics and equality checks', () {
      const tBase = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1');
      final pDefault = CampaignProfile.defaultProfile(
        id: 'c_join',
        nodeId: 'node_1',
        timestamp: tBase,
      );

      const t1 = HybridLogicalClock(physicalTime: 1100, logicalCounter: 0, nodeId: 'node_1');
      const t2 = HybridLogicalClock(physicalTime: 1200, logicalCounter: 0, nodeId: 'node_2');

      final pSetT1 = pDefault.withMapGrid(testGrid, t1);
      final pClearT2 = pSetT1.withMapGrid(null, t2);
      final pSetT2 = pDefault.withMapGrid(testGrid, t2);
      final pClearT1 = pDefault.withMapGrid(null, t1);

      // 1. default vs set -> set wins in both orders
      final joinDefSet = CampaignProfile.join(pDefault, pSetT1);
      final joinSetDef = CampaignProfile.join(pSetT1, pDefault);
      expect(joinDefSet.mapGrid, equals(testGrid));
      expect(joinSetDef.mapGrid, equals(testGrid));
      expect(joinDefSet, equals(joinSetDef));

      // 2. set at t1 vs cleared at t2 > t1 -> cleared wins
      final joinSet1Clear2 = CampaignProfile.join(pSetT1, pClearT2);
      final joinClear2Set1 = CampaignProfile.join(pClearT2, pSetT1);
      expect(joinSet1Clear2.mapGrid, isNull);
      expect(joinClear2Set1.mapGrid, isNull);
      expect(joinSet1Clear2.mapGridRegister.timestamp, equals(t2));
      expect(joinSet1Clear2, equals(joinClear2Set1));

      // 3. set at t2 vs cleared at t1 -> set wins
      final joinSet2Clear1 = CampaignProfile.join(pSetT2, pClearT1);
      final joinClear1Set2 = CampaignProfile.join(pClearT1, pSetT2);
      expect(joinSet2Clear1.mapGrid, equals(testGrid));
      expect(joinClear1Set2.mapGrid, equals(testGrid));
      expect(joinSet2Clear1.mapGridRegister.timestamp, equals(t2));
      expect(joinSet2Clear1, equals(joinClear1Set2));

      // 4. two different grids at the same non-zero timestamp -> StateError
      final pCollisionA = pDefault.withMapGrid(testGrid, t1);
      final pCollisionB = pDefault.withMapGrid(testGrid2, t1);
      expect(() => CampaignProfile.join(pCollisionA, pCollisionB), throwsStateError);
      expect(() => CampaignProfile.join(pCollisionB, pCollisionA), throwsStateError);

      // 5. two different grids at genesis timestamp (built with raw) -> same winner in both orders, no throw
      final now = DateTime.utc(2026, 1, 1);
      final room = RoomNodeState(
        roomId: 'r1',
        roomCode: 'RC-1',
        title: 'Title',
        titleTimestamp: tBase,
      );
      final pGenA = CampaignProfile.raw(
        id: 'c_gen',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
        mapGridRegister: CrdtLwwRegister(value: testGrid, timestamp: HybridLogicalClock.genesis),
      );
      final pGenB = CampaignProfile.raw(
        id: 'c_gen',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
        mapGridRegister: CrdtLwwRegister(value: testGrid2, timestamp: HybridLogicalClock.genesis),
      );
      final joinGenAB = CampaignProfile.join(pGenA, pGenB);
      final joinGenBA = CampaignProfile.join(pGenB, pGenA);
      expect(joinGenAB, equals(joinGenBA));
      expect(joinGenAB.mapGrid, isNotNull);

      // grid vs null at genesis -> same winner in both orders, no throw
      final pGenNull = CampaignProfile.raw(
        id: 'c_gen',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
        mapGridRegister: CampaignProfile.noMapGrid,
      );
      final joinGenNullA = CampaignProfile.join(pGenNull, pGenA);
      final joinGenANull = CampaignProfile.join(pGenA, pGenNull);
      expect(joinGenNullA, equals(joinGenANull));

      // 6. Two profiles that differ only in mapGridRegister are not ==
      expect(pSetT1 == pDefault, isFalse);
      expect(pSetT1 == pSetT2, isFalse);
    });
  });
}
