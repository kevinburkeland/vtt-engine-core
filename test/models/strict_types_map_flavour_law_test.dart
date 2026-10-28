import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:vtt_engine_core/crdt/crdt_lww_register.dart';
import 'package:vtt_engine_core/crdt/crdt_or_set.dart';
import 'package:vtt_engine_core/crdt/hybrid_logical_clock.dart';
import 'package:vtt_engine_core/crdt/pn_counter.dart';
import 'package:vtt_engine_core/models/character_models.dart';
import 'package:vtt_engine_core/models/core_types.dart';
import 'package:vtt_engine_core/models/entity_reference.dart';
import 'package:vtt_engine_core/models/loot_models.dart';
import 'package:vtt_engine_core/models/party_purse.dart';
import 'package:vtt_engine_core/models/session_graph_models.dart';

String _canonicalJson(Object? value) {
  return jsonEncode(_canonicalize(value));
}

Object? _canonicalize(Object? value) {
  if (value is Map<Object?, Object?>) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    final result = <String, Object?>{};
    for (final k in sortedKeys) {
      Object? matchedVal;
      for (final entry in value.entries) {
        if (entry.key.toString() == k) {
          matchedVal = entry.value;
          break;
        }
      }
      result[k] = _canonicalize(matchedVal);
    }
    return result;
  }
  if (value is Iterable<Object?>) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

Map<String, dynamic> _toDynamicFlavourTop(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    out[key] = _toDynamicFlavourValue(value);
  });
  return out;
}

dynamic _toDynamicFlavourValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    final copy = <dynamic, dynamic>{};
    value.forEach((k, v) {
      copy[k] = _toDynamicFlavourValue(v);
    });
    return copy;
  }
  if (value is Iterable<Object?>) {
    final copy = <dynamic>[];
    for (final item in value) {
      copy.add(_toDynamicFlavourValue(item));
    }
    return copy;
  }
  return value;
}

Map<String, dynamic> _toObjectQuestionFlavourTop(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    out[key] = _toObjectQuestionFlavourValue(value);
  });
  return out;
}

Object? _toObjectQuestionFlavourValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    final copy = <Object?, Object?>{};
    value.forEach((k, v) {
      copy[k] = _toObjectQuestionFlavourValue(v);
    });
    return copy;
  }
  if (value is Iterable<Object?>) {
    final copy = <Object?>[];
    for (final item in value) {
      copy.add(_toObjectQuestionFlavourValue(item));
    }
    return copy;
  }
  return value;
}

void _assertFourFlavoursMatch({
  required String typeName,
  required int seed,
  required Map<String, dynamic> originalMap,
  required Map<String, dynamic> Function(Map<String, dynamic> input) roundTrip,
}) {
  final f1Input = originalMap;
  final f2Input = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(originalMap)) as Map<dynamic, dynamic>,
  );
  final f3Input = _toDynamicFlavourTop(originalMap);
  final f4Input = _toObjectQuestionFlavourTop(originalMap);

  final f1Out = roundTrip(f1Input);
  final f2Out = roundTrip(f2Input);
  final f3Out = roundTrip(f3Input);
  final f4Out = roundTrip(f4Input);

  final flavours = <String, Map<String, dynamic>>{
    'jsonDecode(jsonEncode)': f2Out,
    'Map<dynamic, dynamic>': f3Out,
    'Map<Object?, Object?>': f4Out,
  };

  final allKeys = <String>{
    ...f1Out.keys,
    ...f2Out.keys,
    ...f3Out.keys,
    ...f4Out.keys,
  }.toList()
    ..sort();

  for (final entry in flavours.entries) {
    final flavourName = entry.key;
    final candidate = entry.value;
    for (final field in allKeys) {
      final c1 = _canonicalJson(f1Out[field]);
      final cOther = _canonicalJson(candidate[field]);
      if (c1 != cOther) {
        fail(
          '$typeName map-flavour mismatch at seed=$seed '
          '(flavour "$flavourName"), first differing field "$field":\n'
          '  as-produced: $c1\n'
          '  $flavourName: $cOther',
        );
      }
    }
    final full1 = _canonicalJson(f1Out);
    final fullOther = _canonicalJson(candidate);
    if (full1 != fullOther) {
      fail(
        '$typeName map-flavour mismatch at seed=$seed '
        '(flavour "$flavourName")',
      );
    }
  }
}

int _variedCount(Random rng, int seed) {
  if (seed == 0) return 2;
  if (seed == 1) return 0;
  return rng.nextInt(4); // 0, 1, 2, or 3
}

HybridLogicalClock _randomHlc(Random rng, int step) {
  return HybridLogicalClock(
    physicalTime: 1700000000000 + step * 100 + rng.nextInt(50),
    logicalCounter: rng.nextInt(5),
    nodeId: 'node-${rng.nextInt(3)}',
  );
}

