import 'package:meta/meta.dart';

/// Atomic token types for declarative mechanic grants emitted by feats,
/// races, backgrounds, class features, subclasses, and equipment items.
enum GrantType {
  /// Grants a bonus prepared/known spell (payload: {slug, displayName}).
  bonusSpell,

  /// Grants proficiency in a specific skill (payload: {skill}).
  bonusSkill,

  /// Grants proficiency in a specific tool (payload: {tool}).
  bonusTool,

  /// Grants proficiency in a language (payload: {language}).
  bonusLanguage,

  /// Grants a bonus feat selection (payload: {category?}).
  bonusFeat,

  /// Overrides or supplements the AC calculation formula when unarmored
  /// or in specific contexts (payload: {formula, primaryAbility?,
  /// secondaryAbility?, requiresNoArmor, requiresNoShield}).
  acFormula,

  /// Applies a flat or formula-driven bonus to a passive stat
  /// (payload: {stat, formula, flat?}).
  /// Supported stat keys: 'initiative', 'passivePerception', 'speed'.
  passiveModifier,

  /// Grants weapon or armor proficiency (payload: {proficiency, category?}).
  proficiency,

  /// Defines a named character action or feature
  /// (payload: {actionName, usesResource?, resourceName?}).
  actionDefinition,

  /// Grants a flat bonus to a specific ability score
  /// (payload: {ability, amount}).
  abilityScoreBoost,

  /// Flat or per-level HP bonus (payload: {flat?, perLevel?}).
  hpModifier,

  /// Flat speed bonus/penalty in feet (payload: {amount}).
  speedModifier,

  /// Grants damage resistance to a damage type (payload: {damageType}).
  resistanceGrant,

  /// Grants Expertise (double proficiency bonus) on a skill
  /// (payload: {skill}).
  expertiseGrant,

  /// Grants a fixed number of flexible bonus skills chosen from a pool
  /// (payload: {count, pool?}).
  bonusSkillChoice,

  /// Grants darkvision or extends existing darkvision range
  /// (payload: {feet}).
  darkvision,

  /// Grants cantrip access (payload: {count, castingAbility?}).
  bonusCantrip,

  /// Overrides or allows alternative ability score for attack and damage rolls
  /// (e.g., Mental for magic weapons, Presence for pact weapons).
  /// Payload: {ability, requiresMagic?, condition?}.
  attackAbilitySubstitution,

  /// Grants a boolean capability flag (e.g. 'mediumArmorDexCapBonus', 'initiativeBonusMode').
  /// Payload: {flagKey}.
  capabilityFlag,
}

/// A single typed mechanic grant attached to a domain entity.
@immutable
class FeatureGrant {
  final GrantType type;
  final String grantId;

  /// Type-specific structured data. The expected keys are documented on
  /// each [GrantType] value and enforced by the typed factory constructors.
  final Map<String, dynamic> payload;

  /// Optional human-readable label for display in the UI.
  final String? label;

  /// Optional hooks for ACL parser implementations in the infrastructure/application layer.
  static Map<String, bool> Function(dynamic addSpellsData)?
      spellDescriptorExtractor;
  static Set<String> Function(dynamic addSpellsData)? spellNameExtractor;
  static List<FeatureGrant> Function(
          dynamic addSpellsData, String ownerPrefix, String ownerSlug)?
      bonusSpellsExtractor;

  const FeatureGrant({
    required this.type,
    required this.grantId,
    this.payload = const {},
    this.label,
  });

  // ---------------------------------------------------------------------------
  // Typed factory constructors
  // ---------------------------------------------------------------------------

