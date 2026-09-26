import 'dart:collection';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../rules/i_ruleset_module.dart';
import '../rules/ruleset_edition.dart';
import 'core_types.dart';
import 'entity_reference.dart';
import 'feature_grant.dart';
import 'spell_monster_equipment.dart';
import 'party_purse.dart';
import 'value_objects/hit_points.dart';
import 'generic_tabletop_primitives.dart';

bool listEquals<T>(List<T>? a, List<T>? b) => const ListEquality().equals(a, b);
bool mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    const MapEquality().equals(a, b);
bool setEquals<T>(Set<T>? a, Set<T>? b) => const SetEquality().equals(a, b);

/// 5e Core Ability Score Keys
enum AbilityType {
  strength,
  dexterity,
  constitution,
  intelligence,
  wisdom,
  charisma;

  String get shortName => switch (this) {
        AbilityType.strength => 'STR',
        AbilityType.dexterity => 'DEX',
        AbilityType.constitution => 'CON',
        AbilityType.intelligence => 'INT',
        AbilityType.wisdom => 'WIS',
        AbilityType.charisma => 'CHA',
      };

  String get attributeKey => name;

  /// Safely resolves a loose or unstructured string into a canonical [AbilityType].
  static AbilityType fromLooseString(
    String? key, [
    AbilityType fallback = AbilityType.strength,
  ]) {
    if (key == null) return fallback;
    final clean = key.trim().toLowerCase();
    return switch (clean) {
      'str' || 'strength' => AbilityType.strength,
      'dex' || 'dexterity' => AbilityType.dexterity,
      'con' || 'constitution' => AbilityType.constitution,
      'int' || 'intelligence' => AbilityType.intelligence,
      'wis' || 'wisdom' => AbilityType.wisdom,
      'cha' || 'charisma' => AbilityType.charisma,
      _ => AbilityType.values.firstWhere(
          (a) => a.name.toLowerCase() == clean,
          orElse: () => fallback,
        ),
    };
  }
}

/// Standard 5e Skills
enum SkillType {
  acrobatics,
  animalHandling,
  arcana,
  athletics,
  deception,
  history,
  insight,
  intimidation,
  investigation,
  medicine,
  nature,
  perception,
  performance,
  persuasion,
  religion,
  sleightOfHand,
  stealth,
  survival;

  AbilityType get defaultAbility => switch (this) {
        SkillType.athletics => AbilityType.strength,
        SkillType.acrobatics ||
        SkillType.sleightOfHand ||
        SkillType.stealth =>
          AbilityType.dexterity,
        SkillType.arcana ||
        SkillType.history ||
        SkillType.investigation ||
        SkillType.nature ||
        SkillType.religion =>
          AbilityType.intelligence,
        SkillType.animalHandling ||
        SkillType.insight ||
        SkillType.medicine ||
        SkillType.perception ||
        SkillType.survival =>
          AbilityType.wisdom,
        SkillType.deception ||
        SkillType.intimidation ||
        SkillType.performance ||
        SkillType.persuasion =>
          AbilityType.charisma,
      };

  String get displayName => switch (this) {
        SkillType.acrobatics => 'Acrobatics',
        SkillType.animalHandling => 'Animal Handling',
        SkillType.arcana => 'Arcana',
        SkillType.athletics => 'Athletics',
        SkillType.deception => 'Deception',
        SkillType.history => 'History',
        SkillType.insight => 'Insight',
        SkillType.intimidation => 'Intimidation',
        SkillType.investigation => 'Investigation',
        SkillType.medicine => 'Medicine',
        SkillType.nature => 'Nature',
        SkillType.perception => 'Perception',
        SkillType.performance => 'Performance',
        SkillType.persuasion => 'Persuasion',
        SkillType.religion => 'Religion',
        SkillType.sleightOfHand => 'Sleight of Hand',
        SkillType.stealth => 'Stealth',
        SkillType.survival => 'Survival',
      };

  /// Converts this [SkillType] to the generic tabletop [ITraitDefinition] primitive.
  ITraitDefinition toTraitDefinition() => ITraitDefinition(
        id: name,
        name: displayName,
        category: 'skill',
        governedAttribute: defaultAbility.name,
      );

  /// Resolves an [ITraitDefinition] to a canonical [SkillType] if recognized.
  static SkillType? fromTraitDefinition(ITraitDefinition trait) {
    return tryParse(trait.id) ?? tryParse(trait.name);
  }

  static final Map<String, SkillType> _lookupMap = () {
    final map = <String, SkillType>{};
    for (final s in SkillType.values) {
      final nameClean = _sanitize(s.name);
      final dispClean = _sanitize(s.displayName);
      map[nameClean] = s;
      map[dispClean] = s;
      map[s.name.toLowerCase()] = s;
      map[s.displayName.toLowerCase()] = s;
    }
    return map;
  }();

  static String _sanitize(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c != ' ' && c != '_' && c != '-') {
        buffer.write(c.toLowerCase());
      }
    }
    return buffer.toString();
  }

  static SkillType? tryParse(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().toLowerCase();
    final direct = _lookupMap[trimmed];
    if (direct != null) return direct;
    return _lookupMap[_sanitize(value)];
  }

  static SkillType fromLooseString(String? value,
      {SkillType fallback = SkillType.athletics}) {
    return tryParse(value) ?? fallback;
  }
}

/// Skill Proficiency Levels
enum SkillProficiencyLevel {
  none(0.0),
  jackOfAllTrades(0.5),
  proficient(1.0),
  expertise(2.0);

  final double multiplier;
  const SkillProficiencyLevel(this.multiplier);

  static SkillProficiencyLevel fromMultiplier(num? multiplier) {
    if (multiplier == null) return SkillProficiencyLevel.none;
    final val = multiplier.toDouble();
    if (val >= 2.0) return SkillProficiencyLevel.expertise;
    if (val >= 1.0) return SkillProficiencyLevel.proficient;
    if (val >= 0.5) return SkillProficiencyLevel.jackOfAllTrades;
    return SkillProficiencyLevel.none;
  }
}

/// Starting Equipment Preset Item Request
@immutable
class StartingEquipmentItemRequest {
  final EntityReference<EquipmentItem> itemRef;
  final int quantity;
  final bool equipImmediately;
  final EquipmentSlot? defaultSlot;
  final bool requiresAttunement;

  const StartingEquipmentItemRequest({
    required this.itemRef,
    this.quantity = 1,
    this.equipImmediately = false,
    this.defaultSlot,
    this.requiresAttunement = false,
  });
}

/// Generic, ruleset-agnostic attribute pool operating dynamically over keys
/// defined by an [IAttributeSystem].
@immutable
class AttributePool {
  final int strength;
  final int dexterity;
  final int constitution;
  final int intelligence;
  final int wisdom;
  final int charisma;
  final Map<String, int> customAttributes;

  const AttributePool({
    this.strength = 10,
    this.dexterity = 10,
    this.constitution = 10,
    this.intelligence = 10,
    this.wisdom = 10,
    this.charisma = 10,
    this.customAttributes = const {},
  });

  const AttributePool.standardArray()
      : strength = 15,
        dexterity = 14,
        constitution = 13,
        intelligence = 12,
        wisdom = 10,
        charisma = 8,
        customAttributes = const {};

  const AttributePool.zero()
      : strength = 0,
        dexterity = 0,
        constitution = 0,
        intelligence = 0,
        wisdom = 0,
        charisma = 0,
        customAttributes = const {};

  /// Resolves attribute score by generic string or enum key from an [IAttributeSystem].
  int getScore(dynamic key) {
    final clean =
        (key is String ? key : (key is Enum ? key.name : key.toString()))
            .trim()
            .toLowerCase();
    return switch (clean) {
      'strength' || 'str' => strength,
      'dexterity' || 'dex' => dexterity,
      'constitution' || 'con' => constitution,
      'intelligence' || 'int' => intelligence,
      'wisdom' || 'wis' => wisdom,
      'charisma' || 'cha' => charisma,
      _ => customAttributes[clean] ?? 10,
    };
  }

  /// Backwards-compatible lookup alias.
  int getScoreByKey(dynamic key) => getScore(key);

  /// Calculates the modifier by generic key, optionally utilizing the provided [IAttributeSystem].
  int getModifier(dynamic key, [IAttributeSystem? system]) {
    final clean =
        (key is String ? key : (key is Enum ? key.name : key.toString()))
            .trim()
            .toLowerCase();
    final score = getScore(clean);
    if (system != null) {
      return system.calculateModifier(clean, score);
    }
    return ((score - 10) / 2).floor();
  }

  /// Backwards-compatible modifier alias.
  int getModifierByKey(dynamic key, [IAttributeSystem? system]) =>
      getModifier(key, system);

  /// Map representation of all attribute scores in this pool.
  Map<String, int> get attributes => {
        'strength': strength,
        'dexterity': dexterity,
        'constitution': constitution,
        'intelligence': intelligence,
        'wisdom': wisdom,
        'charisma': charisma,
        ...customAttributes,
      };