EntityReference<DomainEntity> _randomRef(
  Random rng,
  EntityType refType,
  String prefix,
  int index,
) {
  final propCount = rng.nextInt(3);
  final props = <String, dynamic>{};
  for (var i = 0; i < propCount; i++) {
    props['prop_$i'] = i.isEven ? 'val_${rng.nextInt(50)}' : rng.nextInt(20);
  }
  final skillCount = rng.nextInt(3);
  final skills = List<String>.generate(skillCount, (i) => 'skill_$i');
  return EntityReference<DomainEntity>(
    refType: refType,
    slug: '$prefix-$index-${rng.nextInt(1000)}',
    displayName: '$prefix Name $index',
    rulesetPreferred:
        RulesetVersion.values[rng.nextInt(RulesetVersion.values.length)],
    grantedSkills: skills,
    customProperties: props,
  );
}

InventoryItemInstance _randomInventoryItem(Random rng, int index) {
  final hasSlot = rng.nextBool();
  return InventoryItemInstance(
    itemRef: _randomRef(rng, EntityType.item, 'item', index),
    instanceId: 'inst-$index-${rng.nextInt(1000)}',
    quantity: 1 + rng.nextInt(5),
    isEquipped: hasSlot,
    equippedSlot: hasSlot ? 'slot_${rng.nextInt(4)}' : null,
    customProperties: <String, dynamic>{
      'weight': rng.nextInt(15),
      if (rng.nextBool())
        'nested': <String, dynamic>{'tier': rng.nextInt(3)},
      if (rng.nextBool()) 'tags': <String>['tag_${rng.nextInt(5)}'],
    },
  );
}

PartyPurse _randomPurse(Random rng, int seed) {
  if (seed == 1 || (seed > 1 && rng.nextInt(4) == 0)) {
    return const PartyPurse.empty();
  }
  final gold = PnCounter(
    positive: <String, int>{'node-a': 10 + rng.nextInt(100)},
    negative: <String, int>{if (rng.nextBool()) 'node-a': rng.nextInt(5)},
  );
  final silver = PnCounter(
    positive: <String, int>{'node-b': 1 + rng.nextInt(50)},
  );
  return PartyPurse(
    denominationCounters: <String, PnCounter>{
      'gold': gold,
      if (rng.nextBool()) 'silver': silver,
    },
  );
}

Character _buildRandomCharacter(int seed) {
  final rng = Random(seed ^ 0x5F3759DF);
  final invCount = _variedCount(rng, seed);
  final featCount = _variedCount(rng, seed);
  final condCount = _variedCount(rng, seed);
  final toolCount = _variedCount(rng, seed);
  final langCount = _variedCount(rng, seed);
  final traitCount = _variedCount(rng, seed);
  final saveCount = _variedCount(rng, seed);
  final resCount = _variedCount(rng, seed);

  final traits = <String, double>{};
  for (var i = 0; i < traitCount; i++) {
    traits['skill_$i'] = (i.isEven ? 1.0 : 2.0);
  }

  final saves = <String>{};
  for (var i = 0; i < saveCount; i++) {
    saves.add('attr_$i');
  }

  final curRes = <String, int>{};
  final maxRes = <String, int>{};
  for (var i = 0; i < resCount; i++) {
    curRes['pool_$i'] = rng.nextInt(5);
    maxRes['pool_$i'] = 5 + rng.nextInt(5);
  }

  return Character(
    id: EntityId(
      slug: 'char-$seed-${rng.nextInt(1000)}',
      ruleset: RulesetVersion.values[rng.nextInt(RulesetVersion.values.length)],
    ),
    name: 'Hero $seed',
    speciesRef: _randomRef(rng, const EntityType('lineage'), 'lineage', seed),
    backgroundRef: (seed == 0 || rng.nextBool())
        ? _randomRef(rng, const EntityType('origin'), 'bg', seed)
        : null,
    progression: seed == 1
        ? null
        : <String, dynamic>{
            'level': 1 + rng.nextInt(20),
            'classes': <Map<String, dynamic>>[
              <String, dynamic>{'slug': 'warrior', 'level': 1 + rng.nextInt(5)},
            ],
          },
    baseScores: AttributePool(<String, int>{
      'str': 8 + rng.nextInt(10),
      'dex': 8 + rng.nextInt(10),
      if (rng.nextBool()) 'con': 10 + rng.nextInt(8),
    }),
    bonusScores: AttributePool(
      seed == 1
          ? const <String, int>{}
          : <String, int>{'str': rng.nextInt(3)},
    ),
    traitProficiencies: traits,
    savingThrowProficiencies: saves,
    toolProficiencies: List<String>.generate(toolCount, (i) => 'tool_$i'),
    languages: List<String>.generate(langCount, (i) => 'lang_$i'),
    inventory: List<InventoryItemInstance>.generate(
      invCount,
      (i) => _randomInventoryItem(rng, i),
    ),
    purse: _randomPurse(rng, seed),
    feats: List<EntityReference<DomainEntity>>.generate(
      featCount,
      (i) => _randomRef(rng, const EntityType('talent'), 'talent', i),
    ),
    resources: CharacterResourcePool(
      currentHp: seed == 1 ? null : 10 + rng.nextInt(40),
      tempHp: seed == 1 ? null : rng.nextInt(10),
      customResourcesCurrent: curRes,
      customResourcesMax: maxRes,
      auxiliaryData: seed == 1
          ? const <String, dynamic>{}
          : <String, dynamic>{
              'notes': 'aux_$seed',
              'flags': <String>['f_${rng.nextInt(3)}'],
            },
    ),
    conditions: List<CharacterCondition>.generate(
      condCount,
      (i) => CharacterCondition(
        conditionId: 'cond_$i',
        name: 'Condition $i',
        durationRounds: 1 + rng.nextInt(10),
        sourceEntityId: rng.nextBool() ? 'src_$i' : null,
        customProperties: <String, dynamic>{'severity': 1 + rng.nextInt(3)},
      ),
    ),
    baseSpeed: seed == 1 ? null : 25 + rng.nextInt(15),
    rulesetId: 'ruleset_${seed % 3}',
    customProperties: seed == 1
        ? const <String, dynamic>{}
        : <String, dynamic>{
            'campaign': 'camp_$seed',
            'meta': <String, dynamic>{'v': seed},
          },
  );
}