  /// +[amount] HP flat, or +[perLevel] HP per character level (Tough feat style).
  factory FeatureGrant.hpBonus({
    required String grantId,
    int flat = 0,
    int perLevel = 0,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.hpModifier,
        grantId: grantId,
        payload: {
          if (flat != 0) 'flat': flat,
          if (perLevel != 0) 'perLevel': perLevel,
        },
        label: label,
      );

  /// Unarmored Defense formula: 10 + DEX + [primaryAbility] (+ [secondaryAbility]?).
  factory FeatureGrant.unarmoredDefense({
    required String grantId,
    required String primaryAbility,
    String? secondaryAbility,
    bool requiresNoShield = false,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.acFormula,
        grantId: grantId,
        payload: {
          'formula': 'unarmored_defense',
          'primaryAbility': primaryAbility,
          if (secondaryAbility != null) 'secondaryAbility': secondaryAbility,
          'requiresNoArmor': true,
          'requiresNoShield': requiresNoShield,
        },
        label: label ?? 'Unarmored Defense',
      );

  /// Draconic Resilience: base AC 13 + DEX (no armor required, no shield restriction).
  factory FeatureGrant.draconicResilience({
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.acFormula,
        grantId: grantId,
        payload: {
          'formula': 'draconic_resilience',
          'baseAc': 13,
          'requiresNoArmor': true,
          'requiresNoShield': false,
        },
        label: label ?? 'Draconic Resilience',
      );

  /// +[amount] AC bonus (e.g., Defense Fighting Style: +1 AC while in armor).
  factory FeatureGrant.acBonus({
    required String grantId,
    required int amount,
    bool requiresArmor = false,
    bool requiresNoArmor = false,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.acFormula,
        grantId: grantId,
        payload: {
          'formula': 'flat_bonus',
          'amount': amount,
          if (requiresArmor) 'requiresArmor': true,
          if (requiresNoArmor) 'requiresNoArmor': true,
        },
        label: label,
      );

  /// +[amount] to [stat]. Supported stats: 'initiative', 'passivePerception', 'speed'.
  factory FeatureGrant.passiveBonus({
    required String grantId,
    required String stat,
    required String formula,
    int? flat,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.passiveModifier,
        grantId: grantId,
        payload: {
          'stat': stat,
          'formula': formula,
          if (flat != null) 'flat': flat,
        },
        label: label,
      );

  /// Proficiency with a specific skill.
  factory FeatureGrant.skillProficiency(
    String skill, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.bonusSkill,
        grantId: grantId,
        payload: {'skill': skill},
        label: label,
      );

  /// Choose [count] skills from an optional [pool] (null = any skill).
  factory FeatureGrant.skillChoice({
    required String grantId,
    required int count,
    List<String>? pool,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.bonusSkillChoice,
        grantId: grantId,
        payload: {
          'count': count,
          if (pool != null) 'pool': pool,
        },
        label: label,
      );

  /// Expertise (double proficiency) on a specific skill.
  factory FeatureGrant.expertise(
    String skill, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.expertiseGrant,
        grantId: grantId,
        payload: {'skill': skill},
        label: label,
      );

  /// Proficiency in a specific tool.
  factory FeatureGrant.bonusTool(
    String tool, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.proficiency,
        grantId: grantId,
        payload: {
          'tool': tool,
          'proficiency': tool,
          'category': 'tool',
        },
        label: label ?? '$tool Proficiency',
      );

  /// Proficiency with weapon, armor, or tool category.
  factory FeatureGrant.weaponArmorProficiency(
    String proficiency, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.proficiency,
        grantId: grantId,
        payload: {'proficiency': proficiency},
        label: label,
      );

  /// Proficiency in an armor type or category (e.g. Light Armor, Medium Armor, Heavy Armor, Shields).
  factory FeatureGrant.armorProficiency(
    String armor, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.proficiency,
        grantId: grantId,
        payload: {'proficiency': armor, 'category': 'armor'},
        label: label ?? '$armor Proficiency',
      );

  /// Attack ability substitution (e.g. Mental for magic weapons, Presence for pact/hex weapons).
  factory FeatureGrant.attackAbilitySubstitution({
    required String grantId,
    required dynamic ability,
    bool requiresMagicWeapon = false,
    bool requiresMagic = false,
    String? condition,
    String? label,
  }) {
    final abilityName =
        ability is Enum ? ability.name : ability.toString();
    final isMagic = requiresMagicWeapon || requiresMagic;
    return FeatureGrant(
      type: GrantType.attackAbilitySubstitution,
      grantId: grantId,
      payload: {
        'ability': abilityName,
        if (isMagic) 'requiresMagic': true,
        if (isMagic) 'requiresMagicWeapon': true,
        if (condition != null) 'condition': condition,
      },
      label: label,
    );
  }

  /// Grants a boolean capability flag (e.g. 'mediumArmorDexCapBonus', 'initiativeBonusMode', 'passivePerceptionBonus').
  factory FeatureGrant.capabilityFlag(
    String flagKey, {
    String? grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.capabilityFlag,
        grantId: grantId ?? 'flag-$flagKey',
        payload: {'flagKey': flagKey},
        label: label,
      );

  /// Flat or capped modifier to Defense.
  factory FeatureGrant.defenseModifier({
    required String grantId,
    int? flatBonus,
    int? maxDexCap,
    bool requiresArmor = false,
    bool requiresMediumArmor = false,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.acFormula,
        grantId: grantId,
        payload: {
          'formula': 'armor_modifier',
          if (flatBonus != null) 'amount': flatBonus,
          if (maxDexCap != null) 'maxDexCap': maxDexCap,
          if (requiresArmor) 'requiresArmor': true,
          if (requiresMediumArmor) 'requiresMediumArmor': true,
        },
        label: label,
      );

  /// Bonus [count] cantrips (optionally specifying casting ability).
  factory FeatureGrant.bonusCantrips({
    required String grantId,
    required int count,
    String? castingAbility,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.bonusCantrip,
        grantId: grantId,
        payload: {
          'count': count,
          if (castingAbility != null) 'castingAbility': castingAbility,
        },
        label: label,
      );

  /// Bonus specific spell granted.
  factory FeatureGrant.bonusSpell({
    required String grantId,
    required String slug,
    required String displayName,
    bool isCantrip = false,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.bonusSpell,
        grantId: grantId,
        payload: {
          'slug': slug,
          'displayName': displayName,
          if (isCantrip) 'isCantrip': true,
        },
        label: label,
      );

  /// Exhaustively extracts clean spell names and cantrip flags from compendium additionalSpells / subclassSpells structures.
  static Map<String, bool> extractSpellDescriptors(dynamic addSpellsData) {
    if (spellDescriptorExtractor != null) {
      return spellDescriptorExtractor!(addSpellsData);
    }
    if (addSpellsData == null) return const {};
    final descriptors = <String, bool>{};

    void processSpellItem(dynamic item, {bool isCantripContext = false}) {
      if (item == null) return;
      if (item is String) {
        final isCantrip = isCantripContext || item.contains('#c');
        final clean = item.split('|').first.replaceAll('#c', '').trim();
        if (clean.isNotEmpty && !clean.startsWith('{')) {
          descriptors[clean] = (descriptors[clean] ?? false) || isCantrip;
        }
      } else if (item is List) {
        for (final subItem in item) {
          processSpellItem(subItem, isCantripContext: isCantripContext);
        }
      } else if (item is Map) {
        if (item.containsKey('choose')) {
          final ch = item['choose'];
          if (ch is Map && ch['from'] != null) {
            processSpellItem(ch['from'], isCantripContext: isCantripContext);
          } else if (ch is String && ch.isNotEmpty) {
            final isCantrip = isCantripContext || ch.contains('#c');
            final clean = ch.split('|').first.replaceAll('#c', '').trim();
            if (!clean.contains('=')) {
              descriptors[clean] = (descriptors[clean] ?? false) || isCantrip;
            }
          }
        }
        if (item.containsKey('from')) {
          processSpellItem(item['from'], isCantripContext: isCantripContext);
        }
        for (final entry in item.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k == 'choose' || k == 'count' || k == 'all' || k == 'from')
            continue;
          final isSubCantrip =
              isCantripContext || k == '_' || k == '0' || k == 's0';
          processSpellItem(entry.value, isCantripContext: isSubCantrip);
        }
      }
    }

    void processSpellGroup(dynamic group) {
      if (group == null) return;
      if (group is List) {
        for (final item in group) {
          processSpellGroup(item);
        }
      } else if (group is Map) {
        bool hadKnownSubkey = false;
        for (final key in [
          'prepared',
          'expanded',
          'innate',
          'known',
          'spells'
        ]) {
          if (group.containsKey(key)) {
            hadKnownSubkey = true;
            processSpellItem(group[key]);
          }
        }
        if (!hadKnownSubkey) {
          for (final entry in group.entries) {
            final k = entry.key.toString().toLowerCase();
            if (k == 'name' ||
                k == 'source' ||
                k == 'class' ||
                k == 'subclass' ||
                k == 'choose' ||
                k == 'count' ||
                k == 'all') {
              continue;
            }
            final isSubCantrip = k == '_' || k == '0' || k == 's0';
            processSpellItem(entry.value, isCantripContext: isSubCantrip);
          }
        }
      } else if (group is String) {
        processSpellItem(group);
      }
    }

    processSpellGroup(addSpellsData);
    return descriptors;
  }

  /// Exhaustively extracts clean spell names from compendium additionalSpells / subclassSpells structures.
  static Set<String> extractSpellNames(dynamic addSpellsData) {
    if (spellNameExtractor != null) {
      return spellNameExtractor!(addSpellsData);
    }
    return extractSpellDescriptors(addSpellsData).keys.toSet();
  }

  /// Exhaustively extracts [FeatureGrant.bonusSpell] grants from compendium additionalSpells data.
  static List<FeatureGrant> extractBonusSpells(
      dynamic addSpellsData, String ownerPrefix, String ownerSlug) {
    if (bonusSpellsExtractor != null) {
      return bonusSpellsExtractor!(addSpellsData, ownerPrefix, ownerSlug);
    }
    final descriptors = extractSpellDescriptors(addSpellsData);
    final grants = <FeatureGrant>[];
    final seenSlugs = <String>{};

    for (final entry in descriptors.entries) {
      final clean = entry.key;
      final isCantrip = entry.value;
      final slug = clean
          .toLowerCase()
          .replaceAll(RegExp(r"['’]"), '')
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (slug.isNotEmpty && seenSlugs.add(slug)) {
        grants.add(FeatureGrant.bonusSpell(
          grantId: '$ownerPrefix-$ownerSlug-spell-$slug',
          slug: slug,
          displayName: clean,
          isCantrip: isCantrip,
          label: clean,
        ));
      }
    }
    return grants;
  }

  /// Darkvision at [feet] range (stacks to max with existing darkvision).
  factory FeatureGrant.darkvisionRange(
    int feet, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.darkvision,
        grantId: grantId,
        payload: {'feet': feet},
        label: label ?? 'Darkvision ($feet ft.)',
      );

  /// +[amount] to a specific [ability] score (e.g., racial ASI).
  factory FeatureGrant.abilityBoost({
    required String grantId,
    required String ability,
    required int amount,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.abilityScoreBoost,
        grantId: grantId,
        payload: {'ability': ability, 'amount': amount},
        label: label,
      );

  /// Damage resistance to a specific damage type (e.g., fire).
  factory FeatureGrant.resistance(
    String damageType, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.resistanceGrant,
        grantId: grantId,
        payload: {'damageType': damageType},
        label: label ?? '$damageType resistance',
      );

  /// Speed modifier in feet (positive = bonus, negative = penalty).
  factory FeatureGrant.speedBonus(
    int amount, {
    required String grantId,
    String? label,
  }) =>
      FeatureGrant(
        type: GrantType.speedModifier,
        grantId: grantId,
        payload: {'amount': amount},
        label: label,
      );

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'grantId': grantId,
        'payload': payload,
        if (label != null) 'label': label,
      };

  factory FeatureGrant.fromMap(Map<String, dynamic> map) {
    final typeName = map['type']?.toString() ?? '';
    final type = GrantType.values.firstWhere(
      (g) => g.name == typeName,
      orElse: () => GrantType.passiveModifier,
    );
    final rawGrantId = map['grantId']?.toString();
    final grantId = (rawGrantId != null && rawGrantId.isNotEmpty)
        ? rawGrantId
        : 'grant_${type.name}_legacy';

    return FeatureGrant(
      type: type,
      grantId: grantId,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      label: map['label']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureGrant &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          grantId == other.grantId &&
          label == other.label;

  @override
  int get hashCode => type.hashCode ^ grantId.hashCode ^ (label?.hashCode ?? 0);

  @override
  String toString() =>
      'FeatureGrant(${type.name} ($grantId)${label != null ? ': $label' : ''})';
}

// ---------------------------------------------------------------------------
// Grant Evaluator — pure utility consumed by CharacterStatCalculator
// ---------------------------------------------------------------------------

/// Pure evaluation helper that reads a flat stream of [FeatureGrant]s and
/// produces numeric outputs for use in [CharacterStatCalculator].
class GrantEvaluator {
  const GrantEvaluator._();

  /// Computes the total flat HP bonus from all active grants.
  /// [totalLevel] is required to evaluate per-level grants.
  static int evaluateHpBonus(List<FeatureGrant> grants, int totalLevel) {
    int bonus = 0;
    for (final g in grants.where((g) => g.type == GrantType.hpModifier)) {
      bonus += (g.payload['flat'] as num?)?.toInt() ?? 0;
      bonus += ((g.payload['perLevel'] as num?)?.toInt() ?? 0) * totalLevel;
    }
    return bonus;
  }

  /// Computes the flat speed modifier from all active grants.
  static int evaluateSpeedBonus(List<FeatureGrant> grants) {
    int bonus = 0;
    for (final g in grants.where((g) => g.type == GrantType.speedModifier)) {
      bonus += (g.payload['amount'] as num?)?.toInt() ?? 0;
    }
    return bonus;
  }

  /// Returns the effective darkvision range (0 if none).
  static int evaluateDarkvisionFeet(List<FeatureGrant> grants) {
    int max = 0;
    for (final g in grants.where((g) => g.type == GrantType.darkvision)) {
      final ft = (g.payload['feet'] as num?)?.toInt() ?? 0;
      if (ft > max) max = ft;
    }
    return max;
  }

  /// Returns the total initiative bonus from passiveModifier grants.
  /// [profBonus] is needed if any grant uses 'profBonus' as the formula.
  static int evaluateInitiativeBonus(List<FeatureGrant> grants, int profBonus) {
    int bonus = 0;
    for (final g in grants.where((g) => g.type == GrantType.passiveModifier)) {
      if (g.payload['stat'] == 'initiative') {
        bonus += _evaluateFormula(
            g.payload['formula']?.toString(), g.payload['flat'], profBonus);
      }
    }
    return bonus;
  }

  /// Finds the first unarmored AC formula grant, or null.
  static FeatureGrant? findUnarmoredAcFormula(List<FeatureGrant> grants) {
    return grants
        .where(
          (g) =>
              g.type == GrantType.acFormula &&
              g.payload['requiresNoArmor'] == true &&
              g.payload['formula'] != 'flat_bonus',
        )
        .firstOrNull;
  }

  /// Computes the total flat AC bonus from acFormula grants
  /// (e.g., Defense Fighting Style: +1 AC while wearing armor).
  static int evaluateFlatAcBonus(
    List<FeatureGrant> grants, {
    required bool hasArmor,
  }) {
    int bonus = 0;
    for (final g in grants.where(
      (g) =>
          g.type == GrantType.acFormula && g.payload['formula'] == 'flat_bonus',
    )) {
      final requiresArmor = g.payload['requiresArmor'] == true;
      final requiresNoArmor = g.payload['requiresNoArmor'] == true;
      if (requiresArmor && !hasArmor) continue;
      if (requiresNoArmor && hasArmor) continue;
      bonus += (g.payload['amount'] as num?)?.toInt() ?? 0;
    }
    return bonus;
  }

  /// Returns all skill proficiencies explicitly granted (not choices).
  static Set<String> evaluateGrantedSkills(List<FeatureGrant> grants) {
    final skills = <String>{};
    for (final g in grants.where((g) => g.type == GrantType.bonusSkill)) {
      final skill = g.payload['skill']?.toString();
      if (skill != null && skill.isNotEmpty) skills.add(skill);
    }
    return skills;
  }

  /// Returns total count of bonus skill *choices* (not fixed skills).
  static int evaluateBonusSkillChoiceCount(List<FeatureGrant> grants) {
    int count = 0;
    for (final g in grants.where((g) => g.type == GrantType.bonusSkillChoice)) {
      count += (g.payload['count'] as num?)?.toInt() ?? 0;
    }
    return count;
  }

  /// Returns all expertise grants as string set.
  static Set<String> evaluateExpertiseGrants(List<FeatureGrant> grants) {
    final skills = <String>{};
    for (final g in grants.where((g) => g.type == GrantType.expertiseGrant)) {
      final skill = g.payload['skill']?.toString();
      if (skill != null && skill.isNotEmpty) skills.add(skill);
    }
    return skills;
  }

  /// Returns all resistance damage types.
  static Set<String> evaluateResistances(List<FeatureGrant> grants) {
    return grants
        .where((g) => g.type == GrantType.resistanceGrant)
        .map((g) => g.payload['damageType']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// Evaluates whether any active grant provides the specified capability flag.
  static bool hasCapability(List<FeatureGrant> grants, String flagKey) {
    final norm = flagKey.toLowerCase().replaceAll('-', '_');
    return grants.any((g) {
      if (g.type == GrantType.capabilityFlag) {
        final key =
            g.payload['flagKey']?.toString().toLowerCase().replaceAll('-', '_');
        return key == norm;
      }
      return false;
    });
  }

  /// Evaluates whether any active grant modifies the medium armor DEX bonus cap (e.g., to 3).
  static int? evaluateMediumArmorDexCap(List<FeatureGrant> grants) {
    for (final g in grants) {
      if (g.type == GrantType.acFormula &&
          g.payload['requiresMediumArmor'] == true) {
        final cap = (g.payload['maxDexCap'] as num?)?.toInt();
        if (cap != null) return cap;
      }
      if (g.type == GrantType.capabilityFlag) {
        final key =
            g.payload['flagKey']?.toString().toLowerCase().replaceAll('-', '_');
        if (key == 'mediumarmordexcapbonus' ||
            key == 'medium_armor_dex_cap_bonus') {
          return 3;
        }
      }
    }
    return null;
  }

  /// Returns valid attack ability substitution candidates for an item based on active grants.
  static List<String> evaluateAttackAbilitySubstitutions(
    List<FeatureGrant> grants, {
    required bool isMagicWeapon,
  }) {
    final validAbilities = <String>[];
    for (final g
        in grants.where((g) => g.type == GrantType.attackAbilitySubstitution)) {
      final requiresMagic = g.payload['requiresMagic'] == true ||
          g.payload['requiresMagicWeapon'] == true;
      if (requiresMagic && !isMagicWeapon) continue;
      final abilityStr = g.payload['ability']?.toString();
      if (abilityStr != null &&
          abilityStr.isNotEmpty &&
          !validAbilities.contains(abilityStr)) {
        validAbilities.add(abilityStr);
      }
    }
    return validAbilities;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static int _evaluateFormula(String? formula, dynamic flat, int profBonus) {
    if (flat is num) return flat.toInt();
    switch (formula) {
      case 'profBonus':
        return profBonus;
      case 'halfProfBonus':
        return (profBonus / 2).floor();
      default:
        return 0;
    }
  }
}