  /// Returns a new [AttributePool] with bonus scores added.
  AttributePool withBonus(AttributePool bonus) {
    final newCustom = <String, int>{};
    final allKeys = customAttributes.keys
        .toSet()
        .union(bonus.customAttributes.keys.toSet());
    for (final k in allKeys) {
      newCustom[k] =
          (customAttributes[k] ?? 0) + (bonus.customAttributes[k] ?? 0);
    }
    return AttributePool(
      strength: strength + bonus.strength,
      dexterity: dexterity + bonus.dexterity,
      constitution: constitution + bonus.constitution,
      intelligence: intelligence + bonus.intelligence,
      wisdom: wisdom + bonus.wisdom,
      charisma: charisma + bonus.charisma,
      customAttributes: Map.unmodifiable(newCustom),
    );
  }

  AttributePool operator +(AttributePool other) => withBonus(other);

  AttributePool copyWith({
    int? strength,
    int? dexterity,
    int? constitution,
    int? intelligence,
    int? wisdom,
    int? charisma,
    Map<String, int>? customAttributes,
  }) {
    return AttributePool(
      strength: strength ?? this.strength,
      dexterity: dexterity ?? this.dexterity,
      constitution: constitution ?? this.constitution,
      intelligence: intelligence ?? this.intelligence,
      wisdom: wisdom ?? this.wisdom,
      charisma: charisma ?? this.charisma,
      customAttributes: customAttributes != null
          ? Map.unmodifiable(customAttributes)
          : this.customAttributes,
    );
  }

  Map<String, int> toMap() => {
        'strength': strength,
        'dexterity': dexterity,
        'constitution': constitution,
        'intelligence': intelligence,
        'wisdom': wisdom,
        'charisma': charisma,
        if (customAttributes.isNotEmpty) ...customAttributes,
      };