LootContainer _buildRandomLootContainer(int seed, [int offset = 0]) {
  final rng = Random((seed + offset * 1000) ^ 0x9E3779B9);
  final itemCount = _variedCount(rng, seed);
  final permCount = _variedCount(rng, seed);
  final propCount = _variedCount(rng, seed);

  final perms = <String, dynamic>{};
  for (var i = 0; i < permCount; i++) {
    perms['player_$i'] = i.isEven ? 'read' : 'write';
  }

  final props = <String, dynamic>{};
  for (var i = 0; i < propCount; i++) {
    props['k_$i'] = <String, dynamic>{'nested': i};
  }

  return LootContainer(
    containerId: 'chest-$seed-$offset',
    nameRegister: CrdtLwwRegister<String>(
      value: 'Container $seed-$offset',
      timestamp: _randomHlc(rng, seed + offset),
    ),
    type: LootContainerType
        .values[rng.nextInt(LootContainerType.values.length)],
    isLocked: rng.nextBool(),
    capacityWeightLbs: seed == 1 ? null : (25.0 + rng.nextInt(100)),
    items: List<InventoryItemInstance>.generate(
      itemCount,
      (i) => _randomInventoryItem(rng, i),
    ),
    purse: _randomPurse(rng, seed),
    permissions: perms,
    customProperties: props,
  );
}

