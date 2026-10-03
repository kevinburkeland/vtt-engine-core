import 'dart:collection';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../rules/i_ruleset_module.dart';
import 'core_types.dart';
import 'entity_reference.dart';
import 'party_purse.dart';
import 'generic_tabletop_primitives.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) =>
    const ListEquality().equals(a, b);
bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);
bool _setEquals<T>(Set<T>? a, Set<T>? b) => const SetEquality().equals(a, b);

/// Starting Equipment Preset Item Request
@immutable
class StartingEquipmentItemRequest {
  final EntityReference<DomainEntity> itemRef;
  final int quantity;
  final bool equipImmediately;
  final String? defaultSlot;
  final Map<String, dynamic> customProperties;

  const StartingEquipmentItemRequest({
    required this.itemRef,
    this.quantity = 1,
    this.equipImmediately = false,
    this.defaultSlot,
    this.customProperties = const {},
  });
}

/// Generic, ruleset-agnostic attribute pool operating dynamically over keys
/// defined by an [IAttributeSystem].
@immutable
class AttributePool {
  final Map<String, int> scores;

  const AttributePool([this.scores = const <String, int>{}]);

  const AttributePool.zero() : scores = const <String, int>{};

  /// Resolves attribute score by generic string or enum key.
  int getScore(dynamic key) {
    if (key == null) return 0;
    final clean =
        (key is String ? key : (key is Enum ? key.name : key.toString()))
            .trim()
            .toLowerCase();
    return scores[clean] ?? 0;
  }

  /// Backwards-compatible lookup alias.
  int getScoreByKey(dynamic key) => getScore(key);

  /// Calculates the modifier by generic key, strictly delegating to the provided [IAttributeSystem].
  /// Does not hardcode any ruleset-specific formula into the core engine.
  int getModifier(dynamic key, [IAttributeSystem? system]) {
    final clean =
        (key is String ? key : (key is Enum ? key.name : key.toString()))
            .trim()
            .toLowerCase();
    final score = getScore(clean);
    if (system != null) {
      return system.calculateModifier(clean, score);
    }
    return 0;
  }

  /// Backwards-compatible modifier alias.
  int getModifierByKey(dynamic key, [IAttributeSystem? system]) =>
      getModifier(key, system);

  /// Map representation of all attribute scores in this pool.
  Map<String, int> get attributes => scores;

  /// Returns a new [AttributePool] with bonus scores added.
  AttributePool withBonus(AttributePool bonus) {
    final newScores = Map<String, int>.from(scores);
    for (final entry in bonus.scores.entries) {
      newScores[entry.key] = (newScores[entry.key] ?? 0) + entry.value;
    }
    return AttributePool(Map.unmodifiable(newScores));
  }

  AttributePool operator +(AttributePool other) => withBonus(other);

  AttributePool copyWith({Map<String, int>? scores}) {
    return AttributePool(
      scores != null ? Map.unmodifiable(scores) : this.scores,
    );
  }

  Map<String, int> toMap() => scores;

  factory AttributePool.fromMap(Map<String, dynamic> map) {
    final parsed = <String, int>{};
    map.forEach((k, v) {
      if (v is num) {
        parsed[k.toString().trim().toLowerCase()] = v.toInt();
      }
    });
    return AttributePool(Map.unmodifiable(parsed));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributePool &&
          runtimeType == other.runtimeType &&
          const MapEquality<String, int>().equals(scores, other.scores);

  @override
  int get hashCode => const MapEquality<String, int>().hash(scores);
}

/// Generic Inventory Item Instance representing an equipped or unequipped item.
@immutable
class InventoryItemInstance {
  final EntityReference<DomainEntity> itemRef;
  final String instanceId;
  final int quantity;
  final bool isEquipped;
  final dynamic equippedSlot;
  final Map<String, dynamic> customProperties;

  InventoryItemInstance({
    required this.itemRef,
    required this.instanceId,
    this.quantity = 1,
    this.isEquipped = false,
    this.equippedSlot,
    Map<String, dynamic> customProperties = const {},
  }) : customProperties =
            Map.unmodifiable(Map<String, dynamic>.from(customProperties));