  factory AttributePool.fromMap(Map<String, dynamic> map) {
    final custom = <String, int>{};
    int str = 10, dex = 10, con = 10, intl = 10, wis = 10, cha = 10;

    map.forEach((k, v) {
      if (v is num) {
        final key = k.toString().trim().toLowerCase();
        switch (key) {
          case 'strength' || 'str':
            str = v.toInt();
          case 'dexterity' || 'dex':
            dex = v.toInt();
          case 'constitution' || 'con':
            con = v.toInt();
          case 'intelligence' || 'int':
            intl = v.toInt();
          case 'wisdom' || 'wis':
            wis = v.toInt();
          case 'charisma' || 'cha':
            cha = v.toInt();
          default:
            custom[key] = v.toInt();
        }
      }
    });

    return AttributePool(
      strength: str,
      dexterity: dex,
      constitution: con,
      intelligence: intl,
      wisdom: wis,
      charisma: cha,
      customAttributes: Map.unmodifiable(custom),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributePool &&
          runtimeType == other.runtimeType &&
          strength == other.strength &&
          dexterity == other.dexterity &&
          constitution == other.constitution &&
          intelligence == other.intelligence &&
          wisdom == other.wisdom &&
          charisma == other.charisma &&
          mapEquals(customAttributes, other.customAttributes);

  @override
  int get hashCode => Object.hash(
        strength,
        dexterity,
        constitution,
        intelligence,
        wisdom,
        charisma,
        const MapEquality<String, int>().hash(customAttributes),
      );
}

/// Canonical type alias pointing to [AttributePool] for backward-compatibility.
typedef AbilityScores = AttributePool;

/// Equipment and Wearable Slots
enum EquipmentSlot {
  head,
  cloak,
  armor,
  shield,
  mainHand,
  offHand,
  twoHand,
  ring1,
  ring2,
  boots,
  wondrous;

  String get displayName => switch (this) {
        EquipmentSlot.head => 'Head',
        EquipmentSlot.cloak => 'Cloak',
        EquipmentSlot.armor => 'Armor',
        EquipmentSlot.shield => 'Shield',
        EquipmentSlot.mainHand => 'Main Hand',
        EquipmentSlot.offHand => 'Off Hand',
        EquipmentSlot.twoHand => 'Two-Handed',
        EquipmentSlot.ring1 => 'Ring 1',
        EquipmentSlot.ring2 => 'Ring 2',
        EquipmentSlot.boots => 'Boots',
        EquipmentSlot.wondrous => 'Wondrous',
      };
}

/// Individual item instance in a character or container inventory
@immutable
class InventoryItemInstance {
  final String instanceId;
  final EntityReference<EquipmentItem> itemRef;
  final int quantity;
  final bool isEquipped;
  final EquipmentSlot? equippedSlot;
  final bool isAttuned;
  final bool requiresAttunement;
  final String? customName;
  final String? notes;
  final Map<String, dynamic> customProperties;

  const InventoryItemInstance({
    required this.instanceId,
    required this.itemRef,
    this.quantity = 1,
    this.isEquipped = false,
    this.equippedSlot,
    this.isAttuned = false,
    this.requiresAttunement = false,
    this.customName,
    this.notes,
    this.customProperties = const {},
  });

  String get displayName => customName ?? itemRef.displayName;

  InventoryItemInstance copyWith({
    String? instanceId,
    EntityReference<EquipmentItem>? itemRef,
    int? quantity,
    bool? isEquipped,
    EquipmentSlot? equippedSlot,
    bool? isAttuned,
    bool? requiresAttunement,
    String? customName,
    String? notes,
    Map<String, dynamic>? customProperties,
  }) {
    return InventoryItemInstance(
      instanceId: instanceId ?? this.instanceId,
      itemRef: itemRef ?? this.itemRef,
      quantity: quantity ?? this.quantity,
      isEquipped: isEquipped ?? this.isEquipped,
      equippedSlot:
          isEquipped == false ? null : (equippedSlot ?? this.equippedSlot),
      isAttuned: isAttuned ?? this.isAttuned,
      requiresAttunement: requiresAttunement ?? this.requiresAttunement,
      customName: customName ?? this.customName,
      notes: notes ?? this.notes,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'instanceId': instanceId,
        'itemRef': itemRef.toMap(),
        'quantity': quantity,
        'isEquipped': isEquipped,
        'equippedSlot': equippedSlot?.name,
        'isAttuned': isAttuned,
        'requiresAttunement': requiresAttunement,
        'customName': customName,
        'notes': notes,
        'customProperties': customProperties,
      };

  factory InventoryItemInstance.fromMap(Map<String, dynamic> map) {
    EquipmentSlot? slot;
    if (map['equippedSlot'] != null) {
      final sStr = map['equippedSlot'].toString();
      slot = EquipmentSlot.values.firstWhere(
        (s) => s.name == sStr,
        orElse: () => EquipmentSlot.wondrous,
      );
    }

    return InventoryItemInstance(
      instanceId: map['instanceId']?.toString() ?? '',
      itemRef: EntityReference<EquipmentItem>.fromMap(
          Map<String, dynamic>.from(map['itemRef'] as Map? ?? {})),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      isEquipped: map['isEquipped'] == true,
      equippedSlot: slot,
      isAttuned: map['isAttuned'] == true,
      requiresAttunement: map['requiresAttunement'] == true,
      customName: map['customName']?.toString(),
      notes: map['notes']?.toString(),
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemInstance &&
          runtimeType == other.runtimeType &&
          instanceId == other.instanceId &&
          itemRef == other.itemRef &&
          quantity == other.quantity &&
          isEquipped == other.isEquipped &&
          equippedSlot == other.equippedSlot &&
          isAttuned == other.isAttuned &&
          requiresAttunement == other.requiresAttunement &&
          customName == other.customName &&
          notes == other.notes &&
          mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      instanceId.hashCode ^
      itemRef.hashCode ^
      quantity.hashCode ^
      isEquipped.hashCode ^
      (equippedSlot?.hashCode ?? 0) ^
      isAttuned.hashCode ^
      requiresAttunement.hashCode ^
      (customName?.hashCode ?? 0) ^
      (notes?.hashCode ?? 0) ^
      customProperties.length.hashCode;
}

/// Single class progression slice (supporting single class or multiclassing)
@immutable
class ClassLevelProgression {
  final EntityReference<DomainEntity> classRef;
  final EntityReference<DomainEntity>? subclassRef;
  final int level;
  final String hitDie; // e.g. "d8", "d10", "d12", "d6"
  final List<int> hitPointsRolled; // HP gained per level above 1st
  final bool isStartingClass;
  final Map<String, List<String>>
      selectedFeatureOptions; // decisionId -> [selectedOptionIds]

  const ClassLevelProgression({
    required this.classRef,
    this.subclassRef,
    this.level = 1,
    required this.hitDie,
    this.hitPointsRolled = const [],
    this.isStartingClass = false,
    this.selectedFeatureOptions = const {},
  });

  int get hitDieSides {
    final clean = hitDie.replaceAll('d', '').trim();
    return int.tryParse(clean) ?? 8;
  }

  int get averageHpPerLevel => (hitDieSides / 2).floor() + 1;

  ClassLevelProgression copyWith({
    EntityReference<DomainEntity>? classRef,
    EntityReference<DomainEntity>? subclassRef,
    int? level,
    String? hitDie,
    List<int>? hitPointsRolled,
    bool? isStartingClass,
    Map<String, List<String>>? selectedFeatureOptions,
  }) {
    return ClassLevelProgression(
      classRef: classRef ?? this.classRef,
      subclassRef: subclassRef ?? this.subclassRef,
      level: level ?? this.level,
      hitDie: hitDie ?? this.hitDie,
      hitPointsRolled: hitPointsRolled != null
          ? List.unmodifiable(hitPointsRolled)
          : this.hitPointsRolled,
      isStartingClass: isStartingClass ?? this.isStartingClass,
      selectedFeatureOptions: selectedFeatureOptions != null
          ? Map.unmodifiable(selectedFeatureOptions
              .map((k, v) => MapEntry(k, List<String>.unmodifiable(v))))
          : this.selectedFeatureOptions,
    );
  }

  Map<String, dynamic> toMap() => {
        'classRef': classRef.toMap(),
        'subclassRef': subclassRef?.toMap(),
        'level': level,
        'hitDie': hitDie,
        'hitPointsRolled': hitPointsRolled,
        'isStartingClass': isStartingClass,
        'selectedFeatureOptions': selectedFeatureOptions,
      };

  factory ClassLevelProgression.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['selectedFeatureOptions'];
    final parsedOptions = <String, List<String>>{};
    if (rawOptions is Map) {
      rawOptions.forEach((key, val) {
        if (val is List) {
          parsedOptions[key.toString()] = val.map((e) => e.toString()).toList();
        } else if (val != null) {
          parsedOptions[key.toString()] = [val.toString()];
        }
      });
    }

    return ClassLevelProgression(
      classRef: EntityReference<DomainEntity>.fromMap(
          Map<String, dynamic>.from(map['classRef'] as Map? ?? {})),
      subclassRef: map['subclassRef'] != null
          ? EntityReference<DomainEntity>.fromMap(
              Map<String, dynamic>.from(map['subclassRef'] as Map? ?? {}))
          : null,
      level: (map['level'] as num?)?.toInt() ?? 1,
      hitDie: map['hitDie']?.toString() ?? 'd8',
      hitPointsRolled: (map['hitPointsRolled'] as List? ?? [])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(),
      isStartingClass: map['isStartingClass'] == true,
      selectedFeatureOptions: parsedOptions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassLevelProgression &&
          runtimeType == other.runtimeType &&
          classRef == other.classRef &&
          subclassRef == other.subclassRef &&
          level == other.level &&
          hitDie == other.hitDie &&
          listEquals(hitPointsRolled, other.hitPointsRolled) &&
          isStartingClass == other.isStartingClass &&
          mapEquals(selectedFeatureOptions, other.selectedFeatureOptions);

  @override
  int get hashCode =>
      classRef.hashCode ^
      (subclassRef?.hashCode ?? 0) ^
      level.hashCode ^
      hitDie.hashCode ^
      Object.hashAll(hitPointsRolled) ^
      isStartingClass.hashCode ^
      selectedFeatureOptions.length.hashCode;
}

/// Overall Character Progression aggregating all class levels
@immutable
class CharacterProgression {
  final List<ClassLevelProgression> classes;
  final int experiencePoints;
  final Map<int, int> manualHpRolls; // Character Level -> Rolled HP

  const CharacterProgression({
    required this.classes,
    this.experiencePoints = 0,
    this.manualHpRolls = const {},
  });

  int get totalLevel => classes.fold(0, (sum, c) => sum + c.level);

  ClassLevelProgression? get startingClass =>
      classes.where((c) => c.isStartingClass).firstOrNull ??
      classes.firstOrNull;

  ClassLevelProgression? getClass(String classSlug) =>
      classes.where((c) => c.classRef.slug == classSlug).firstOrNull;

  /// Retrieves all selected option IDs for a specific decision across all classes.
  List<String> getSelectedOptionsForDecision(String decisionId) {
    final results = <String>[];
    for (final c in classes) {
      final opts = c.selectedFeatureOptions[decisionId];
      if (opts != null) results.addAll(opts);
    }
    return results;
  }

  /// Aggregates all selected feature option IDs across all classes.
  Map<String, List<String>> getAllSelectedFeatureOptions() {
    final merged = <String, List<String>>{};
    for (final c in classes) {
      final classSlug = c.classRef.slug.toLowerCase();
      final customDecisions = c.classRef.customProperties['featureDecisions']
              is List
          ? (c.classRef.customProperties['featureDecisions'] as List).toSet()
          : null;

      c.selectedFeatureOptions.forEach((k, v) {
        final normK = k.toLowerCase().replaceAll('-', '_');
        if (k.startsWith('$classSlug-') ||
            k.startsWith('feat-') ||
            k.contains('invocation') ||
            normK == 'fighting_style' ||
            normK.contains('fighting_style') ||
            (customDecisions != null &&
                (customDecisions.contains(k) ||
                    customDecisions.contains(normK)))) {
          merged.putIfAbsent(k, () => []).addAll(v);
        }
      });
    }
    return merged;
  }

  CharacterProgression copyWith({
    List<ClassLevelProgression>? classes,
    int? experiencePoints,
    Map<int, int>? manualHpRolls,
  }) {
    return CharacterProgression(
      classes: classes != null ? List.unmodifiable(classes) : this.classes,
      experiencePoints: experiencePoints ?? this.experiencePoints,
      manualHpRolls: manualHpRolls != null
          ? Map.unmodifiable(manualHpRolls)
          : this.manualHpRolls,
    );
  }

  Map<String, dynamic> toMap() => {
        'classes': classes.map((c) => c.toMap()).toList(),
        'experiencePoints': experiencePoints,
        'manualHpRolls': manualHpRolls.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory CharacterProgression.fromMap(Map<String, dynamic> map) {
    final hpRolls = <int, int>{};
    if (map['manualHpRolls'] is Map) {
      (map['manualHpRolls'] as Map).forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null && v is num) hpRolls[key] = v.toInt();
      });
    }

    return CharacterProgression(
      classes: (map['classes'] as List? ?? [])
          .whereType<Map>()
          .map((c) =>
              ClassLevelProgression.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      experiencePoints: (map['experiencePoints'] as num?)?.toInt() ?? 0,
      manualHpRolls: hpRolls,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterProgression &&
          runtimeType == other.runtimeType &&
          listEquals(classes, other.classes) &&
          experiencePoints == other.experiencePoints &&
          mapEquals(manualHpRolls, other.manualHpRolls);

  @override
  int get hashCode =>
      Object.hashAll(classes) ^
      experiencePoints.hashCode ^
      manualHpRolls.length.hashCode;
}

/// Standard 5e Spell Slots Pool
@immutable
class SpellSlotPool {
  final Map<int, int> currentSlots; // Level 1-9 available slots
  final Map<int, int> maxSlots; // Level 1-9 max slots
  final int pactMagicSlotLevel; // 1-5
  final int pactMagicMax;
  final int pactMagicCurrent;

  const SpellSlotPool({
    this.currentSlots = const {},
    this.maxSlots = const {},
    this.pactMagicSlotLevel = 0,
    this.pactMagicMax = 0,
    this.pactMagicCurrent = 0,
  });

  SpellSlotPool copyWith({
    Map<int, int>? currentSlots,
    Map<int, int>? maxSlots,
    int? pactMagicSlotLevel,
    int? pactMagicMax,
    int? pactMagicCurrent,
  }) {
    return SpellSlotPool(
      currentSlots: currentSlots != null
          ? Map.unmodifiable(currentSlots)
          : this.currentSlots,
      maxSlots: maxSlots != null ? Map.unmodifiable(maxSlots) : this.maxSlots,
      pactMagicSlotLevel: pactMagicSlotLevel ?? this.pactMagicSlotLevel,
      pactMagicMax: pactMagicMax ?? this.pactMagicMax,
      pactMagicCurrent: pactMagicCurrent ?? this.pactMagicCurrent,
    );
  }

  Map<String, dynamic> toMap() => {
        'currentSlots': currentSlots.map((k, v) => MapEntry(k.toString(), v)),
        'maxSlots': maxSlots.map((k, v) => MapEntry(k.toString(), v)),
        'pactMagicSlotLevel': pactMagicSlotLevel,
        'pactMagicMax': pactMagicMax,
        'pactMagicCurrent': pactMagicCurrent,
      };

  factory SpellSlotPool.fromMap(Map<String, dynamic> map) {
    final cur = <int, int>{};
    if (map['currentSlots'] is Map) {
      (map['currentSlots'] as Map).forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null && v is num) cur[key] = v.toInt();
      });
    }

    final max = <int, int>{};
    if (map['maxSlots'] is Map) {
      (map['maxSlots'] as Map).forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null && v is num) max[key] = v.toInt();
      });
    }

    return SpellSlotPool(
      currentSlots: cur,
      maxSlots: max,
      pactMagicSlotLevel: (map['pactMagicSlotLevel'] as num?)?.toInt() ?? 0,
      pactMagicMax: (map['pactMagicMax'] as num?)?.toInt() ?? 0,
      pactMagicCurrent: (map['pactMagicCurrent'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpellSlotPool &&
          runtimeType == other.runtimeType &&
          mapEquals(currentSlots, other.currentSlots) &&
          mapEquals(maxSlots, other.maxSlots) &&
          pactMagicSlotLevel == other.pactMagicSlotLevel &&
          pactMagicMax == other.pactMagicMax &&
          pactMagicCurrent == other.pactMagicCurrent;

  @override
  int get hashCode =>
      mapEquals.hashCode ^
      currentSlots.length.hashCode ^
      maxSlots.length.hashCode ^
      pactMagicSlotLevel.hashCode ^
      pactMagicMax.hashCode ^
      pactMagicCurrent.hashCode;
}

/// Character resource pools (HP, Hit Dice, Spell Slots, Class charges, Death Saves, Exhaustion, Inspiration)
@immutable
class CharacterResourcePool {
  final EntityVitals? _vitals;
  final int _currentHp;
  final int _tempHp;
  final Map<String, int> currentHitDice; // e.g. {"d8": 3, "d10": 1}
  final SpellSlotPool spellSlots;
  final Map<String, int> customResourcesCurrent; // e.g. {"ki": 4, "rage": 2}
  final Map<String, int> customResourcesMax;
  final int _deathSaveSuccesses; // clamped 0-3
  final int _deathSaveFailures; // clamped 0-3
  final int _exhaustionLevel; // clamped 0-10
  final bool hasHeroicInspiration;

  int get deathSaveSuccesses =>
      (_vitals?.auxiliaryPools['deathSaveSuccesses'] as num?)?.toInt() ??
      (_vitals?.auxiliaryPools['death_save_successes'] as num?)?.toInt() ??
      _deathSaveSuccesses;

  int get deathSaveFailures =>
      (_vitals?.auxiliaryPools['deathSaveFailures'] as num?)?.toInt() ??
      (_vitals?.auxiliaryPools['death_save_failures'] as num?)?.toInt() ??
      _deathSaveFailures;

  int get exhaustionLevel =>
      (_vitals?.auxiliaryPools['exhaustionLevel'] as num?)?.toInt() ??
      (_vitals?.auxiliaryPools['exhaustion_level'] as num?)?.toInt() ??
      _exhaustionLevel;

  EntityVitals get vitals =>
      _vitals ??
      EntityVitals(
        currentHp: _currentHp,
        maxHp: 9999,
        temporaryHp: _tempHp,
        isDowned: _currentHp <= 0,
        isDead: deathSaveFailures >= 3,
        auxiliaryPools: {
          'deathSaveSuccesses': deathSaveSuccesses,
          'death_save_successes': deathSaveSuccesses,
          'deathSaveFailures': deathSaveFailures,
          'death_save_failures': deathSaveFailures,
          'exhaustionLevel': exhaustionLevel,
          ...spellSlots.currentSlots
              .map((k, v) => MapEntry('spell_slot_cur_$k', v)),
          ...spellSlots.maxSlots
              .map((k, v) => MapEntry('spell_slot_max_$k', v)),
          if (spellSlots.pactMagicMax > 0) ...{
            'spell_slot_pact_max': spellSlots.pactMagicMax,
            'spell_slot_pact_cur': spellSlots.pactMagicCurrent,
          },
          ...customResourcesCurrent.map((k, v) => MapEntry('resource_$k', v)),
        },
      );

  int get currentHp => _vitals?.currentHp ?? _currentHp;
  int get tempHp => _vitals?.temporaryHp ?? _tempHp;

  HitPoints get hitPoints => HitPoints(
        currentHp: currentHp,
        maxHp: 9999,
        tempHp: tempHp,
      );

  const CharacterResourcePool.empty()
      : _vitals = const EntityVitals(currentHp: 10, maxHp: 9999),
        _currentHp = 10,
        _tempHp = 0,
        currentHitDice = const {},
        spellSlots = const SpellSlotPool(),
        customResourcesCurrent = const {},
        customResourcesMax = const {},
        _deathSaveSuccesses = 0,
        _deathSaveFailures = 0,
        _exhaustionLevel = 0,
        hasHeroicInspiration = false;

  const CharacterResourcePool({
    EntityVitals? vitals,
    int currentHp = 10,
    int tempHp = 0,
    this.currentHitDice = const {},
    this.spellSlots = const SpellSlotPool(),
    this.customResourcesCurrent = const {},
    this.customResourcesMax = const {},
    int deathSaveSuccesses = 0,
    int deathSaveFailures = 0,
    int exhaustionLevel = 0,
    this.hasHeroicInspiration = false,
  })  : _vitals = vitals,
        _currentHp = currentHp,
        _tempHp = tempHp,
        _deathSaveSuccesses = deathSaveSuccesses < 0
            ? 0
            : (deathSaveSuccesses > 3 ? 3 : deathSaveSuccesses),
        _deathSaveFailures = deathSaveFailures < 0
            ? 0
            : (deathSaveFailures > 3 ? 3 : deathSaveFailures),
        _exhaustionLevel = exhaustionLevel < 0
            ? 0
            : (exhaustionLevel > 10 ? 10 : exhaustionLevel);

  CharacterResourcePool withVitals(EntityVitals newVitals) {
    return copyWith(
      vitals: newVitals,
      currentHp: newVitals.currentHp,
      tempHp: newVitals.temporaryHp,
      deathSaveSuccesses: newVitals.auxiliaryPools['deathSaveSuccesses'] ??
          newVitals.auxiliaryPools['death_save_successes'] ??
          deathSaveSuccesses,
      deathSaveFailures: newVitals.isDead
          ? 3
          : (newVitals.auxiliaryPools['deathSaveFailures'] ??
              newVitals.auxiliaryPools['death_save_failures'] ??
              deathSaveFailures),
      exhaustionLevel: newVitals.auxiliaryPools['exhaustionLevel'] ??
          newVitals.auxiliaryPools['exhaustion_level'] ??
          exhaustionLevel,
    );
  }

  CharacterResourcePool copyWith({
    EntityVitals? vitals,
    HitPoints? hitPoints,
    int? currentHp,
    int? tempHp,
    Map<String, int>? currentHitDice,
    SpellSlotPool? spellSlots,
    Map<String, int>? customResourcesCurrent,
    Map<String, int>? customResourcesMax,
    int? deathSaveSuccesses,
    int? deathSaveFailures,
    int? exhaustionLevel,
    bool? hasHeroicInspiration,
  }) {
    final resolvedCurrentHp = vitals?.currentHp ??
        hitPoints?.currentHp ??
        currentHp ??
        this.currentHp;
    final resolvedTempHp =
        vitals?.temporaryHp ?? hitPoints?.tempHp ?? tempHp ?? this.tempHp;
    final resolvedDeathSaveSuccesses =
        deathSaveSuccesses ?? this.deathSaveSuccesses;
    final resolvedDeathSaveFailures =
        deathSaveFailures ?? this.deathSaveFailures;
    final resolvedExhaustionLevel = exhaustionLevel ?? this.exhaustionLevel;
    final resolvedVitals = vitals ??
        this.vitals.copyWith(
          currentHp: resolvedCurrentHp,
          temporaryHp: resolvedTempHp,
          isDowned: resolvedCurrentHp <= 0,
          isDead: (vitals?.isDead ?? false) || resolvedDeathSaveFailures >= 3,
          auxiliaryPools: {
            ...this.vitals.auxiliaryPools,
            'deathSaveSuccesses': resolvedDeathSaveSuccesses,
            'deathSaveFailures': resolvedDeathSaveFailures,
            'exhaustionLevel': resolvedExhaustionLevel,
          },
        );

    return CharacterResourcePool(
      vitals: resolvedVitals,
      currentHp: resolvedCurrentHp,
      tempHp: resolvedTempHp,
      currentHitDice: currentHitDice != null
          ? Map.unmodifiable(currentHitDice)
          : this.currentHitDice,
      spellSlots: spellSlots ?? this.spellSlots,
      customResourcesCurrent: customResourcesCurrent != null
          ? Map.unmodifiable(customResourcesCurrent)
          : this.customResourcesCurrent,
      customResourcesMax: customResourcesMax != null
          ? Map.unmodifiable(customResourcesMax)
          : this.customResourcesMax,
      deathSaveSuccesses: deathSaveSuccesses ?? this.deathSaveSuccesses,
      deathSaveFailures: deathSaveFailures ?? this.deathSaveFailures,
      exhaustionLevel: exhaustionLevel ?? this.exhaustionLevel,
      hasHeroicInspiration: hasHeroicInspiration ?? this.hasHeroicInspiration,
    );
  }

  Map<String, dynamic> toMap() => {
        'currentHp': currentHp,
        'tempHp': tempHp,
        'currentHitDice': currentHitDice,
        'spellSlots': spellSlots.toMap(),
        'customResourcesCurrent': customResourcesCurrent,
        'customResourcesMax': customResourcesMax,
        'deathSaveSuccesses': deathSaveSuccesses,
        'deathSaveFailures': deathSaveFailures,
        'exhaustionLevel': exhaustionLevel,
        'hasHeroicInspiration': hasHeroicInspiration,
      };

  factory CharacterResourcePool.fromMap(Map<String, dynamic> map) {
    final rawHp = map['currentHp'] ?? map['hp'];
    final curHp = (rawHp as num?)?.toInt() ?? 10;
    final rawThp = map['tempHp'] ?? map['thp'];
    final tHp = (rawThp as num?)?.toInt() ?? 0;
    final hp = map['hitPoints'] is Map
        ? HitPoints(
            currentHp:
                ((map['hitPoints'] as Map)['currentHp'] as num?)?.toInt() ??
                    ((map['hitPoints'] as Map)['hp'] as num?)?.toInt() ??
                    curHp,
            maxHp: ((map['hitPoints'] as Map)['maxHp'] as num?)?.toInt() ??
                ((map['hitPoints'] as Map)['mhp'] as num?)?.toInt() ??
                (map['maxHp'] as num?)?.toInt() ??
                (map['mhp'] as num?)?.toInt() ??
                9999,
            tempHp: ((map['hitPoints'] as Map)['tempHp'] as num?)?.toInt() ??
                ((map['hitPoints'] as Map)['thp'] as num?)?.toInt() ??
                tHp,
          )
        : HitPoints(currentHp: curHp, maxHp: 9999, tempHp: tHp);

    return CharacterResourcePool(
      currentHp: hp.currentHp,
      tempHp: hp.tempHp,
      currentHitDice:
          Map<String, int>.from(map['currentHitDice'] as Map? ?? {}),
      spellSlots: SpellSlotPool.fromMap(
          Map<String, dynamic>.from(map['spellSlots'] as Map? ?? {})),
      customResourcesCurrent:
          Map<String, int>.from(map['customResourcesCurrent'] as Map? ?? {}),
      customResourcesMax:
          Map<String, int>.from(map['customResourcesMax'] as Map? ?? {}),
      deathSaveSuccesses: (map['deathSaveSuccesses'] as num?)?.toInt() ?? 0,
      deathSaveFailures: (map['deathSaveFailures'] as num?)?.toInt() ?? 0,
      exhaustionLevel: (map['exhaustionLevel'] as num?)?.toInt() ?? 0,
      hasHeroicInspiration: map['hasHeroicInspiration'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterResourcePool &&
          runtimeType == other.runtimeType &&
          vitals == other.vitals &&
          mapEquals(currentHitDice, other.currentHitDice) &&
          spellSlots == other.spellSlots &&
          mapEquals(customResourcesCurrent, other.customResourcesCurrent) &&
          mapEquals(customResourcesMax, other.customResourcesMax) &&
          deathSaveSuccesses == other.deathSaveSuccesses &&
          deathSaveFailures == other.deathSaveFailures &&
          exhaustionLevel == other.exhaustionLevel &&
          hasHeroicInspiration == other.hasHeroicInspiration;

  @override
  int get hashCode =>
      vitals.hashCode ^
      currentHitDice.length.hashCode ^
      spellSlots.hashCode ^
      customResourcesCurrent.length.hashCode ^
      customResourcesMax.length.hashCode ^
      deathSaveSuccesses.hashCode ^
      deathSaveFailures.hashCode ^
      exhaustionLevel.hashCode ^
      hasHeroicInspiration.hashCode;
}

/// Active Condition and Temporary Status Effect
@immutable
class CharacterCondition {
  final String conditionName; // e.g. "blinded", "poisoned", "haste"
  final int durationSeconds; // 0 = indefinite
  final String? source; // spell or effect name
  final Map<String, dynamic> parameters;

  const CharacterCondition({
    required this.conditionName,
    this.durationSeconds = 0,
    this.source,
    this.parameters = const {},
  });

  CharacterCondition copyWith({
    String? conditionName,
    int? durationSeconds,
    String? source,
    Map<String, dynamic>? parameters,
  }) {
    return CharacterCondition(
      conditionName: conditionName ?? this.conditionName,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      source: source ?? this.source,
      parameters:
          parameters != null ? Map.unmodifiable(parameters) : this.parameters,
    );
  }

  Map<String, dynamic> toMap() => {
        'conditionName': conditionName,
        'durationSeconds': durationSeconds,
        'source': source,
        'parameters': parameters,
      };

  factory CharacterCondition.fromMap(Map<String, dynamic> map) {
    return CharacterCondition(
      conditionName: map['conditionName']?.toString() ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      source: map['source']?.toString(),
      parameters: Map<String, dynamic>.from(map['parameters'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterCondition &&
          runtimeType == other.runtimeType &&
          conditionName == other.conditionName &&
          durationSeconds == other.durationSeconds &&
          source == other.source &&
          mapEquals(parameters, other.parameters);

  @override
  int get hashCode =>
      conditionName.hashCode ^
      durationSeconds.hashCode ^
      (source?.hashCode ?? 0) ^
      parameters.length.hashCode;
}

/// A Set representation for saving throw and trait keys that supports transparent
/// membership tests against either canonical String keys or legacy Enum tokens.
@immutable
class AttributeKeySet with SetMixin<String> {
  final Set<String> _inner;

  const AttributeKeySet([this._inner = const {}]);

  factory AttributeKeySet.from(Iterable<dynamic>? iterable) {
    if (iterable == null) return const AttributeKeySet();
    final set = <String>{};
    for (final item in iterable) {
      if (item is Enum) {
        set.add(item.name.toLowerCase());
      } else if (item != null) {
        set.add(item.toString().trim().toLowerCase());
      }
    }
    return AttributeKeySet(Set.unmodifiable(set));
  }

  @override
  bool contains(Object? element) {
    if (element == null) return false;
    if (_inner.contains(element)) return true;
    final elementKey = element is Enum
        ? element.name.toLowerCase()
        : element.toString().toLowerCase().trim();
    return _inner.contains(elementKey);
  }

  @override
  Iterator<String> get iterator => _inner.iterator;

  @override
  int get length => _inner.length;

  @override
  String? lookup(Object? element) {
    if (contains(element)) {
      final elementKey = element is Enum
          ? element.name.toLowerCase()
          : element.toString().toLowerCase().trim();
      return _inner.lookup(elementKey);
    }
    return null;
  }

  @override
  bool add(String value) =>
      throw UnsupportedError('AttributeKeySet is unmodifiable');

  @override
  bool remove(Object? value) =>
      throw UnsupportedError('AttributeKeySet is unmodifiable');

  @override
  Set<String> toSet() => Set<String>.from(_inner);
}

/// Root Character Domain Entity adhering to DomainEntity interface
@immutable
class Character extends DomainEntity {
  @override
  final EntityId id;
  @override
  final String name;
  final EntityReference<DomainEntity> speciesRef;
  final EntityReference<DomainEntity>? backgroundRef;
  final CharacterProgression progression;
  final AttributePool baseScores;
  final AttributePool
      bonusScores; // Permanent bonuses from species/background/feats
  final Map<dynamic, dynamic> traitProficiencies;
  final Set<dynamic> savingThrowProficiencies;
  final List<String> toolProficiencies;
  final List<String> languages;
  final List<InventoryItemInstance> inventory;
  final PartyPurse purse;
  final Map<String, List<EntityReference<Spell>>> allocatedSpells;
  final List<EntityReference<Spell>> _cantrips;
  final List<EntityReference<Spell>> _spellsKnown;
  final List<EntityReference<Spell>> spellsPrepared;
  final List<EntityReference<DomainEntity>> feats;
  final CharacterResourcePool resources;
  final List<CharacterCondition> conditions;
  final int maxAttunementSlots;
  final int baseSpeedFeet;
  final String rulesetId;
  @override
  final Map<String, dynamic> customProperties;

  const Character({
    required this.id,
    required this.name,
    required this.speciesRef,
    this.backgroundRef,
    required this.progression,
    required this.baseScores,
    this.bonusScores = const AttributePool.zero(),
    Map<dynamic, dynamic>? traitProficiencies,
    Map<dynamic, dynamic>? skillProficiencies,
    this.savingThrowProficiencies = const AttributeKeySet(),
    this.toolProficiencies = const [],
    this.languages = const ['Common'],
    this.inventory = const [],
    this.purse = const PartyPurse(),
    this.allocatedSpells = const {},
    List<EntityReference<Spell>> cantrips = const [],
    List<EntityReference<Spell>> spellsKnown = const [],
    this.spellsPrepared = const [],
    this.feats = const [],
    required this.resources,
    this.conditions = const [],
    this.maxAttunementSlots = 3,
    this.baseSpeedFeet = 30,
    String rulesetId = 'dnd5e_2014',
    RulesetEdition? rulesEdition,
    this.customProperties = const {},
  })  : traitProficiencies =
            traitProficiencies ?? skillProficiencies ?? const {},
        _cantrips = cantrips,
        _spellsKnown = spellsKnown,
        rulesetId = rulesEdition == RulesetEdition.v2024
            ? 'dnd5e_2024'
            : (rulesEdition == RulesetEdition.v2014 ? 'dnd5e_2014' : rulesetId);

  @override
  EntityType get entityType => EntityType.character;

  int get totalLevel => progression.totalLevel;
  int get proficiencyBonus => totalLevel <= 0 ? 2 : ((totalLevel - 1) ~/ 4) + 2;

  String get classesSummary {
    if (progression.classes.isEmpty) return 'Adventurer';
    return progression.classes
        .map((c) => '${c.classRef.displayName} ${c.level}')
        .join(' / ');
  }

  /// Machine-readable identifier of the active ruleset module.
  String get activeModuleId =>
      rulesetId.contains('2024') ? 'dnd5e_2024' : 'dnd5e_2014';

  /// Canonical ruleset edition of this character.
  RulesetEdition get rulesEdition => switch (rulesetId) {
        'dnd5e_2014' || 'v2014' || '5e-2014' => RulesetEdition.v2014,
        _ => RulesetEdition.v2024,
      };

  /// Optional injected evaluator for complex ruleset-specific max HP calculations.
  static int Function(Character character)? maxHpEvaluator;

  /// Evaluated maximum Hit Points, checking customProperties, injected evaluator, or vitals.
  int get evaluatedMaxHp {
    if (customProperties['maxHp'] is num) {
      return (customProperties['maxHp'] as num).toInt();
    }
    if (maxHpEvaluator != null) {
      try {
        return maxHpEvaluator!(this);
      } catch (_) {}
    }
    final mhp = resources.hitPoints.maxHp;
    if (mhp > 0 && mhp != 9999) return mhp;
    return math.max(10, resources.currentHp);
  }

  /// Ruleset-agnostic vitals model exposing current HP, max HP, temp HP, downed, and death states.
  EntityVitals get vitals => EntityVitals(
        currentHp: resources.currentHp,
        maxHp: resources.hitPoints.maxHp,
        temporaryHp: resources.tempHp,
        isDowned: resources.hitPoints.isDowned,
        isDead: resources.deathSaveFailures >= 3 || resources.hitPoints.isDead,
        auxiliaryPools: {
          'death_save_successes': resources.deathSaveSuccesses,
          'death_save_failures': resources.deathSaveFailures,
          'exhaustion_level': resources.exhaustionLevel,
        },
      );

  /// Map of canonical attribute keys to effective score values.
  Map<String, int> get attributeScores => {
        'strength': effectiveAbilityScores.strength,
        'dexterity': effectiveAbilityScores.dexterity,
        'constitution': effectiveAbilityScores.constitution,
        'intelligence': effectiveAbilityScores.intelligence,
        'wisdom': effectiveAbilityScores.wisdom,
        'charisma': effectiveAbilityScores.charisma,
      };

  /// Retrieves an attribute score by key (e.g. 'strength', 'dexterity', etc.).
  int getAttributeScore(String key, [int fallback = 10]) =>
      attributeScores[key.trim().toLowerCase()] ?? fallback;

  /// Pluggable resolver callback to determine a spell's level from its slug
  /// when entity references lack embedded level metadata.
  static int? Function(String slug)? spellLevelResolver;

  bool _isCantripRef(String? slotGroupKey, EntityReference<Spell> ref) {
    if (ref.customProperties['isCantrip'] == true) return true;
    final level =
        ref.customProperties['level'] ?? spellLevelResolver?.call(ref.slug);
    if (level is num && level == 0) return true;
    if (level is String && (level == '0' || level.toLowerCase() == 'cantrip'))
      return true;
    if (slotGroupKey != null) {
      final k = slotGroupKey.toLowerCase().trim();
      if (k.contains('cantrip') || k == '0') return true;
    }
    if (ref.slug.toLowerCase().contains('cantrip')) return true;
    return false;
  }

  bool _isLeveledSpellRef(String? slotGroupKey, EntityReference<Spell> ref) {
    if (_isCantripRef(slotGroupKey, ref)) return false;
    final level =
        ref.customProperties['level'] ?? spellLevelResolver?.call(ref.slug);
    if (level is num && level > 0) return true;
    if (level is String && int.tryParse(level) != null && int.parse(level) > 0)
      return true;
    if (slotGroupKey != null) {
      final k = slotGroupKey.toLowerCase().trim();
      if (k.contains('cantrip') || k == '0') return false;
      if (k.contains('spell') ||
          k.contains('known') ||
          k.contains('prep') ||
          k.contains('domain') ||
          k.contains('legacy') ||
          k.contains('bloodline')) {
        return true;
      }
    }
    return true;
  }

  List<EntityReference<Spell>> get cantrips {
    final list = <EntityReference<Spell>>[];
    for (final entry in allocatedSpells.entries) {
      final groupKey = entry.key;
      final spells = entry.value;
      for (final s in spells) {
        if (_isCantripRef(groupKey, s) && !list.any((e) => e.slug == s.slug)) {
          list.add(s);
        }
      }
    }
    for (final c in _cantrips) {
      if (!list.any((e) => e.slug == c.slug)) {
        list.add(c);
      }
    }
    return List.unmodifiable(list);
  }

  List<EntityReference<Spell>> get spellsKnown {
    final list = <EntityReference<Spell>>[];
    for (final entry in allocatedSpells.entries) {
      final groupKey = entry.key;
      final spells = entry.value;
      for (final s in spells) {
        if (_isLeveledSpellRef(groupKey, s) &&
            !list.any((e) => e.slug == s.slug)) {
          list.add(s);
        }
      }
    }
    for (final s in _spellsKnown) {
      if (!list.any((e) => e.slug == s.slug)) {
        list.add(s);
      }
    }
    return List.unmodifiable(list);
  }

  /// Raw ability scores (base scores with permanent bonuses from species/ASI/feats)
  AbilityScores get rawAbilityScores => baseScores.withBonus(bonusScores);

  /// Returns the inherent maximum score allowed for [attributeKey].
  /// Defaults to standard tabletop 20, but accounts for Level 20 Barbarian capstone (24 for STR/CON)
  /// and any permanent inherent maximum increases stored in [customProperties] under 'abilityMaximums'.
  int getAbilityScoreMaximum(dynamic attributeKey) {
    int maxCap = 20;
    final clean = (attributeKey is String
            ? attributeKey
            : (attributeKey is Enum
                ? attributeKey.name
                : attributeKey.toString()))
        .trim()
        .toLowerCase();
    // Check Barbarian Level 20 Capstone
    final isBarbarian20 = progression.classes.any(
      (c) => c.classRef.slug.toLowerCase() == 'barbarian' && c.level >= 20,
    );
    if (isBarbarian20 && (clean == 'strength' || clean == 'constitution')) {
      maxCap = math.max(maxCap, 24);
    }
    // Check customProperties / permanent inherent tomes
    if (customProperties['abilityMaximums'] is Map) {
      final map = customProperties['abilityMaximums'] as Map;
      final val = (map[clean] as num?)?.toInt();
      if (val != null) {
        maxCap = math.max(maxCap, val);
      }
    }
    return maxCap.clamp(20, 30);
  }

  /// Effective ability scores (evaluates rawAbilityScores and applies hard overrides from attuned/equipped items or custom properties)
  AbilityScores get effectiveAbilityScores {
    final scores = Map<String, int>.from(rawAbilityScores.attributes);

    for (final instance in equippedItems) {
      if (instance.requiresAttunement && !instance.isAttuned) continue;
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

    return AbilityScores(
      strength: scores['strength'] ?? 10,
      dexterity: scores['dexterity'] ?? 10,
      constitution: scores['constitution'] ?? 10,
      intelligence: scores['intelligence'] ?? 10,
      wisdom: scores['wisdom'] ?? 10,
      charisma: scores['charisma'] ?? 10,
      customAttributes: Map.unmodifiable(scores),
    );
  }

  int get attunedItemCount => inventory.where((item) => item.isAttuned).length;

  List<InventoryItemInstance> get equippedItems =>
      inventory.where((item) => item.isEquipped).toList();

  /// Returns all active [FeatureGrant]s attached to this character from custom properties,
  /// granted feats, classes, subclasses, and inventory equipment.
  List<FeatureGrant> get activeGrants {
    final list = <FeatureGrant>[];

    void extractGrants(dynamic rawGrants) {
      if (rawGrants is! List) return;
      for (final item in rawGrants) {
        if (item is FeatureGrant) {
          list.add(item);
        } else if (item is Map) {
          list.add(FeatureGrant.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    // 1. Direct grants in customProperties['grants']
    extractGrants(customProperties['grants']);

    // 2. Feats embedded grants
    for (final featRef in feats) {
      extractGrants(featRef.customProperties['grants']);
    }

    // 3. Classes and Subclasses embedded grants
    for (final c in progression.classes) {
      extractGrants(c.classRef.customProperties['grants']);
      if (c.subclassRef != null) {
        extractGrants(c.subclassRef!.customProperties['grants']);
      }
    }

    // 4. Equipped items embedded grants
    for (final item in equippedItems) {
      if (item.requiresAttunement && !item.isAttuned) continue;
      extractGrants(item.customProperties['grants']);
      extractGrants(item.itemRef.customProperties['grants']);
    }

    return List.unmodifiable(list);
  }

  /// Evaluates whether the character has a specific capability flag enabled from any selected
  /// feature option, feat, class feature, active FeatureGrant, or custom properties.
  bool hasCapabilityFlag(String flagKey) {
    if (customProperties[flagKey] == true) return true;
    final normalizedKey = flagKey.toLowerCase().replaceAll('-', '_');
    if (customProperties[normalizedKey] == true) return true;

    // Check customProperties['flags']
    if (customProperties['flags'] is Map) {
      final flagsMap = customProperties['flags'] as Map;
      if (flagsMap[flagKey] == true || flagsMap[normalizedKey] == true) {
        return true;
      }
    }

    // Check active FeatureGrants
    for (final g in activeGrants) {
      if (g.type == GrantType.capabilityFlag) {
        final key =
            g.payload['flagKey']?.toString().toLowerCase().replaceAll('-', '_');
        if (key == normalizedKey || key == flagKey.toLowerCase()) {
          return true;
        }
      }
    }

    // Feature Options (fighting styles, invocations, pact boons, etc.)
    final allSelectedOptions = progression.getAllSelectedFeatureOptions();
    for (final optionIds in allSelectedOptions.values) {
      for (final optId in optionIds) {
        final normOptId = optId.toLowerCase().replaceAll('-', '_');
        if (normOptId == normalizedKey) return true;
        if ((flagKey == 'eldritchBlastChaDamage' ||
                flagKey == 'agonizing_blast') &&
            normOptId == 'agonizing_blast') {
          return true;
        }
      }
    }

    // Generic SRD mechanics
    if (flagKey == 'jackOfAllTrades' || normalizedKey == 'jack_of_all_trades') {
      final bardClass = progression.classes
          .where((c) =>
              c.classRef.slug.toLowerCase().contains('bard') ||
              c.classRef.displayName.toLowerCase().contains('bard'))
          .firstOrNull;
      if (bardClass != null && bardClass.level >= 2) {
        return true;
      }
    }

    // Generic capability mapping aliases
    if (flagKey == 'homebrewArmorExpert') {
      return hasCapabilityFlag('mediumArmorDexCapBonus');
    }
    if (flagKey == 'homebrewInitiativeBoost') {
      return hasCapabilityFlag('initiativeBonusMode');
    }

    return false;
  }

  /// Generic stat query interface allowing ruleset modules or external engines
  /// to resolve derived statistics dynamically without hardcoded rules in the entity.
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

  /// Resolves an attribute modifier dynamically by string key using [effectiveAbilityScores],
  /// optionally evaluated via the provided [IAttributeSystem].
  int getAttributeModifier(String key, [IAttributeSystem? system]) =>
      effectiveAbilityScores.getModifierByKey(key, system);

  /// Resolves trait proficiency multiplier dynamically (e.g. 1.0 for proficient, 2.0 for expertise).
  double getTraitProficiency(dynamic traitKey) {
    final clean = (traitKey is Enum ? traitKey.name : traitKey.toString())
        .trim()
        .toLowerCase();
    for (final entry in traitProficiencies.entries) {
      final key = entry.key;
      final keyStr =
          (key is Enum ? key.name : key.toString()).trim().toLowerCase();
      if (keyStr == clean) {
        final val = entry.value;
        if (val is num) return val.toDouble();
        if (val is Enum) {
          if (val.name == 'expertise') return 2.0;
          if (val.name == 'proficient') return 1.0;
          if (val.name == 'jackOfAllTrades') return 0.5;
        }
        final valStr = val.toString().toLowerCase();
        if (valStr.contains('expertise')) return 2.0;
        if (valStr.contains('proficient')) return 1.0;
        if (valStr.contains('jackofalltrades') ||
            valStr.contains('jack_of_all_trades')) return 0.5;
        return 0.0;
      }
    }
    return 0.0;
  }

  /// Whether the character is proficient in saving throws for [key].
  bool hasSavingThrowProficiency(dynamic key) =>
      savingThrowProficiencies.contains(key);

  /// Resolves skill or trait modifier dynamically from generic [ITraitDefinition].
  int getTraitModifier(ITraitDefinition trait,
      [IAttributeSystem? attributeSystem]) {
    final attrKey = trait.governedAttribute;
    final baseMod =
        attrKey != null ? getAttributeModifier(attrKey, attributeSystem) : 0;
    final mult = getTraitProficiency(trait.id);
    final bonus = (proficiencyBonus * mult).floor();
    return baseMod + bonus;
  }

  /// Dynamic Saving Throw Modifier calculation factoring in ability modifiers and proficiency.
  int getSaveModifier(dynamic attributeKey) {
    final keyStr =
        (attributeKey is Enum ? attributeKey.name : attributeKey.toString())
            .trim()
            .toLowerCase();
    final baseMod = getAttributeModifier(keyStr);
    final isProficient = hasSavingThrowProficiency(attributeKey);
    return baseMod + (isProficient ? proficiencyBonus : 0);
  }

  @override
  Map<String, dynamic> toMap() => {
        'id': id.toMap(),
        'name': name,
        'speciesRef': speciesRef.toMap(),
        'backgroundRef': backgroundRef?.toMap(),
        'progression': progression.toMap(),
        'baseScores': baseScores.toMap(),
        'bonusScores': bonusScores.toMap(),
        'traitProficiencies': traitProficiencies,
        'skillProficiencies': traitProficiencies,
        'savingThrowProficiencies': savingThrowProficiencies.toList(),
        'toolProficiencies': toolProficiencies,
        'languages': languages,
        'inventory': inventory.map((i) => i.toMap()).toList(),
        'purse': purse.toMap(),
        'allocatedSpells': allocatedSpells.map(
          (k, v) => MapEntry(k, v.map((s) => s.toMap()).toList()),
        ),
        'cantrips': cantrips.map((c) => c.toMap()).toList(),
        'spellsKnown': spellsKnown.map((s) => s.toMap()).toList(),
        'spellsPrepared': spellsPrepared.map((s) => s.toMap()).toList(),
        'feats': feats.map((f) => f.toMap()).toList(),
        'resources': resources.toMap(),
        'currentHp': resources.currentHp,
        'maxHp': evaluatedMaxHp,
        'tempHp': resources.tempHp,
        'armorClass': queryStat('ac'),
        'conditions': conditions.map((c) => c.toMap()).toList(),
        'maxAttunementSlots': maxAttunementSlots,
        'baseSpeedFeet': baseSpeedFeet,
        'rulesetId': rulesetId,
        'rulesEdition': rulesEdition.name,
        'customProperties': customProperties,
      };

  factory Character.fromMap(Map<String, dynamic> map) {
    final traits = <String, double>{};
    if (map['traitProficiencies'] is Map) {
      (map['traitProficiencies'] as Map).forEach((k, v) {
        if (v is num) traits[k.toString().toLowerCase().trim()] = v.toDouble();
      });
    } else if (map['skillProficiencies'] is Map) {
      (map['skillProficiencies'] as Map).forEach((k, v) {
        final valStr = v.toString().toLowerCase().trim();
        final mult = switch (valStr) {
          'expertise' => 2.0,
          'proficient' => 1.0,
          'jackofalltrades' => 0.5,
          _ => (v is num) ? v.toDouble() : 1.0,
        };
        traits[k.toString().toLowerCase().trim()] = mult;
      });
    }

    final saves = <String>{};
    if (map['savingThrowProficiencies'] is List) {
      for (final s in (map['savingThrowProficiencies'] as List)) {
        saves.add(s.toString().toLowerCase().trim());
      }
    }

    final resolvedRulesetId = map['rulesetId']?.toString() ??
        map['rulesEdition']?.toString() ??
        'dnd5e_2014';

    final rawAllocated = map['allocatedSpells'];
    final parsedAllocated = <String, List<EntityReference<Spell>>>{};
    if (rawAllocated is Map) {
      rawAllocated.forEach((k, v) {
        if (v is List) {
          parsedAllocated[k.toString()] = v
              .whereType<Map>()
              .map((s) =>
                  EntityReference<Spell>.fromMap(Map<String, dynamic>.from(s)))
              .toList();
        }
      });
    }

    final parsedCantrips = (map['cantrips'] as List? ?? [])
        .whereType<Map>()
        .map(
            (c) => EntityReference<Spell>.fromMap(Map<String, dynamic>.from(c)))
        .toList();

    final parsedSpellsKnown = (map['spellsKnown'] as List? ?? [])
        .whereType<Map>()
        .map(
            (s) => EntityReference<Spell>.fromMap(Map<String, dynamic>.from(s)))
        .toList();

    if (parsedAllocated.isEmpty) {
      if (parsedCantrips.isNotEmpty) {
        parsedAllocated['cantrips'] = parsedCantrips;
      }
      if (parsedSpellsKnown.isNotEmpty) {
        parsedAllocated['spellsKnown'] = parsedSpellsKnown;
      }
    }

    return Character(
      id: map['id'] is Map
          ? EntityId.fromMap(Map<String, dynamic>.from(map['id'] as Map))
          : EntityId(
              slug: map['id']?.toString() ?? '', ruleset: RulesetVersion.v2024),
      name: map['name']?.toString() ?? '',
      speciesRef: EntityReference<DomainEntity>.fromMap(
          Map<String, dynamic>.from(map['speciesRef'] as Map? ?? {})),
      backgroundRef: map['backgroundRef'] != null
          ? EntityReference<DomainEntity>.fromMap(
              Map<String, dynamic>.from(map['backgroundRef'] as Map? ?? {}))
          : null,
      progression: CharacterProgression.fromMap(
          Map<String, dynamic>.from(map['progression'] as Map? ?? {})),
      baseScores: AbilityScores.fromMap(
          Map<String, dynamic>.from(map['baseScores'] as Map? ?? {})),
      bonusScores: AbilityScores.fromMap(
          Map<String, dynamic>.from(map['bonusScores'] as Map? ?? {})),
      traitProficiencies: traits,
      savingThrowProficiencies: AttributeKeySet.from(saves),
      toolProficiencies: (map['toolProficiencies'] as List? ?? [])
          .whereType<String>()
          .toList(),
      languages: (map['languages'] as List? ?? ['Common'])
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
          : const PartyPurse(),
      allocatedSpells: parsedAllocated,
      cantrips: parsedCantrips,
      spellsKnown: parsedSpellsKnown,
      spellsPrepared: (map['spellsPrepared'] as List? ?? [])
          .whereType<Map>()
          .map((s) =>
              EntityReference<Spell>.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      feats: (map['feats'] as List? ?? [])
          .whereType<Map>()
          .map((f) => EntityReference<DomainEntity>.fromMap(
              Map<String, dynamic>.from(f)))
          .toList(),
      resources: CharacterResourcePool.fromMap(
          map['resources'] is Map && (map['resources'] as Map).isNotEmpty
              ? Map<String, dynamic>.from(map['resources'] as Map)
              : <String, dynamic>{
                  if (map['currentHp'] != null) 'currentHp': map['currentHp'],
                  if (map['hp'] != null) 'currentHp': map['hp'],
                  if (map['maxHp'] != null) 'maxHp': map['maxHp'],
                  if (map['tempHp'] != null) 'tempHp': map['tempHp'],
                  if (map['thp'] != null) 'tempHp': map['thp'],
                  if (map['deathSaveSuccesses'] != null)
                    'deathSaveSuccesses': map['deathSaveSuccesses'],
                  if (map['dss'] != null) 'deathSaveSuccesses': map['dss'],
                  if (map['deathSaveFailures'] != null)
                    'deathSaveFailures': map['deathSaveFailures'],
                  if (map['dsf'] != null) 'deathSaveFailures': map['dsf'],
                  if (map['exhaustionLevel'] != null)
                    'exhaustionLevel': map['exhaustionLevel'],
                  if (map['ex'] != null) 'exhaustionLevel': map['ex'],
                }),
      conditions: (map['conditions'] as List? ?? [])
          .whereType<Map>()
          .map((c) => CharacterCondition.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      maxAttunementSlots: (map['maxAttunementSlots'] as num?)?.toInt() ?? 3,
      baseSpeedFeet: (map['baseSpeedFeet'] as num?)?.toInt() ?? 30,
      rulesetId: resolvedRulesetId,
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  Character copyWith({
    EntityId? id,
    String? name,
    EntityReference<DomainEntity>? speciesRef,
    EntityReference<DomainEntity>? backgroundRef,
    CharacterProgression? progression,
    AttributePool? baseScores,
    AttributePool? bonusScores,
    Map<String, double>? traitProficiencies,
    dynamic skillProficiencies,
    Set<dynamic>? savingThrowProficiencies,
    List<String>? toolProficiencies,
    List<String>? languages,
    List<InventoryItemInstance>? inventory,
    PartyPurse? purse,
    Map<String, List<EntityReference<Spell>>>? allocatedSpells,
    List<EntityReference<Spell>>? cantrips,
    List<EntityReference<Spell>>? spellsKnown,
    List<EntityReference<Spell>>? spellsPrepared,
    List<EntityReference<DomainEntity>>? feats,
    CharacterResourcePool? resources,
    List<CharacterCondition>? conditions,
    int? maxAttunementSlots,
    int? baseSpeedFeet,
    String? rulesetId,
    dynamic rulesEdition,
    Map<String, dynamic>? customProperties,
  }) {
    Map<dynamic, dynamic>? effectiveTraits = traitProficiencies;
    if (skillProficiencies is Map) {
      effectiveTraits = Map<dynamic, dynamic>.from(skillProficiencies);
    }

    AttributeKeySet? effectiveSaves;
    if (savingThrowProficiencies != null) {
      effectiveSaves = AttributeKeySet.from(savingThrowProficiencies);
    }

    final effectiveRulesetId = rulesEdition != null
        ? (rulesEdition is Enum ? rulesEdition.name : rulesEdition.toString())
        : (rulesetId ?? this.rulesetId);

    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      speciesRef: speciesRef ?? this.speciesRef,
      backgroundRef: backgroundRef ?? this.backgroundRef,
      progression: progression ?? this.progression,
      baseScores: baseScores ?? this.baseScores,
      bonusScores: bonusScores ?? this.bonusScores,
      traitProficiencies: effectiveTraits != null
          ? Map.unmodifiable(effectiveTraits)
          : this.traitProficiencies,
      savingThrowProficiencies: effectiveSaves ?? this.savingThrowProficiencies,
      toolProficiencies: toolProficiencies != null
          ? List.unmodifiable(toolProficiencies)
          : this.toolProficiencies,
      languages:
          languages != null ? List.unmodifiable(languages) : this.languages,
      inventory:
          inventory != null ? List.unmodifiable(inventory) : this.inventory,
      purse: purse ?? this.purse,
      allocatedSpells: allocatedSpells != null
          ? Map.unmodifiable(allocatedSpells.map((k, v) =>
              MapEntry(k, List<EntityReference<Spell>>.unmodifiable(v))))
          : this.allocatedSpells,
      cantrips: cantrips != null ? List.unmodifiable(cantrips) : _cantrips,
      spellsKnown:
          spellsKnown != null ? List.unmodifiable(spellsKnown) : _spellsKnown,
      spellsPrepared: spellsPrepared != null
          ? List.unmodifiable(spellsPrepared)
          : this.spellsPrepared,
      feats: feats != null ? List.unmodifiable(feats) : this.feats,
      resources: resources ?? this.resources,
      conditions:
          conditions != null ? List.unmodifiable(conditions) : this.conditions,
      maxAttunementSlots: maxAttunementSlots ?? this.maxAttunementSlots,
      baseSpeedFeet: baseSpeedFeet ?? this.baseSpeedFeet,
      rulesetId: effectiveRulesetId,
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
          mapEquals(traitProficiencies, other.traitProficiencies) &&
          setEquals(savingThrowProficiencies, other.savingThrowProficiencies) &&
          listEquals(toolProficiencies, other.toolProficiencies) &&
          listEquals(languages, other.languages) &&
          listEquals(inventory, other.inventory) &&
          purse == other.purse &&
          mapEquals(allocatedSpells, other.allocatedSpells) &&
          listEquals(spellsPrepared, other.spellsPrepared) &&
          listEquals(feats, other.feats) &&
          resources == other.resources &&
          listEquals(conditions, other.conditions) &&
          maxAttunementSlots == other.maxAttunementSlots &&
          baseSpeedFeet == other.baseSpeedFeet &&
          rulesetId == other.rulesetId &&
          mapEquals(customProperties, other.customProperties);

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      speciesRef.hashCode ^
      (backgroundRef?.hashCode ?? 0) ^
      progression.hashCode ^
      baseScores.hashCode ^
      bonusScores.hashCode ^
      traitProficiencies.length.hashCode ^
      savingThrowProficiencies.length.hashCode ^
      toolProficiencies.length.hashCode ^
      languages.length.hashCode ^
      inventory.length.hashCode ^
      purse.hashCode ^
      allocatedSpells.length.hashCode ^
      spellsPrepared.length.hashCode ^
      feats.length.hashCode ^
      resources.hashCode ^
      conditions.length.hashCode ^
      maxAttunementSlots.hashCode ^
      baseSpeedFeet.hashCode ^
      rulesetId.hashCode ^
      customProperties.length.hashCode;
}