RoomNodeState _buildRandomRoomNodeState(int seed) {
  final rng = Random(seed ^ 0x85EBCA6B);
  final linkCount = _variedCount(rng, seed);
  final instCount = _variedCount(rng, seed);
  final containerCount = _variedCount(rng, seed);
  final encCount = _variedCount(rng, seed);
  final minionCount = _variedCount(rng, seed);
  final propCount = _variedCount(rng, seed);

  final links = List<RoomEntityLink>.generate(linkCount, (i) {
    final ts = _randomHlc(rng, i + 1);
    return RoomEntityLink(
      refType: EntityCategory('cat_$i', 'Category $i'),
      entityId: 'entity-$seed-$i',
      displayNameRegister: CrdtLwwRegister<String>(
        value: 'Link $i',
        timestamp: ts,
      ),
      notesRegister: CrdtLwwRegister<String?>(
        value: rng.nextBool() ? 'Note $i' : null,
        timestamp: ts,
      ),
      position: rng.nextBool()
          ? <String, dynamic>{'x': rng.nextInt(20), 'y': rng.nextInt(20)}
          : null,
      isIsolatedClone: rng.nextBool(),
      cloneRuntimeData: rng.nextBool()
          ? <String, dynamic>{'hp': 10 + rng.nextInt(20)}
          : null,
      incarnationTimestamp: ts,
    );
  });

  final instances = List<EntityInstance>.generate(instCount, (i) {
    final ts = _randomHlc(rng, i + 10);
    return EntityInstance(
      instanceId: 'inst-$seed-$i',
      entityDefinitionId: rng.nextBool() ? 'def-$i' : null,
      entityType: rng.nextBool() ? 'token' : null,
      displayNameRegister: CrdtLwwRegister<String>(
        value: 'Instance $i',
        timestamp: ts,
      ),
      position: rng.nextBool()
          ? <String, dynamic>{'x': i, 'y': i * 2}
          : null,
      isVisible: rng.nextBool(),
      runtimeData: rng.nextBool()
          ? <String, dynamic>{'init': 10 + i}
          : const <String, dynamic>{},
      customProperties: rng.nextBool()
          ? <String, dynamic>{'tag': 't_$i'}
          : const <String, dynamic>{},
    );
  });

  final containers = List<LootContainer>.generate(
    containerCount,
    (i) => _buildRandomLootContainer(seed, i + 1),
  );

  var activeEncounter = const CrdtOrSet<EncounterParticipant>.empty();
  for (var i = 0; i < encCount; i++) {
    final ts = _randomHlc(rng, i + 20);
    final participant = EncounterParticipant(
      participantId: 'part-$seed-$i',
      entityLink: RoomEntityLink(
        refType: const EntityCategory('actor', 'Actor'),
        entityId: 'act-$seed-$i',
        displayNameRegister: CrdtLwwRegister<String>(
          value: 'Participant $i',
          timestamp: ts,
        ),
        notesRegister: CrdtLwwRegister<String?>(
          value: null,
          timestamp: ts,
        ),
        incarnationTimestamp: ts,
      ),
      initiativeScore: 5 + rng.nextInt(20),
      initiativeTieBreaker: rng.nextInt(5),
      currentHp: 10 + rng.nextInt(30),
      maxHp: 40,
      tempHp: rng.nextInt(5),
      defense: 12 + rng.nextInt(6),
      activeConditions: List<String>.generate(
        rng.nextInt(3),
        (c) => 'cond_$c',
      ),
      isDefeated: false,
      isDead: false,
      isActiveTurn: i == 0,
      customProperties: rng.nextBool()
          ? <String, dynamic>{'role': 'elite_$i'}
          : const <String, dynamic>{},
    );
    activeEncounter = activeEncounter.add(
      participant.participantId,
      participant,
      ts,
    );
  }

  var activeMinions = const CrdtOrSet<dynamic>.empty();
  for (var i = 0; i < minionCount; i++) {
    final ts = _randomHlc(rng, i + 30);
    final minionId = 'minion-$seed-$i';
    final minionMap = <String, dynamic>{
      'id': minionId,
      'name': 'Minion $i',
      'hp': 5 + rng.nextInt(15),
      'tags': <String>['summon_$i'],
    };
    activeMinions = activeMinions.add(minionId, minionMap, ts);
  }

  final props = <String, dynamic>{};
  for (var i = 0; i < propCount; i++) {
    props['room_prop_$i'] = <String, dynamic>{'lighting': 'dim_$i'};
  }

  return RoomNodeState(
    roomId: 'room-$seed',
    roomCode: 'CODE$seed',
    titleRegister: CrdtLwwRegister<String>(
      value: 'Room Title $seed',
      timestamp: _randomHlc(rng, 1),
    ),
    descriptionRegister: CrdtLwwRegister<String>(
      value: 'Room Description $seed',
      timestamp: _randomHlc(rng, 2),
    ),
    entityLinks: links,
    entityInstances: instances,
    containers: containers,
    activeEncounter: activeEncounter,
    activeMinions: activeMinions,
    customProperties: props,
  );
}

void main() {
  group('Part S4: Core strict-types map-flavour law', () {
    test('Character.fromMap produces identical toMap across all 4 map flavours (100 seeds)', () {
      for (var seed = 0; seed < 100; seed++) {
        final character = _buildRandomCharacter(seed);
        final originalMap = character.toMap();
        _assertFourFlavoursMatch(
          typeName: 'Character',
          seed: seed,
          originalMap: originalMap,
          roundTrip: (input) => Character.fromMap(input).toMap(),
        );
      }
    });

    test('LootContainer.fromMap produces identical toMap across all 4 map flavours (100 seeds)', () {
      for (var seed = 0; seed < 100; seed++) {
        final container = _buildRandomLootContainer(seed);
        final originalMap = container.toMap();
        _assertFourFlavoursMatch(
          typeName: 'LootContainer',
          seed: seed,
          originalMap: originalMap,
          roundTrip: (input) => LootContainer.fromMap(input).toMap(),
        );
      }
    });

    test('RoomNodeState.fromMap produces identical toMap across all 4 map flavours (100 seeds)', () {
      for (var seed = 0; seed < 100; seed++) {
        final room = _buildRandomRoomNodeState(seed);
        final originalMap = room.toMap();
        _assertFourFlavoursMatch(
          typeName: 'RoomNodeState',
          seed: seed,
          originalMap: originalMap,
          roundTrip: (input) => RoomNodeState.fromMap(
            input,
            minionParser: (m) => m,
          ).toMap(),
        );
      }
    });
  });
}
