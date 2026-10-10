import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('Cold Iron Birdcage — Pass 3.1: CRDT Timestamp Authority & Reconstruction Closure', () {
    const defaultSeed = 0x1234ABCD;

    group('A. Guarantee Active HLC Write Uniqueness', () {
      test('Test 1: physical clock returns SAME millisecond twice -> monotonic progression', () {
        int simulatedTime = 1700000000000;
        final replicaId = ReplicaId('writer-node-1');
        final clock = StatefulHlcClock(
          replicaId: replicaId,
          timeProvider: () => simulatedTime,
        );

        final writeA = clock.nextTimestamp();
        final writeB = clock.nextTimestamp();

        expect(writeA, isNot(equals(writeB)));
        expect(writeB.isAfter(writeA), isTrue);
        expect(writeA.nodeId, equals(replicaId.value));
        expect(writeB.nodeId, equals(replicaId.value));
        expect(writeA.physicalTime, equals(simulatedTime));
        expect(writeB.physicalTime, equals(simulatedTime));
        expect(writeA.logicalCounter, equals(0));
        expect(writeB.logicalCounter, equals(1));
      });

      test('Test 2: physical clock moves backward -> next timestamp strictly after previous', () {
        int simulatedTime = 1700000000500;
        final replicaId = ReplicaId('writer-node-back');
        final clock = StatefulHlcClock(
          replicaId: replicaId,
          timeProvider: () => simulatedTime,
        );

        final t1 = clock.nextTimestamp();
        expect(t1.physicalTime, equals(1700000000500));
        expect(t1.logicalCounter, equals(0));

        // Clock moves backward by 200ms
        simulatedTime = 1700000000300;
        final t2 = clock.nextTimestamp();

        expect(t2.isAfter(t1), isTrue);
        expect(t2.physicalTime, equals(1700000000500));
        expect(t2.logicalCounter, equals(1));
        expect(t2.nodeId, equals(replicaId.value));

        // Another write while clock still in past
        final t3 = clock.nextTimestamp();
        expect(t3.isAfter(t2), isTrue);
        expect(t3.logicalCounter, equals(2));
      });
    });

    group('B & C. RoomNodeState Deterministic Legacy Reconstruction & copyWith', () {
      test('RoomNodeState.copyWith does not invent causal history or accept loose raw types', () {
        final initialRoom = RoomNodeState(
          roomId: 'r-1',
          roomCode: 'R100',
          title: 'Dungeon Room',
        );

        final p = EncounterParticipant(
          participantId: 'p-hero',
          entityLink: RoomEntityLink(entityId: 'e-1', displayName: 'Hero'),
          currentHp: 25,
          maxHp: 25,
        );
        final encSet = const CrdtOrSet<EncounterParticipant>.empty().add(
          p.participantId,
          p,
          const HybridLogicalClock(physicalTime: 10, logicalCounter: 0, nodeId: 'n1'),
        );

        final updated = initialRoom.copyWith(activeEncounter: encSet);
        expect(updated.activeEncounterList.length, equals(1));
        expect(updated.activeEncounter.items['p-hero']!.timestamp.nodeId, equals('n1'));
      });

      test('Deserialize same legacy map twice with real time advancing produces identical state and hashCode', () async {
        final legacyMap = <String, dynamic>{
          'roomId': 'room-legacy-1',
          'roomCode': 'RL1',
          'title': 'Legacy Tomb',
          'activeMinions': [
            {'id': 'min-1', 'name': 'Skeleton A', 'hp': 13},
            {'id': 'min-2', 'name': 'Skeleton B', 'hp': 13},
          ],
          'activeEncounter': [
            {
              'participantId': 'part-1',
              'entityLink': {'entityId': 'ent-1', 'displayName': 'Fighter'},
              'currentHp': 30,
              'maxHp': 30,
            },
          ],
        };

        final resultA = RoomNodeState.fromMap(legacyMap);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final resultB = RoomNodeState.fromMap(legacyMap);

        expect(resultA == resultB, isTrue);
        expect(resultA.hashCode, equals(resultB.hashCode));
        expect(resultA.activeMinions, equals(resultB.activeMinions));
        expect(resultA.activeEncounter, equals(resultB.activeEncounter));

        // Assert deterministic migration identity
        final minionTs = resultA.activeMinions.items['min-1']!.timestamp;
        expect(minionTs.physicalTime, equals(0));
        expect(minionTs.logicalCounter, equals(0));
        expect(minionTs.nodeId, equals('genesis'));

        final encTs = resultA.activeEncounter.items['part-1']!.timestamp;
        expect(encTs.physicalTime, equals(0));
        expect(encTs.logicalCounter, equals(0));
        expect(encTs.nodeId, equals('genesis'));
      });

      test('Legacy list identical duplicate IDs collapse idempotently', () {
        final legacyMap = <String, dynamic>{
          'roomId': 'room-dup-1',
          'roomCode': 'RD1',
          'title': 'Dup Room',
          'activeMinions': [
            {'id': 'min-1', 'name': 'Bat', 'hp': 1},
            {'id': 'min-1', 'name': 'Bat', 'hp': 1},
          ],
        };

        final room = RoomNodeState.fromMap(legacyMap);
        expect(room.activeMinions.length, equals(1));
        expect(room.activeMinions.items['min-1']!.value['name'], equals('Bat'));
      });

      test('Legacy list duplicate IDs with divergent payloads fail loudly with StateError', () {
        final legacyMinionsMap = <String, dynamic>{
          'roomId': 'room-divergent-1',
          'roomCode': 'RDV1',
          'title': 'Divergent Minions',
          'activeMinions': [
            {'id': 'min-1', 'name': 'Bat', 'hp': 1},
            {'id': 'min-1', 'name': 'Bat', 'hp': 99},
          ],
        };

        expect(() => RoomNodeState.fromMap(legacyMinionsMap), throwsA(isA<StateError>()));

        final legacyEncounterMap = <String, dynamic>{
          'roomId': 'room-divergent-2',
          'roomCode': 'RDV2',
          'title': 'Divergent Encounter',
          'activeEncounter': [
            {
              'participantId': 'part-1',
              'entityLink': {'entityId': 'ent-1', 'displayName': 'Hero'},
              'currentHp': 20,
              'maxHp': 20,
            },
            {
              'participantId': 'part-1',
              'entityLink': {'entityId': 'ent-1', 'displayName': 'Hero'},
              'currentHp': 5,
              'maxHp': 20,
            },
          ],
        };

        expect(() => RoomNodeState.fromMap(legacyEncounterMap), throwsA(isA<StateError>()));
      });
    });

    group('D. Structural Payload Equivalence in Generic CRDTs', () {
      const ts = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'node-eq');

      test('1. Independently allocated nested maps with same content + same HLC merge idempotently', () {
        final map1 = <String, dynamic>{'hp': 10, 'meta': {'level': 3}};
        final map2 = <String, dynamic>{'hp': 10, 'meta': {'level': 3}};

        final reg1 = CrdtLwwRegister<Map<String, dynamic>>(value: map1, timestamp: ts);
        final reg2 = CrdtLwwRegister<Map<String, dynamic>>(value: map2, timestamp: ts);

        expect(reg1 == reg2, isTrue);
        expect(reg1.hashCode, equals(reg2.hashCode));
        expect(reg1.merge(reg2), equals(reg1));
        expect(reg2.merge(reg1), equals(reg2));
      });

      test('2. Same Map entries in different insertion order merge successfully', () {
        final mapA = <String, dynamic>{'a': 1, 'b': 2, 'c': {'x': 10, 'y': 20}};
        final mapB = <String, dynamic>{'b': 2, 'c': {'y': 20, 'x': 10}, 'a': 1};

        final regA = CrdtLwwRegister<Map<String, dynamic>>(value: mapA, timestamp: ts);
        final regB = CrdtLwwRegister<Map<String, dynamic>>(value: mapB, timestamp: ts);

        expect(regA == regB, isTrue);
        expect(regA.hashCode, equals(regB.hashCode));
        expect(regA.merge(regB), equals(regA));
        expect(regB.merge(regA), equals(regB));
      });

      test('3. Same HLC + nested logical difference throws StateError symmetrically in BOTH directions', () {
        final mapA = <String, dynamic>{'hp': 10, 'meta': {'level': 3}};
        final mapB = <String, dynamic>{'hp': 10, 'meta': {'level': 4}};

        final regA = CrdtLwwRegister<Map<String, dynamic>>(value: mapA, timestamp: ts);
        final regB = CrdtLwwRegister<Map<String, dynamic>>(value: mapB, timestamp: ts);

        expect(() => regA.merge(regB), throwsA(isA<StateError>()));
        expect(() => regB.merge(regA), throwsA(isA<StateError>()));

        final setA = const CrdtOrSet<Map<String, dynamic>>.empty().add('item-1', mapA, ts);
        final setB = const CrdtOrSet<Map<String, dynamic>>.empty().add('item-1', mapB, ts);

        expect(() => setA.merge(setB), throwsA(isA<StateError>()));
        expect(() => setB.merge(setA), throwsA(isA<StateError>()));
      });

      test('4. Serialization -> independent deserialization -> merge does not cause false collision', () {
        final original = const CrdtOrSet<Map<String, dynamic>>.empty().add(
          'item-1',
          {'str': 16, 'skills': ['Athletics', 'Intimidation']},
          ts,
        );

        final serialized = original.toMap((item) => item);
        final deserializedA = CrdtOrSet<Map<String, dynamic>>.fromMap(
          serialized,
          (raw) => Map<String, dynamic>.from(raw as Map),
        );
        final deserializedB = CrdtOrSet<Map<String, dynamic>>.fromMap(
          serialized,
          (raw) => Map<String, dynamic>.from(raw as Map),
        );

        expect(deserializedA == deserializedB, isTrue);
        expect(deserializedA.hashCode, equals(deserializedB.hashCode));
        expect(deserializedA.merge(deserializedB), equals(deserializedA));
      });

      test('5. RoomNodeState raw-map round trip followed by merge succeeds for logically identical payloads', () {
        final roomA = RoomNodeState(
          roomId: 'r1',
          roomCode: 'RC1',
          title: 'Room',
          activeMinions: const CrdtOrSet<dynamic>.empty().add(
            'min-1',
            {'name': 'Goblin', 'stats': {'ac': 15, 'hp': 7}},
            ts,
          ),
        );

        final mapA = roomA.toMap();
        final reconstructedA = RoomNodeState.fromMap(mapA);
        final reconstructedB = RoomNodeState.fromMap(mapA);

        expect(reconstructedA.activeMinions == reconstructedB.activeMinions, isTrue);
        final mergedMinions = reconstructedA.activeMinions.merge(reconstructedB.activeMinions);
        expect(mergedMinions, equals(reconstructedA.activeMinions));
      });
    });

    group('E. Canonical OR-Set State & Stale-Add Handling', () {
      const t1 = HybridLogicalClock(physicalTime: 1000, logicalCounter: 0, nodeId: 'n1');
      const t2 = HybridLogicalClock(physicalTime: 2000, logicalCounter: 0, nodeId: 'n1');

      test('Item newer than tombstone -> item survives upon canonical construction/fromMap', () {
        final rawItems = {'m1': const CrdtLwwRegister(value: 'Minion', timestamp: t2)};
        final rawTombs = {'m1': t1};

        final set = CrdtOrSet(items: rawItems, tombstones: rawTombs);
        expect(set.items.containsKey('m1'), isTrue);
        expect(set.tombstones.containsKey('m1'), isFalse);
        expect(set.length, equals(1));
      });

      test('Tombstone newer than item -> tombstone survives upon canonical construction/fromMap', () {
        final rawItems = {'m1': const CrdtLwwRegister(value: 'Minion', timestamp: t1)};
        final rawTombs = {'m1': t2};

        final set = CrdtOrSet(items: rawItems, tombstones: rawTombs);
        expect(set.items.containsKey('m1'), isFalse);
        expect(set.tombstones.containsKey('m1'), isTrue);
        expect(set.length, equals(0));
      });

      test('Exact timestamp tie between item and tombstone -> ADD WINS', () {
        final rawItems = {'m1': const CrdtLwwRegister(value: 'Minion', timestamp: t1)};
        final rawTombs = {'m1': t1};

        final set = CrdtOrSet(items: rawItems, tombstones: rawTombs);
        expect(set.items.containsKey('m1'), isTrue);
        expect(set.tombstones.containsKey('m1'), isFalse);
        expect(set.length, equals(1));
      });

      test('Stale local add does not replace newer item', () {
        final setAtT2 = const CrdtOrSet<String>.empty().add('item-1', 'Newer Version', t2);
        // Attempt to add stale version at T1
        final setAfterStaleAdd = setAtT2.add('item-1', 'Stale Version', t1);

        expect(setAfterStaleAdd.items['item-1']!.value, equals('Newer Version'));
        expect(setAfterStaleAdd.items['item-1']!.timestamp, equals(t2));
      });

      test('Stale local addBatch does not replace newer item', () {
        final setAtT2 = const CrdtOrSet<String>.empty().add('item-1', 'Newer Version', t2);
        final setAfterBatch = setAtT2.addBatch([(id: 'item-1', item: 'Stale Version', timestamp: t1)]);

        expect(setAfterBatch.items['item-1']!.value, equals('Newer Version'));
        expect(setAfterBatch.items['item-1']!.timestamp, equals(t2));
      });

      test('Contradictory serialized state canonicalizes deterministically on fromMap', () {
        final contradictoryMap = {
          'items': {
            'x1': {'v': 'Alive', 'ts': t1.toMap()},
            'x2': {'v': 'Will Die', 'ts': t1.toMap()},
          },
          'tombstones': {
            'x1': t1.toMap(), // tie -> x1 alive
            'x2': t2.toMap(), // t2 > t1 -> x2 tombstone
          },
        };

        final set = CrdtOrSet<String>.fromMap(contradictoryMap, (r) => r.toString());
        expect(set.items.containsKey('x1'), isTrue);
        expect(set.tombstones.containsKey('x1'), isFalse);

        expect(set.items.containsKey('x2'), isFalse);
        expect(set.tombstones.containsKey('x2'), isTrue);
      });
    });

    group('F. Malformed Authoritative Counter Must Not Fall Back to Scalar', () {
      test('1. Negative component in counter + valid scalar throws FormatException', () {
        final map = {
          'gpCounter': {
            'positive': {'node-1': -50},
          },
          'gp': 100,
        };

        expect(() => PartyPurse.fromMap(map), throwsA(isA<FormatException>()));
      });

      test('2. Malformed component (fractional) in denominationCounters + valid scalar throws FormatException', () {
        final map = {
          'denominationCounters': {
            'gp': {
              'positive': {'node-1': 3.5},
            },
          },
          'gp': 50,
        };

        expect(() => PartyPurse.fromMap(map), throwsA(isA<FormatException>()));
      });

      test('3. Valid counter + mismatching scalar -> counter remains authoritative unchanged', () {
        final map = {
          'gpCounter': {
            'positive': {'node-authoritative': 500},
          },
          'gp': 10, // Stale redundant scalar
        };

        final purse = PartyPurse.fromMap(map);
        expect(purse.getBalance('gp'), equals(500));
        expect(purse.getCounter('gp').positive['node-authoritative'], equals(500));
        expect(purse.getCounter('gp').positive.containsKey('init'), isFalse);
      });

      test('4. Scalar only -> deterministic historical init migration', () {
        final map = {
          'gp': 150,
          'sp': 25,
        };

        final purse = PartyPurse.fromMap(map);
        expect(purse.getBalance('gp'), equals(150));
        expect(purse.getCounter('gp').positive['init'], equals(150));
        expect(purse.getBalance('sp'), equals(25));
        expect(purse.getCounter('sp').positive['init'], equals(25));
      });

      test('5. Historical "cloud" and "init" component IDs remain readable as DATA but active writes use ReplicaId', () {
        final map = {
          'gpCounter': {
            'positive': {'cloud': 200, 'init': 100},
            'negative': {'cloud': 50},
          },
        };

        final purse = PartyPurse.fromMap(map);
        expect(purse.getBalance('gp'), equals(250));
        expect(purse.getCounter('gp').positive['cloud'], equals(200));
        expect(purse.getCounter('gp').positive['init'], equals(100));

        // Active mutation requires ReplicaId and stamps only that replica
        final updated = purse.modifyDenomination('gp', 50, replicaId: ReplicaId('active-runtime-1'));
        expect(updated.getCounter('gp').positive['active-runtime-1'], equals(50));
        expect(updated.getCounter('gp').positive['cloud'], equals(200));
        expect(updated.getCounter('gp').positive['init'], equals(100));
      });
    });

    group('G. Strict Integer CRDT Parsing', () {
      test('PN-Counter strictly rejects fractional, negative, and non-map values', () {
        expect(() => PnCounter.fromMap({'positive': {'n1': 3.5}}), throwsA(isA<FormatException>()));
        expect(() => PnCounter.fromMap({'positive': {'n1': '3.5'}}), throwsA(isA<FormatException>()));
        expect(() => PnCounter.fromMap({'positive': {'n1': -1}}), throwsA(isA<FormatException>()));
        expect(() => PnCounter.fromMap({'positive': 'not-a-map'}), throwsA(isA<FormatException>()));
        expect(() => PnCounter.fromMap({'negative': [1, 2, 3]}), throwsA(isA<FormatException>()));

        // Accepts exact integers, integral doubles, and valid numeric strings
        final valid = PnCounter.fromMap({
          'positive': {'n1': 3, 'n2': 4.0, 'n3': '5'},
          'negative': {'n1': 0, 'n2': 0.0, 'n3': '0'},
        });
        expect(valid.positive['n1'], equals(3));
        expect(valid.positive['n2'], equals(4));
        expect(valid.positive['n3'], equals(5));
        expect(valid.negative['n1'], equals(0));
      });

      test('HLC strictly rejects fractional, negative, and malformed fields', () {
        expect(() => HybridLogicalClock.fromMap({'pt': 3.5, 'lc': 0, 'node': 'n1'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'pt': '3.5', 'lc': 0, 'node': 'n1'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'pt': 1000, 'lc': 2.5, 'node': 'n1'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'pt': 1000, 'lc': '2.5', 'node': 'n1'}), throwsA(isA<FormatException>()));
        expect(() => HybridLogicalClock.fromMap({'pt': 1000, 'lc': -1, 'node': 'n1'}), throwsA(isA<FormatException>()));

        // Missing lc defaults to 0 (documented compatibility)
        final missingLc = HybridLogicalClock.fromMap({'pt': 1000, 'node': 'n1'});
        expect(missingLc.logicalCounter, equals(0));

        // Valid integral representations accepted
        final validHlc = HybridLogicalClock.fromMap({'pt': 1000.0, 'lc': 5.0, 'node': 'n1'});
        expect(validHlc.physicalTime, equals(1000));
        expect(validHlc.logicalCounter, equals(5));
      });
    });

    group('H. Complete CRDT Law Test Bar with Fresh PRNG Seeds and Reproducible Diagnostics', () {
      const iterations = 50;

      test('PnCounter lattice laws (idempotence, commutativity, associativity)', () {
        const effectiveSeed = defaultSeed ^ 1;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          PnCounter genCounter() {
            final p = <String, int>{};
            final n = <String, int>{};
            for (var k = 0; k < 3; k++) {
              if (rng.nextBool()) p['node-$k'] = rng.nextInt(300);
              if (rng.nextBool()) n['node-$k'] = rng.nextInt(300);
            }
            return PnCounter(positive: p, negative: n);
          }

          final a = genCounter();
          final b = genCounter();
          final c = genCounter();

          // Idempotence: a ⊔ a == a
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');
          expect(a.merge(a).hashCode, equals(a.hashCode), reason: 'seed: $effectiveSeed, iter: $i, a: $a');

          // Commutativity: a ⊔ b == b ⊔ a
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');
          expect(a.merge(b).hashCode, equals(b.merge(a).hashCode));

          // Associativity: (a ⊔ b) ⊔ c == a ⊔ (b ⊔ c)
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
          expect(left.hashCode, equals(right.hashCode));
        }
      });

      test('CrdtLwwRegister lattice laws (idempotence, commutativity, associativity)', () {
        const effectiveSeed = defaultSeed ^ 2;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          final pt1 = 1000 + rng.nextInt(500);
          final pt2 = 1000 + rng.nextInt(500);
          final pt3 = 1000 + rng.nextInt(500);
          final node1 = 'n-${rng.nextInt(3)}';
          final node2 = 'n-${rng.nextInt(3)}';
          final node3 = 'n-${rng.nextInt(3)}';

          final ts1 = HybridLogicalClock(physicalTime: pt1, logicalCounter: rng.nextInt(5), nodeId: node1);
          final ts2 = HybridLogicalClock(physicalTime: pt2, logicalCounter: rng.nextInt(5), nodeId: node2);
          final ts3 = HybridLogicalClock(physicalTime: pt3, logicalCounter: rng.nextInt(5), nodeId: node3);

          // Canonical values for non-colliding tests
          final val1 = {'key': 'v-$ts1'};
          final val2 = (ts2 == ts1) ? val1 : {'key': 'v-$ts2'};
          final val3 = (ts3 == ts1) ? val1 : ((ts3 == ts2) ? val2 : {'key': 'v-$ts3'});

          final r1 = CrdtLwwRegister<Map<String, dynamic>>(value: val1, timestamp: ts1);
          final r2 = CrdtLwwRegister<Map<String, dynamic>>(value: val2, timestamp: ts2);
          final r3 = CrdtLwwRegister<Map<String, dynamic>>(value: val3, timestamp: ts3);

          // Idempotence
          expect(r1.merge(r1), equals(r1), reason: 'seed: $effectiveSeed, iter: $i, r1: $r1');
          expect(r1.merge(r1).hashCode, equals(r1.hashCode));

          // Commutativity
          expect(r1.merge(r2), equals(r2.merge(r1)), reason: 'seed: $effectiveSeed, iter: $i, r1: $r1, r2: $r2');
          expect(r1.merge(r2).hashCode, equals(r2.merge(r1).hashCode));

          // Associativity
          final left = (r1.merge(r2)).merge(r3);
          final right = r1.merge(r2.merge(r3));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, r1: $r1, r2: $r2, r3: $r3');
          expect(left.hashCode, equals(right.hashCode));
        }
      });

      test('CrdtOrSet lattice laws (idempotence, commutativity, associativity, add-wins)', () {
        const effectiveSeed = defaultSeed ^ 3;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          CrdtOrSet<Map<String, dynamic>> genSet() {
            var s = const CrdtOrSet<Map<String, dynamic>>.empty();
            for (var k = 0; k < 3; k++) {
              final id = 'item-$k';
              final pt = 1000 + rng.nextInt(300);
              final ts = HybridLogicalClock(physicalTime: pt, logicalCounter: rng.nextInt(3), nodeId: 'n-${rng.nextInt(2)}');
              final payload = {'id': id, 'power': k * 10};
              if (rng.nextBool()) {
                s = s.add(id, payload, ts);
              } else {
                s = s.remove(id, ts);
              }
            }
            return s;
          }

          final a = genSet();
          final b = genSet();
          final c = genSet();

          // Idempotence
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');
          expect(a.merge(a).hashCode, equals(a.hashCode));

          // Commutativity
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');
          expect(a.merge(b).hashCode, equals(b.merge(a).hashCode));

          // Associativity
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
          expect(left.hashCode, equals(right.hashCode));
        }
      });

      test('PartyPurse merge lattice laws (idempotence, commutativity, associativity) across multiple denominations', () {
        const effectiveSeed = defaultSeed ^ 4;
        final rng = Random(effectiveSeed);
        for (var i = 0; i < iterations; i++) {
          PartyPurse genPurse() {
            final counters = <String, PnCounter>{};
            for (final denom in ['cp', 'sp', 'gp', 'pp', 'credits']) {
              if (rng.nextBool()) {
                final p = <String, int>{};
                final n = <String, int>{};
                for (var k = 0; k < 3; k++) {
                  if (rng.nextBool()) p['node-$k'] = rng.nextInt(200);
                  if (rng.nextBool()) n['node-$k'] = rng.nextInt(200);
                }
                counters[denom] = PnCounter(positive: p, negative: n);
              }
            }
            return PartyPurse.fromCounters(counters);
          }

          final a = genPurse();
          final b = genPurse();
          final c = genPurse();

          // Idempotence
          expect(a.merge(a), equals(a), reason: 'seed: $effectiveSeed, iter: $i, a: $a');
          expect(a.merge(a).hashCode, equals(a.hashCode));

          // Commutativity
          expect(a.merge(b), equals(b.merge(a)), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b');
          expect(a.merge(b).hashCode, equals(b.merge(a).hashCode));

          // Associativity
          final left = (a.merge(b)).merge(c);
          final right = a.merge(b.merge(c));
          expect(left, equals(right), reason: 'seed: $effectiveSeed, iter: $i, a: $a, b: $b, c: $c');
          expect(left.hashCode, equals(right.hashCode));
        }
      });
    });

    group('I. CrdtOrSet Strict Deserialization & Null Payload Policy', () {
      test('empty map {} deserializes as empty CrdtOrSet', () {
        final s = CrdtOrSet<String>.fromMap({}, (v) => v.toString());
        expect(s.isEmpty, isTrue);
        expect(s.items, isEmpty);
        expect(s.tombstones, isEmpty);
      });

      test('items: null throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({'items': null}, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('tombstones: null throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({'tombstones': null}, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('items is not a Map (e.g. List) throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({'items': []}, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('tombstones is not a Map (e.g. List) throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({'tombstones': []}, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('item value is primitive instead of Map throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'items': {'id1': 'raw_string_value'},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('item missing ts throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'items': {'id1': {'v': 'payload'}},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('item ts is not a Map throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'items': {'id1': {'v': 'payload', 'ts': 'bad_ts'}},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('item missing v throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'items': {'id1': {'ts': {'pt': 100, 'lc': 0, 'node': 'n1'}}},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('tombstone value is primitive instead of HLC Map throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'tombstones': {'id1': 'not_a_map'},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('tombstone HLC is malformed (e.g. fractional pt) throws FormatException', () {
        expect(
          () => CrdtOrSet<String>.fromMap({
            'tombstones': {'id1': {'pt': 100.5, 'lc': 0, 'node': 'n1'}},
          }, (v) => v.toString()),
          throwsA(isA<FormatException>()),
        );
      });

      test('null payload values are valid for nullable generic types CrdtOrSet<String?>', () {
        final parsed = CrdtOrSet<String?>.fromMap({
          'items': {
            'id1': {
              'v': null,
              'ts': {'pt': 100, 'lc': 0, 'node': 'n1'},
            },
          },
        }, (v) => v as String?);

        expect(parsed.items.length, equals(1));
        expect(parsed.items['id1']!.value, isNull);
        expect(parsed.items['id1']!.timestamp.nodeId, equals('n1'));
      });
    });

    group('J. RoomNodeState Strict Replicated Deserialization & Legacy Migration', () {
      test('1. malformed activeMinions_crdt throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeMinions_crdt': {
              'items': {
                'm1': {
                  'v': {'name': 'Skeleton'},
                  'ts': {'pt': 3.5, 'lc': 0, 'node': 'n1'},
                },
              },
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('2. malformed activeEncounter_crdt throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeEncounter_crdt': {
              'items': {
                'p1': {
                  'v': {'participantId': 'p1'},
                  'ts': {'pt': 100, 'lc': 2.5, 'node': 'n1'},
                },
              },
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('3. malformed map-shaped activeMinions CRDT throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeMinions': {
              'items': 'not_a_map',
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('4. malformed map-shaped activeEncounter CRDT throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeEncounter': {
              'items': 'not_a_map',
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('5. CRDT field present but malformed does NOT fall back to legacy list', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeMinions_crdt': {
              'items': {
                'm1': {
                  'v': {'name': 'Skeleton'},
                  'ts': {'pt': 3.5, 'lc': 0, 'node': 'n1'},
                },
              },
            },
            'activeMinions': [
              {'id': 'm1', 'name': 'Valid Skeleton'},
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('5a. activeMinions_crdt: null with valid legacy list throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeMinions_crdt': null,
            'activeMinions': [
              {'id': 'm1', 'name': 'Valid Skeleton'},
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('5b. activeEncounter_crdt: null with valid legacy list throws FormatException', () {
        expect(
          () => RoomNodeState.fromMap({
            'roomId': 'r1',
            'roomCode': 'RC1',
            'title': 'Test Room',
            'activeEncounter_crdt': null,
            'activeEncounter': [
              {
                'participantId': 'p1',
                'entityLink': {'entityId': 'e1', 'displayName': 'Hero'},
                'currentHp': 20,
                'maxHp': 20,
              },
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('6. legacy list still migrates correctly when no CRDT field exists', () {
        final state = RoomNodeState.fromMap({
          'roomId': 'r1',
          'roomCode': 'RC1',
          'title': 'Test Room',
          'activeMinions': [
            {'id': 'm1', 'name': 'Valid Skeleton'},
          ],
        });

        expect(state.activeMinions.items.length, equals(1));
        final reg = state.activeMinions.items['m1']!;
        expect(reg.timestamp.physicalTime, equals(0));
        expect(reg.timestamp.logicalCounter, equals(0));
        expect(reg.timestamp.nodeId, equals('genesis'));
      });

      test('7. deterministic 0/0/genesis behavior produces identical state and hash across runs', () {
        final map = {
          'roomId': 'r1',
          'roomCode': 'RC1',
          'title': 'Test Room',
          'activeMinions': [
            {'id': 'm1', 'name': 'Valid Skeleton'},
          ],
          'activeEncounter': [
            {
              'participantId': 'p1',
              'entityLink': {'entityId': 'e1', 'displayName': 'Hero'},
              'currentHp': 20,
              'maxHp': 20,
            },
          ],
        };

        final a = RoomNodeState.fromMap(map);
        final b = RoomNodeState.fromMap(map);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('K. Authoritative PartyPurse Counter Representations & Precedence', () {
      test('1. valid nested counter + malformed gpCounter throws FormatException', () {
        expect(
          () => PartyPurse.fromMap({
            'denominationCounters': {
              'gp': {
                'positive': {'n1': 50},
                'negative': {'n1': 10},
              },
            },
            'gpCounter': {
              'positive': {'n1': 3.5}, // malformed fractional
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('2. malformed nested counter + valid gpCounter throws FormatException', () {
        expect(
          () => PartyPurse.fromMap({
            'denominationCounters': {
              'gp': {
                'positive': {'n1': -5}, // malformed negative component
              },
            },
            'gpCounter': {
              'positive': {'n1': 50},
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('3. valid nested counter + valid gpCounter with different values -> nested wins', () {
        final purse = PartyPurse.fromMap({
          'denominationCounters': {
            'gp': {
              'positive': {'n1': 100},
            },
          },
          'gpCounter': {
            'positive': {'n1': 50},
          },
        });

        expect(purse.getBalance('gp'), equals(100));
        expect(purse.getCounter('gp').positive['n1'], equals(100));
      });

      test('4. valid counter(s) + mismatching scalar -> counter winner unchanged', () {
        final purse = PartyPurse.fromMap({
          'denominationCounters': {
            'gp': {
              'positive': {'n1': 100},
            },
          },
          'gp': 25, // legacy scalar mismatch
        });

        expect(purse.getBalance('gp'), equals(100));
        expect(purse.getCounter('gp').positive['n1'], equals(100));
      });

      test('5. scalar only -> deterministic init migration', () {
        final purse = PartyPurse.fromMap({
          'gp': 50,
          'sp': -10,
        });

        expect(purse.getBalance('gp'), equals(50));
        expect(purse.getCounter('gp').positive['init'], equals(50));
        expect(purse.getCounter('sp').negative['init'], equals(10));
        expect(purse.getBalance('sp'), equals(0)); // clamped >= 0 for presentation
      });

      test('6. malformed customCounters entry throws FormatException', () {
        expect(
          () => PartyPurse.fromMap({
            'customCounters': {
              'credits': 'not_a_map',
            },
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
