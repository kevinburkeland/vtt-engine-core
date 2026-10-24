import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('CampaignProfile Active Map Tests', () {
    const validSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const validSha2 =
        'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e';

    final testRef = BlobRef(
      sha256Hex: validSha,
      byteSize: 1024,
      width: 1920,
      height: 1080,
      format: BlobFormat.webp,
    );

    final testRef2 = BlobRef(
      sha256Hex: validSha2,
      byteSize: 2048,
      width: 800,
      height: 600,
      format: BlobFormat.jpeg,
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
      expect(pRaw.activeMap, isNull);
      expect(pRaw.activeMapRegister, equals(CampaignProfile.noActiveMap));

      final pFactory = CampaignProfile(
        id: 'c_factory',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        nodeId: 'node_1',
      );
      expect(pFactory.activeMap, isNull);
      expect(pFactory.activeMapRegister, equals(CampaignProfile.noActiveMap));

      final pInitial = CampaignProfile.initial(
        id: 'c_initial',
        name: 'Initial',
        nodeId: 'node_1',
      );
      expect(pInitial.activeMap, isNull);
      expect(pInitial.activeMapRegister, equals(CampaignProfile.noActiveMap));

      final pDefault = CampaignProfile.defaultProfile(
        id: 'c_default',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );
      expect(pDefault.activeMap, isNull);
      expect(pDefault.activeMapRegister, equals(CampaignProfile.noActiveMap));

      final pPlaceholder = CampaignProfile.placeholder(
        id: 'c_placeholder',
        roomCode: 'RC-P',
        name: 'Placeholder',
        stagingTitle: 'Staging',
      );
      expect(pPlaceholder.activeMap, isNull);
      expect(pPlaceholder.activeMapRegister, equals(CampaignProfile.noActiveMap));
    });

    test('P2 (copyWith keeps the map across every parameter)', () {
      const initialTimestamp = HybridLogicalClock(
        physicalTime: 1000,
        logicalCounter: 0,
        nodeId: 'dm_node',
      );
      final base = CampaignProfile.defaultProfile(
        id: 'c_base',
        nodeId: 'dm_node',
        timestamp: initialTimestamp,
      ).withActiveMap(testRef, const HybridLogicalClock(physicalTime: 1050, logicalCounter: 0, nodeId: 'dm_node'));

      expect(base.activeMap, equals(testRef));
      final expectedReg = base.activeMapRegister;

      // Note: If any new named parameter is added to CampaignProfile.copyWith,
      // it MUST be added to this test list to verify it carries activeMapRegister through!
      final copyInvocations = <String, CampaignProfile Function()>{
        'id': () => base.copyWith(id: 'c_new_id'),
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
        'edition': () => base.copyWith(edition: const RulesetIdentifier('custom_rules')),
        'rulesetId': () => base.copyWith(rulesetId: 'custom_rules_2'),
        'createdAt': () => base.copyWith(createdAt: DateTime.utc(2025, 1, 1)),
        'lastPlayedAt': () => base.copyWith(lastPlayedAt: DateTime.utc(2027, 1, 1)),
        'roomState': () => base.copyWith(
              roomState: base.roomState.copyWith(
                title: 'Updated Room',
                titleTimestamp: const HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'dm_node'),
              ),
            ),
        'partyRoster': () => base.copyWith(
              partyRoster: const CrdtOrSet<String>.empty().add('char_1', 'char_1', initialTimestamp),
            ),
        'partyCharacterIds': () => base.copyWith(partyCharacterIds: const ['char_2']),
        'pinnedRuleIds': () => base.copyWith(pinnedRuleIds: const {'rule_x'}),
        'pinnedRules': () => base.copyWith(
              pinnedRules: const CrdtOrSet<String>.empty().add('rule_y', 'rule_y', initialTimestamp),
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
          copied.activeMapRegister,
          equals(expectedReg),
          reason: 'copyWith(${entry.key}) lost activeMapRegister',
        );
        expect(
          copied.activeMap,
          equals(testRef),
          reason: 'copyWith(${entry.key}) lost activeMap',
        );
      }
    });

    test('P3 (write method): withActiveMap transitions and rejects invalid timestamps', () {
      final base = CampaignProfile.defaultProfile(
        id: 'c1',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );

      const t1 = HybridLogicalClock(physicalTime: 1100, logicalCounter: 0, nodeId: 'node_1');
      const t2 = HybridLogicalClock(physicalTime: 1200, logicalCounter: 0, nodeId: 'node_1');

      final withMap = base.withActiveMap(testRef, t1);
      expect(withMap.activeMap, equals(testRef));
      expect(withMap.activeMapRegister.value, equals(testRef));
      expect(withMap.activeMapRegister.timestamp, equals(t1));

      final clearedMap = withMap.withActiveMap(null, t2);
      expect(clearedMap.activeMap, isNull);
      expect(clearedMap.activeMapRegister.value, isNull);
      expect(clearedMap.activeMapRegister.timestamp, equals(t2));

      // Throws ArgumentError for genesis
      expect(
        () => base.withActiveMap(testRef, HybridLogicalClock.genesis),
        throwsArgumentError,
      );

      // Throws ArgumentError for physicalTime == 0
      expect(
        () => base.withActiveMap(
          testRef,
          const HybridLogicalClock(physicalTime: 0, logicalCounter: 1, nodeId: 'node_1'),
        ),
        throwsArgumentError,
      );
    });

    test('P4 (extractor): extractCampaignProfileTimestamps includes activeMapRegister', () {
      final base = CampaignProfile.defaultProfile(
        id: 'c1',
        nodeId: 'node_1',
        timestamp: const HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node_1'),
      );

      // Default profile activeMapRegister is genesis (physicalTime == 0) -> not extracted
      final baseTimestamps = extractCampaignProfileTimestamps(base);
      expect(baseTimestamps.contains(CampaignProfile.noActiveMap.timestamp), isFalse);

      const tMap = HybridLogicalClock(physicalTime: 2500, logicalCounter: 1, nodeId: 'node_1');
      final withMap = base.withActiveMap(testRef, tMap);

      final withMapTimestamps = extractCampaignProfileTimestamps(withMap);
      expect(withMapTimestamps.contains(tMap), isTrue);
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

      final pSetT1 = pDefault.withActiveMap(testRef, t1);
      final pClearT2 = pSetT1.withActiveMap(null, t2);
      final pSetT2 = pDefault.withActiveMap(testRef, t2);
      final pClearT1 = pDefault.withActiveMap(null, t1);

      // 1. default vs set -> set wins in both orders
      final joinDefSet = CampaignProfile.join(pDefault, pSetT1);
      final joinSetDef = CampaignProfile.join(pSetT1, pDefault);
      expect(joinDefSet.activeMap, equals(testRef));
      expect(joinSetDef.activeMap, equals(testRef));
      expect(joinDefSet, equals(joinSetDef));

      // 2. set at t1 vs cleared at t2 > t1 -> cleared wins
      final joinSet1Clear2 = CampaignProfile.join(pSetT1, pClearT2);
      final joinClear2Set1 = CampaignProfile.join(pClearT2, pSetT1);
      expect(joinSet1Clear2.activeMap, isNull);
      expect(joinClear2Set1.activeMap, isNull);
      expect(joinSet1Clear2.activeMapRegister.timestamp, equals(t2));
      expect(joinSet1Clear2, equals(joinClear2Set1));

      // 3. set at t2 vs cleared at t1 -> set wins
      final joinSet2Clear1 = CampaignProfile.join(pSetT2, pClearT1);
      final joinClear1Set2 = CampaignProfile.join(pClearT1, pSetT2);
      expect(joinSet2Clear1.activeMap, equals(testRef));
      expect(joinClear1Set2.activeMap, equals(testRef));
      expect(joinSet2Clear1.activeMapRegister.timestamp, equals(t2));
      expect(joinSet2Clear1, equals(joinClear1Set2));

      // 4. two different refs at the same non-zero timestamp -> StateError
      final pCollisionA = pDefault.withActiveMap(testRef, t1);
      final pCollisionB = pDefault.withActiveMap(testRef2, t1);
      expect(() => CampaignProfile.join(pCollisionA, pCollisionB), throwsStateError);
      expect(() => CampaignProfile.join(pCollisionB, pCollisionA), throwsStateError);

      // 5. two different refs at genesis timestamp (built with raw) -> same winner in both orders, no throw
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
        activeMapRegister: CrdtLwwRegister(value: testRef, timestamp: HybridLogicalClock.genesis),
      );
      final pGenB = CampaignProfile.raw(
        id: 'c_gen',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
        activeMapRegister: CrdtLwwRegister(value: testRef2, timestamp: HybridLogicalClock.genesis),
      );
      final joinGenAB = CampaignProfile.join(pGenA, pGenB);
      final joinGenBA = CampaignProfile.join(pGenB, pGenA);
      expect(joinGenAB, equals(joinGenBA));
      expect(joinGenAB.activeMap, isNotNull);

      // ref vs null at genesis -> same winner in both orders, no throw
      final pGenNull = CampaignProfile.raw(
        id: 'c_gen',
        createdAt: now,
        lastPlayedAt: now,
        roomState: room,
        notesRegister: const CrdtLwwRegister(value: '', timestamp: HybridLogicalClock.genesis),
        activeMapRegister: CampaignProfile.noActiveMap,
      );
      final joinGenNullA = CampaignProfile.join(pGenNull, pGenA);
      final joinGenANull = CampaignProfile.join(pGenA, pGenNull);
      expect(joinGenNullA, equals(joinGenANull));

      // 6. Two profiles that differ only in activeMapRegister are not ==
      expect(pSetT1 == pDefault, isFalse);
      expect(pSetT1 == pSetT2, isFalse);
    });
  });
}