  const InventoryItemInstance.raw({
    required this.itemRef,
    required this.instanceId,
    this.quantity = 1,
    this.isEquipped = false,
    this.equippedSlot,
    this.customProperties = const {},
  });

  String get displayName => itemRef.displayName;

  InventoryItemInstance copyWith({
    EntityReference<DomainEntity>? itemRef,
    String? instanceId,
    int? quantity,
    bool? isEquipped,
    dynamic equippedSlot,
    Map<String, dynamic>? customProperties,
  }) {
    return InventoryItemInstance(
      itemRef: itemRef ?? this.itemRef,
      instanceId: instanceId ?? this.instanceId,
      quantity: quantity ?? this.quantity,
      isEquipped: isEquipped ?? this.isEquipped,
      equippedSlot:
          isEquipped == false ? null : (equippedSlot ?? this.equippedSlot),
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'itemRef': itemRef.toMap(),
        'instanceId': instanceId,
        'quantity': quantity,
        'isEquipped': isEquipped,
        if (equippedSlot != null) 'equippedSlot': equippedSlot,
        'customProperties': customProperties,
      };

  factory InventoryItemInstance.fromMap(Map<String, dynamic> map) {
    return InventoryItemInstance(
      itemRef: EntityReference<DomainEntity>.fromMap(
          Map<String, dynamic>.from(map['itemRef'] as Map? ?? {})),
      instanceId: map['instanceId']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      isEquipped: map['isEquipped'] == true,
      equippedSlot: map['equippedSlot']?.toString(),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemInstance &&
          runtimeType == other.runtimeType &&
          itemRef == other.itemRef &&
          instanceId == other.instanceId &&
          quantity == other.quantity &&
          isEquipped == other.isEquipped &&
          equippedSlot == other.equippedSlot &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      itemRef.hashCode ^
      instanceId.hashCode ^
      quantity.hashCode ^
      isEquipped.hashCode ^
      (equippedSlot?.hashCode ?? 0) ^
      customProperties.length.hashCode;
}

/// Generic character resource pools.
@immutable
class CharacterResourcePool {
  final EntityVitals? _vitals;
  final int? _currentHp;
  final int? _tempHp;
  final Map<String, int> customResourcesCurrent;
  final Map<String, int> customResourcesMax;
  final Map<String, dynamic> auxiliaryData;

  const CharacterResourcePool({
    EntityVitals? vitals,
    int? currentHp,
    int? tempHp,
    this.customResourcesCurrent = const {},
    this.customResourcesMax = const {},
    this.auxiliaryData = const {},
  })  : _vitals = vitals,
        _currentHp = currentHp,
        _tempHp = tempHp;

  int? get currentHp => _vitals?.currentHp ?? _currentHp;
  int? get tempHp => _vitals?.temporaryHp ?? _tempHp;

  EntityVitals? get vitals =>
      _vitals ??
      (currentHp != null
          ? EntityVitals(
              currentHp: currentHp!,
              maxHp: 9999,
              temporaryHp: tempHp ?? 0,
              isDowned: currentHp! <= 0,
              isDead: false,
              auxiliaryPools: customResourcesCurrent,
            )
          : null);

  CharacterResourcePool copyWith({
    EntityVitals? vitals,
    int? currentHp,
    int? tempHp,
    Map<String, int>? customResourcesCurrent,
    Map<String, int>? customResourcesMax,
    Map<String, dynamic>? auxiliaryData,
  }) {
    return CharacterResourcePool(
      vitals: vitals ?? _vitals,
      currentHp: currentHp ?? _currentHp,
      tempHp: tempHp ?? _tempHp,
      customResourcesCurrent: customResourcesCurrent != null
          ? Map.unmodifiable(customResourcesCurrent)
          : this.customResourcesCurrent,
      customResourcesMax: customResourcesMax != null
          ? Map.unmodifiable(customResourcesMax)
          : this.customResourcesMax,
      auxiliaryData: auxiliaryData != null
          ? Map.unmodifiable(auxiliaryData)
          : this.auxiliaryData,
    );
  }

  Map<String, dynamic> toMap() => {
        if (currentHp != null) 'currentHp': currentHp,
        if (tempHp != null) 'tempHp': tempHp,
        'customResourcesCurrent': customResourcesCurrent,
        'customResourcesMax': customResourcesMax,
        'auxiliaryData': auxiliaryData,
      };

  factory CharacterResourcePool.fromMap(Map<String, dynamic> map) {
    final cur = <String, int>{};
    if (map['customResourcesCurrent'] is Map) {
      (map['customResourcesCurrent'] as Map).forEach((k, v) {
        if (v is num) cur[k.toString()] = v.toInt();
      });
    }

    final max = <String, int>{};
    if (map['customResourcesMax'] is Map) {
      (map['customResourcesMax'] as Map).forEach((k, v) {
        if (v is num) max[k.toString()] = v.toInt();
      });
    }

    return CharacterResourcePool(
      currentHp: (map['currentHp'] as num?)?.toInt(),
      tempHp: (map['tempHp'] as num?)?.toInt(),
      customResourcesCurrent: cur,
      customResourcesMax: max,
      auxiliaryData:
          Map<String, dynamic>.from(map['auxiliaryData'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterResourcePool &&
          runtimeType == other.runtimeType &&
          currentHp == other.currentHp &&
          tempHp == other.tempHp &&
          _mapEquals(customResourcesCurrent, other.customResourcesCurrent) &&
          _mapEquals(customResourcesMax, other.customResourcesMax) &&
          _mapEquals(auxiliaryData, other.auxiliaryData);

  @override
  int get hashCode =>
      (currentHp?.hashCode ?? 0) ^
      (tempHp?.hashCode ?? 0) ^
      customResourcesCurrent.length.hashCode ^
      customResourcesMax.length.hashCode ^
      auxiliaryData.length.hashCode;
}

/// Generic active status/condition instance attached to a character.
@immutable
class CharacterCondition {
  final String conditionId;
  final String name;
  final int durationRounds;
  final String? sourceEntityId;
  final Map<String, dynamic> customProperties;

  const CharacterCondition({
    String? conditionId,
    String? name,
    String? conditionName,
    this.durationRounds = -1,
    this.sourceEntityId,
    Map<String, dynamic>? customProperties,
    Map<String, dynamic>? parameters,
  })  : conditionId = conditionId ?? conditionName ?? '',
        name = name ?? conditionName ?? '',
        customProperties = customProperties ?? parameters ?? const {};

  String get conditionName => name;
  String? get source => sourceEntityId;
  Map<String, dynamic> get parameters => customProperties;

  Map<String, dynamic> toMap() => {
        'conditionId': conditionId,
        'name': name,
        'durationRounds': durationRounds,
        if (sourceEntityId != null) 'sourceEntityId': sourceEntityId,
        if (customProperties.isNotEmpty) 'customProperties': customProperties,
      };

  factory CharacterCondition.fromMap(Map<String, dynamic> map) {
    return CharacterCondition(
      conditionId: map['conditionId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      durationRounds: (map['durationRounds'] as num?)?.toInt() ?? -1,
      sourceEntityId: map['sourceEntityId']?.toString(),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterCondition &&
          runtimeType == other.runtimeType &&
          conditionId == other.conditionId &&
          name == other.name &&
          durationRounds == other.durationRounds &&
          sourceEntityId == other.sourceEntityId &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      conditionId.hashCode ^
      name.hashCode ^
      durationRounds.hashCode ^
      (sourceEntityId?.hashCode ?? 0) ^
      customProperties.length.hashCode;
}

/// Case-insensitive Set implementation for tracking dynamic attribute keys.
class AttributeKeySet with SetMixin<String> {
  final Set<String> _storage;

  AttributeKeySet() : _storage = {};

  AttributeKeySet.from(Iterable<dynamic> elements)
      : _storage = elements
            .map((e) =>
                (e is Enum ? e.name : e.toString()).trim().toLowerCase())
            .toSet();

  @override
  bool add(String value) => _storage.add(value.trim().toLowerCase());

  @override
  bool contains(Object? element) {
    if (element == null) return false;
    final clean =
        (element is Enum ? element.name : element.toString()).trim().toLowerCase();
    return _storage.contains(clean);
  }

  @override
  Iterator<String> get iterator => _storage.iterator;

  @override
  int get length => _storage.length;

  @override
  String? lookup(Object? element) {
    if (element == null) return null;
    final clean =
        (element is Enum ? element.name : element.toString()).trim().toLowerCase();
    return _storage.lookup(clean);
  }

  @override
  bool remove(Object? element) {
    if (element == null) return false;
    final clean =
        (element is Enum ? element.name : element.toString()).trim().toLowerCase();
    return _storage.remove(clean);
  }

  @override
  Set<String> toSet() => Set<String>.from(_storage);
}

/// Root Character Domain Entity adhering to DomainEntity interface.
/// Encapsulates generic tabletop character state without game-specific assumptions.
class Character extends DomainEntity {
  @override
  final EntityId id;
  @override
  final String name;
  final EntityReference<DomainEntity> speciesRef;
  final EntityReference<DomainEntity>? backgroundRef;
  final dynamic progression;
  final AttributePool baseScores;
  final AttributePool bonusScores;
  final Map<dynamic, dynamic> traitProficiencies;
  final Set<dynamic> savingThrowProficiencies;
  final List<String> toolProficiencies;
  final List<String> languages;
  final List<InventoryItemInstance> inventory;
  final PartyPurse purse;
  final List<EntityReference<DomainEntity>> feats;
  final CharacterResourcePool resources;
  final List<CharacterCondition> conditions;
  final int? baseSpeed;
  final String rulesetId;
  @override
  final Map<String, dynamic> customProperties;

  const Character({
    required this.id,
    required this.name,
    required this.speciesRef,
    this.backgroundRef,
    this.progression,
    this.baseScores = const AttributePool.zero(),
    this.bonusScores = const AttributePool.zero(),
    this.traitProficiencies = const {},
    this.savingThrowProficiencies = const {},
    this.toolProficiencies = const [],
    this.languages = const [],
    this.inventory = const [],
    this.purse = const PartyPurse.empty(),
    this.feats = const [],
    this.resources = const CharacterResourcePool(),
    this.conditions = const [],
    this.baseSpeed,
    this.rulesetId = 'default',
    this.customProperties = const {},
  });

  @override
  EntityType get entityType => EntityType.character;

  /// Machine-readable identifier of the active ruleset module.
  String get activeModuleId => rulesetId;

  /// Ruleset-agnostic vitals model exposing current HP, max HP, temp HP, downed, and death states.
  EntityVitals? get vitals => resources.vitals;

  /// Raw ability scores (base scores combined with bonuses).
  AttributePool get rawAbilityScores => baseScores.withBonus(bonusScores);

  /// Effective ability scores (accounting for custom properties and equipment overrides).
  AttributePool get effectiveAbilityScores {
    final scores = Map<String, int>.from(rawAbilityScores.attributes);

    for (final instance in inventory.where((i) => i.isEquipped)) {
      final props = instance.customProperties;
      if (props['abilityOverrides'] is Map) {
        final overrides = props['abilityOverrides'] as Map;
        overrides.forEach((k, v) {
          if (v is num) {
            final key = k.toString().toLowerCase().trim();
            scores[key] = math.max(scores[key] ?? 10, v.toInt());
          }
        });
      }
      if (props['abilityBonuses'] is Map) {
        final bonuses = props['abilityBonuses'] as Map;
        bonuses.forEach((k, v) {
          if (v is num) {
            final key = k.toString().toLowerCase().trim();
            scores[key] = (scores[key] ?? 10) + v.toInt();
          }
        });
      }
    }

    if (customProperties['abilityOverrides'] is Map) {
      final overrides = customProperties['abilityOverrides'] as Map;
      overrides.forEach((k, v) {
        if (v is num) {
          final key = k.toString().toLowerCase().trim();
          scores[key] = math.max(scores[key] ?? 10, v.toInt());
        }
      });
    }

    return AttributePool(Map.unmodifiable(scores));
  }

  /// Retrieves an attribute score by dynamic key.
  int getAttributeScore(String key, [int fallback = 10]) =>
      effectiveAbilityScores.getScore(key);

  /// Retrieves all active declarative feature grants across this character.
  List<dynamic> get activeGrants {
    final list = <dynamic>[];

    void extractGrants(dynamic rawGrants) {
      if (rawGrants is! List) return;
      for (final item in rawGrants) {
        if (item != null) {
          list.add(item);
        }
      }
    }

    extractGrants(customProperties['grants']);
    for (final featRef in feats) {
      extractGrants(featRef.customProperties['grants']);
    }
    for (final item in inventory.where((i) => i.isEquipped)) {
      extractGrants(item.customProperties['grants']);
      extractGrants(item.itemRef.customProperties['grants']);
    }

    return List.unmodifiable(list);
  }

  /// Evaluates whether the character has a specific capability flag enabled dynamically.
  bool hasCapabilityFlag(String flagKey) {
    if (customProperties[flagKey] == true) return true;
    final normalizedKey = flagKey.toLowerCase().replaceAll('-', '_');
    if (customProperties[normalizedKey] == true) return true;

    if (customProperties['flags'] is Map) {
      final flagsMap = customProperties['flags'] as Map;
      if (flagsMap[flagKey] == true || flagsMap[normalizedKey] == true) {
        return true;
      }
    }

    for (final g in activeGrants) {
      if (g is Map) {
        final key = g['payload'] is Map
            ? g['payload']['flagKey']?.toString().toLowerCase().replaceAll('-', '_')
            : g['flagKey']?.toString().toLowerCase().replaceAll('-', '_');
        if (key == normalizedKey || key == flagKey.toLowerCase()) {
          return true;
        }
      } else if (g != null) {
        try {
          final payload = (g as dynamic).payload;
          final key = payload is Map
              ? payload['flagKey']?.toString().toLowerCase().replaceAll('-', '_')
              : null;
          if (key == normalizedKey || key == flagKey.toLowerCase()) {
            return true;
          }
        } catch (_) {}
      }
    }

    return false;
  }

  /// Generic stat query interface allowing ruleset modules to resolve derived statistics dynamically.
  int queryStat(String statKey,
      {IRulesetModule? module, Map<String, dynamic> context = const {}}) {
    if (module != null) {
      return module.calculateDerivedStat(
          character: this, statKey: statKey, context: context);
    }
    if (customProperties[statKey] is num) {
      return (customProperties[statKey] as num).toInt();
    }
    return 10;
  }

  /// Resolves an attribute modifier dynamically by string key.
  int getAttributeModifier(String key, [IAttributeSystem? system]) =>
      effectiveAbilityScores.getModifier(key, system);

  /// Resolves trait proficiency multiplier dynamically (e.g. 1.0 for proficient, 2.0 for double).
  double getTraitProficiency(dynamic traitKey) {
    final clean = (traitKey is Enum ? traitKey.name : traitKey.toString())
        .trim()
        .toLowerCase();
    for (final entry in traitProficiencies.entries) {
      final kStr = (entry.key is Enum ? entry.key.name : entry.key.toString())
          .trim()
          .toLowerCase();
      if (kStr == clean) {
        final val = entry.value;
        if (val is num) return val.toDouble();
        if (val is Enum) {
          if (val.name == 'proficient') return 1.0;
          if (val.name == 'expertise') return 2.0;
          if (val.name == 'half') return 0.5;
        }
      }
    }
    return 0.0;
  }

  /// Whether the character is proficient in saving throws for [key].
  bool hasSavingThrowProficiency(dynamic key) {
    final clean = (key is Enum ? key.name : key.toString()).trim().toLowerCase();
    for (final s in savingThrowProficiencies) {
      final sStr = (s is Enum ? s.name : s.toString()).trim().toLowerCase();
      if (sStr == clean) return true;
    }
    return false;
  }

  /// Resolves skill or trait modifier dynamically from generic [ITraitDefinition].
  int getTraitModifier(ITraitDefinition trait,
      [IAttributeSystem? attributeSystem]) {
    final attrKey = trait.governedAttribute;
    final baseMod =
        attrKey != null ? getAttributeModifier(attrKey, attributeSystem) : 0;
    return baseMod;
  }

  /// Dynamic Saving Throw Modifier calculation factoring in ability modifiers.
  int getSaveModifier(dynamic attributeKey,
      [IAttributeSystem? attributeSystem]) {
    final keyStr =
        (attributeKey is Enum ? attributeKey.name : attributeKey.toString())
            .trim()
            .toLowerCase();
    return getAttributeModifier(keyStr, attributeSystem);
  }

  @override
  Map<String, dynamic> toMap() => {
        'id': id.toMap(),
        'name': name,
        'speciesRef': speciesRef.toMap(),
        'backgroundRef': backgroundRef?.toMap(),
        if (progression != null)
          'progression': progression is Map
              ? progression
              : (progression?.toMap != null
                  ? (progression as dynamic).toMap()
                  : progression.toString()),
        'baseScores': baseScores.toMap(),
        'bonusScores': bonusScores.toMap(),
        'traitProficiencies': traitProficiencies,
        'savingThrowProficiencies': savingThrowProficiencies.toList(),
        'toolProficiencies': toolProficiencies,
        'languages': languages,
        'inventory': inventory.map((i) => i.toMap()).toList(),
        'purse': purse.toMap(),
        'feats': feats.map((f) => f.toMap()).toList(),
        'resources': resources.toMap(),
        if (resources.currentHp != null) 'currentHp': resources.currentHp,
        if (resources.tempHp != null) 'tempHp': resources.tempHp,
        'defense': queryStat('defense'),
        'conditions': conditions.map((c) => c.toMap()).toList(),
        if (baseSpeed != null) 'baseSpeed': baseSpeed,
        'rulesetId': rulesetId,
        'customProperties': customProperties,
      };

  factory Character.fromMap(Map<String, dynamic> map) {
    final traits = <String, double>{};
    if (map['traitProficiencies'] is Map) {
      (map['traitProficiencies'] as Map).forEach((k, v) {
        if (v is num) traits[k.toString().toLowerCase().trim()] = v.toDouble();
      });
    }

    final saves = <String>{};
    if (map['savingThrowProficiencies'] is List) {
      for (final s in (map['savingThrowProficiencies'] as List)) {
        saves.add(s.toString().toLowerCase().trim());
      }
    }

    return Character(
      id: map['id'] is Map
          ? EntityId.fromMap(Map<String, dynamic>.from(map['id'] as Map))
          : EntityId(
              slug: map['id']?.toString() ?? '', ruleset: RulesetVersion.homebrew),
      name: map['name']?.toString() ?? '',
      speciesRef: EntityReference<DomainEntity>.fromMap(
          Map<String, dynamic>.from(map['speciesRef'] as Map? ?? {})),
      backgroundRef: map['backgroundRef'] != null
          ? EntityReference<DomainEntity>.fromMap(
              Map<String, dynamic>.from(map['backgroundRef'] as Map? ?? {}))
          : null,
      progression: map['progression'],
      baseScores: AttributePool.fromMap(
          Map<String, dynamic>.from(map['baseScores'] as Map? ?? {})),
      bonusScores: AttributePool.fromMap(
          Map<String, dynamic>.from(map['bonusScores'] as Map? ?? {})),
      traitProficiencies: traits,
      savingThrowProficiencies: saves,
      toolProficiencies: (map['toolProficiencies'] as List? ?? [])
          .whereType<String>()
          .toList(),
      languages: (map['languages'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      inventory: (map['inventory'] as List? ?? [])
          .whereType<Map>()
          .map((i) =>
              InventoryItemInstance.fromMap(Map<String, dynamic>.from(i)))
          .toList(),
      purse: map['purse'] != null
          ? PartyPurse.fromMap(
              Map<String, dynamic>.from(map['purse'] as Map? ?? {}))
          : const PartyPurse.empty(),
      feats: (map['feats'] as List? ?? [])
          .whereType<Map>()
          .map((f) => EntityReference<DomainEntity>.fromMap(
              Map<String, dynamic>.from(f)))
          .toList(),
      resources: CharacterResourcePool.fromMap(
          map['resources'] is Map
              ? Map<String, dynamic>.from(map['resources'] as Map)
              : <String, dynamic>{
                  if (map['currentHp'] != null) 'currentHp': map['currentHp'],
                  if (map['hp'] != null) 'currentHp': map['hp'],
                  if (map['tempHp'] != null) 'tempHp': map['tempHp'],
                }),
      conditions: (map['conditions'] as List? ?? [])
          .whereType<Map>()
          .map((c) => CharacterCondition.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      baseSpeed: (map['baseSpeed'] as num?)?.toInt(),
      rulesetId: map['rulesetId']?.toString() ?? 'default',
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  Character copyWith({
    EntityId? id,
    String? name,
    EntityReference<DomainEntity>? speciesRef,
    EntityReference<DomainEntity>? backgroundRef,
    dynamic progression,
    AttributePool? baseScores,
    AttributePool? bonusScores,
    Map<dynamic, dynamic>? traitProficiencies,
    Set<dynamic>? savingThrowProficiencies,
    List<String>? toolProficiencies,
    List<String>? languages,
    List<InventoryItemInstance>? inventory,
    PartyPurse? purse,
    List<EntityReference<DomainEntity>>? feats,
    CharacterResourcePool? resources,
    List<CharacterCondition>? conditions,
    int? baseSpeed,
    String? rulesetId,
    Map<String, dynamic>? customProperties,
  }) {
    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      speciesRef: speciesRef ?? this.speciesRef,
      backgroundRef: backgroundRef ?? this.backgroundRef,
      progression: progression ?? this.progression,
      baseScores: baseScores ?? this.baseScores,
      bonusScores: bonusScores ?? this.bonusScores,
      traitProficiencies: traitProficiencies != null
          ? Map.unmodifiable(traitProficiencies)
          : this.traitProficiencies,
      savingThrowProficiencies: savingThrowProficiencies ?? this.savingThrowProficiencies,
      toolProficiencies: toolProficiencies != null
          ? List.unmodifiable(toolProficiencies)
          : this.toolProficiencies,
      languages:
          languages != null ? List.unmodifiable(languages) : this.languages,
      inventory: inventory != null
          ? List.unmodifiable(inventory)
          : this.inventory,
      purse: purse ?? this.purse,
      feats: feats != null ? List.unmodifiable(feats) : this.feats,
      resources: resources ?? this.resources,
      conditions: conditions != null
          ? List.unmodifiable(conditions)
          : this.conditions,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      rulesetId: rulesetId ?? this.rulesetId,
      customProperties: customProperties != null
          ? Map.unmodifiable(customProperties)
          : this.customProperties,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Character &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          speciesRef == other.speciesRef &&
          backgroundRef == other.backgroundRef &&
          progression == other.progression &&
          baseScores == other.baseScores &&
          bonusScores == other.bonusScores &&
          _mapEquals(traitProficiencies, other.traitProficiencies) &&
          _setEquals(savingThrowProficiencies, other.savingThrowProficiencies) &&
          _listEquals(toolProficiencies, other.toolProficiencies) &&
          _listEquals(languages, other.languages) &&
          _listEquals(inventory, other.inventory) &&
          purse == other.purse &&
          _listEquals(feats, other.feats) &&
          resources == other.resources &&
          _listEquals(conditions, other.conditions) &&
          baseSpeed == other.baseSpeed &&
          rulesetId == other.rulesetId &&
          _mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      speciesRef.hashCode ^
      (backgroundRef?.hashCode ?? 0) ^
      (progression?.hashCode ?? 0) ^
      baseScores.hashCode ^
      bonusScores.hashCode ^
      traitProficiencies.length.hashCode ^
      savingThrowProficiencies.length.hashCode ^
      toolProficiencies.length.hashCode ^
      languages.length.hashCode ^
      inventory.length.hashCode ^
      purse.hashCode ^
      feats.length.hashCode ^
      resources.hashCode ^
      conditions.length.hashCode ^
      (baseSpeed?.hashCode ?? 0) ^
      rulesetId.hashCode ^
      customProperties.length.hashCode;
}
