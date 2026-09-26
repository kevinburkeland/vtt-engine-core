import '../rules/ruleset_edition.dart';
import 'core_types.dart';
import 'character_models.dart';
import 'entity_reference.dart';
import 'feature_grant.dart';
import 'spell_monster_equipment.dart';
import 'party_purse.dart';

/// Mutable working-memory draft model for character creation.
///
/// Accepts nullable inputs and arbitrary out-of-order assignments
/// (supporting dynamic wizard ordering presets). Validates completely before
/// compiling into an immutable [Character] domain entity.
class CharacterDraft {
  String? characterName;
  RulesetEdition _rulesEdition;
  RulesetEdition get rulesEdition => _rulesEdition;
  set rulesEdition(RulesetEdition edition) {
    _rulesEdition = edition;
    reconcile();
  }

  EntityReference<DomainEntity>? speciesRef;
  EntityReference<DomainEntity>? subraceRef;
  EntityReference<DomainEntity>? backgroundRef;
  EntityReference<DomainEntity>? startingClassRef;
  String? startingClassHitDie;
  AbilityScores? baseScores;
  Map<SkillType, SkillProficiencyLevel> selectedSkills;

  // Extended compilation properties
  AbilityScores backgroundBonusScores;
  AbilityScores speciesBonusScores;
  AbilityScores bonusScores;
  Set<AbilityType> savingThrowProficiencies;
  List<String> toolProficiencies;
  List<String> languages;
  List<StartingEquipmentItemRequest> startingEquipment;
  PartyPurse startingPurse;
  bool takesStartingWealth;
  List<EntityReference<Spell>> cantrips;
  List<EntityReference<Spell>> spellsKnown;
  List<EntityReference<Spell>> spellsPrepared;
  List<EntityReference<DomainEntity>> originFeats;
  EntityReference<DomainEntity>? startingSubclassRef;
  Map<String, List<String>> selectedFeatureOptions;
  int baseSpeedFeet;
  List<AbilityType> pendingFlexibleAbilityChoices;

  CharacterDraft({
    this.characterName,
    RulesetEdition rulesEdition = RulesetEdition.v2024,
    this.speciesRef,
    this.subraceRef,
    this.backgroundRef,
    this.startingClassRef,
    this.startingClassHitDie,
    this.baseScores,
    Map<SkillType, SkillProficiencyLevel>? selectedSkills,
    this.backgroundBonusScores = const AbilityScores.zero(),
    this.speciesBonusScores = const AbilityScores.zero(),
    this.bonusScores = const AbilityScores.zero(),
    Set<AbilityType>? savingThrowProficiencies,
    List<String>? toolProficiencies,
    List<String>? languages,
    List<StartingEquipmentItemRequest>? startingEquipment,
    this.startingPurse = const PartyPurse(),
    this.takesStartingWealth = false,
    List<EntityReference<Spell>>? cantrips,
    List<EntityReference<Spell>>? spellsKnown,
    List<EntityReference<Spell>>? spellsPrepared,
    List<EntityReference<DomainEntity>>? originFeats,
    this.startingSubclassRef,
    Map<String, List<String>>? selectedFeatureOptions,
    this.baseSpeedFeet = 30,
    List<AbilityType>? pendingFlexibleAbilityChoices,
  })  : _rulesEdition = rulesEdition,
        selectedSkills = selectedSkills != null ? Map.from(selectedSkills) : {},
        savingThrowProficiencies = savingThrowProficiencies != null
            ? Set.from(savingThrowProficiencies)
            : {},
        toolProficiencies =
            toolProficiencies != null ? List.from(toolProficiencies) : [],
        languages = languages != null ? List.from(languages) : ['Common'],
        startingEquipment =
            startingEquipment != null ? List.from(startingEquipment) : [],
        cantrips = cantrips != null ? List.from(cantrips) : [],
        spellsKnown = spellsKnown != null ? List.from(spellsKnown) : [],
        spellsPrepared =
            spellsPrepared != null ? List.from(spellsPrepared) : [],
        originFeats = originFeats != null ? List.from(originFeats) : [],
        selectedFeatureOptions = selectedFeatureOptions != null
            ? Map.from(selectedFeatureOptions)
            : {},
        pendingFlexibleAbilityChoices = pendingFlexibleAbilityChoices != null
            ? List.from(pendingFlexibleAbilityChoices)
            : [] {
    reconcile();
  }

  static AbilityScores _parseAbilityScores(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return const AbilityScores.zero();
    var str = 0, dex = 0, con = 0, intl = 0, wis = 0, cha = 0;
    for (final entry in raw.entries) {
      final key = entry.key.toString().toLowerCase().trim();
      final prefix = key.length > 3 ? key.substring(0, 3) : key;
      final val = (entry.value as num?)?.toInt() ?? 0;
      for (final ab in AbilityType.values) {
        if (ab.name.toLowerCase().startsWith(prefix)) {
          switch (ab) {
            case AbilityType.strength:
              str += val;
            case AbilityType.dexterity:
              dex += val;
            case AbilityType.constitution:
              con += val;
            case AbilityType.intelligence:
              intl += val;
            case AbilityType.wisdom:
              wis += val;
            case AbilityType.charisma:
              cha += val;
          }
          break;
        }
      }
    }
    return AbilityScores(
      strength: str,
      dexterity: dex,
      constitution: con,
      intelligence: intl,
      wisdom: wis,
      charisma: cha,
    );
  }

  /// Reconciles ruleset-dependent invariants in-place.
  void reconcile() {
    if (_rulesEdition == RulesetEdition.v2014) {
      if (originFeats.isNotEmpty) {
        originFeats.clear();
      }
      backgroundBonusScores = const AbilityScores.zero();

      // Ensure flexible ability choices honor pool in 2014 mode without defaulting to Strength
      final activePool = (subraceRef?.customProperties['flexibleAbilityPool'] ??
          speciesRef?.customProperties['flexibleAbilityPool']) as List?;
      if (activePool != null && activePool.isNotEmpty) {
        final allowed = <AbilityType>[];
        for (final item in activePool) {
          final str = item.toString().toLowerCase().trim();
          final prefix = str.length > 3 ? str.substring(0, 3) : str;
          for (final ab in AbilityType.values) {
            if (ab.name.toLowerCase().startsWith(prefix)) {
              if (!allowed.contains(ab)) allowed.add(ab);
            }
          }
        }
        if (allowed.isNotEmpty) {
          pendingFlexibleAbilityChoices.retainWhere(allowed.contains);
          if (pendingFlexibleAbilityChoices.isEmpty) {
            pendingFlexibleAbilityChoices.add(allowed.first);
          }
        }
      }

      final flexBonus =
          (subraceRef?.customProperties['flexibleAbilityBonus'] as num?)
                  ?.toInt() ??
              (speciesRef?.customProperties['flexibleAbilityBonus'] as num?)
                  ?.toInt() ??
              1;
      var flexScores = const AbilityScores.zero();
      for (final choice in pendingFlexibleAbilityChoices) {
        switch (choice) {
          case AbilityType.strength:
            flexScores =
                flexScores.copyWith(strength: flexScores.strength + flexBonus);
          case AbilityType.dexterity:
            flexScores = flexScores.copyWith(
                dexterity: flexScores.dexterity + flexBonus);
          case AbilityType.constitution:
            flexScores = flexScores.copyWith(
                constitution: flexScores.constitution + flexBonus);
          case AbilityType.intelligence:
            flexScores = flexScores.copyWith(
                intelligence: flexScores.intelligence + flexBonus);
          case AbilityType.wisdom:
            flexScores =
                flexScores.copyWith(wisdom: flexScores.wisdom + flexBonus);
          case AbilityType.charisma:
            flexScores =
                flexScores.copyWith(charisma: flexScores.charisma + flexBonus);
        }
      }

      final baseSpeciesFixed = _parseAbilityScores(
        speciesRef?.customProperties['fixedAbilityBonuses'] ??
            speciesRef?.customProperties['abilityBonuses2014'],
      );

      if (subraceRef != null) {
        final subraceFixed = _parseAbilityScores(
          subraceRef!.customProperties['fixedAbilityBonuses'],
        );
        speciesBonusScores = baseSpeciesFixed + subraceFixed + flexScores;
      } else if (speciesRef != null) {
        speciesBonusScores = baseSpeciesFixed + flexScores;
      }

      bonusScores = speciesBonusScores;
    } else {
      speciesBonusScores = const AbilityScores.zero();
      pendingFlexibleAbilityChoices.clear();
      if (backgroundBonusScores != const AbilityScores.zero()) {
        bonusScores = backgroundBonusScores;
      }
    }

    // Seed class tool proficiencies
    final clSlug = startingClassRef?.slug.toLowerCase().trim();
    if (clSlug == 'rogue') {
      if (!toolProficiencies.any((t) => t.toLowerCase().contains('thieves'))) {
        toolProficiencies.add('Thieves\' Tools');
      }
    } else if (clSlug == 'druid') {
      if (!toolProficiencies
          .any((t) => t.toLowerCase().contains('herbalism'))) {
        toolProficiencies.add('Herbalism Kit');
      }
    }

    final classProps = startingClassRef?.customProperties;
    if (classProps != null) {
      final dynamicTools = classProps['tools'] ??
          classProps['startingTools'] ??
          (classProps['startingProficiencies'] is Map
              ? classProps['startingProficiencies']['tools']
              : null);
      if (dynamicTools is List) {
        for (final t in dynamicTools) {
          final tStr = t.toString().trim();
          if (tStr.isNotEmpty &&
              !toolProficiencies
                  .any((x) => x.toLowerCase() == tStr.toLowerCase())) {
            toolProficiencies.add(tStr);
          }
        }
      }
    }

    // Auto-seed species & subrace bonus spells from additionalSpells metadata if present
    final subAddSpells = subraceRef?.customProperties['additionalSpells'] ??
        speciesRef?.customProperties['additionalSpells'];
    if (subAddSpells != null) {
      final descriptors = FeatureGrant.extractSpellDescriptors(subAddSpells);
      for (final entry in descriptors.entries) {
        final clean = entry.key;
        final isCantrip = entry.value;
        final slug = clean
            .toLowerCase()
            .replaceAll(RegExp(r"['’]"), '')
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        if (slug.isNotEmpty) {
          final spellRef = EntityReference<Spell>(
            refType: EntityType.spell,
            slug: slug,
            displayName: clean,
          );
          if (isCantrip) {
            if (!cantrips.any((c) => c.slug == slug)) {
              cantrips.add(spellRef);
            }
          } else {
            if (!spellsKnown.any((s) => s.slug == slug)) {
              spellsKnown.add(spellRef);
            }
          }
        }
      }
    }
  }

  CharacterDraft copyWith({
    String? characterName,
    RulesetEdition? rulesEdition,
    EntityReference<DomainEntity>? speciesRef,
    EntityReference<DomainEntity>? subraceRef,
    EntityReference<DomainEntity>? backgroundRef,
    EntityReference<DomainEntity>? startingClassRef,
    String? startingClassHitDie,
    AbilityScores? baseScores,
    Map<SkillType, SkillProficiencyLevel>? selectedSkills,
    AbilityScores? backgroundBonusScores,
    AbilityScores? speciesBonusScores,
    AbilityScores? bonusScores,
    Set<AbilityType>? savingThrowProficiencies,
    List<String>? toolProficiencies,
    List<String>? languages,
    List<StartingEquipmentItemRequest>? startingEquipment,
    PartyPurse? startingPurse,
    bool? takesStartingWealth,
    List<EntityReference<Spell>>? cantrips,
    List<EntityReference<Spell>>? spellsKnown,
    List<EntityReference<Spell>>? spellsPrepared,
    List<EntityReference<DomainEntity>>? originFeats,
    EntityReference<DomainEntity>? startingSubclassRef,
    Map<String, List<String>>? selectedFeatureOptions,
    int? baseSpeedFeet,
    List<AbilityType>? pendingFlexibleAbilityChoices,
  }) {
    return CharacterDraft(
      characterName: characterName ?? this.characterName,
      rulesEdition: rulesEdition ?? this.rulesEdition,
      speciesRef: speciesRef ?? this.speciesRef,
      subraceRef: subraceRef ?? this.subraceRef,
      backgroundRef: backgroundRef ?? this.backgroundRef,
      startingClassRef: startingClassRef ?? this.startingClassRef,
      startingClassHitDie: startingClassHitDie ?? this.startingClassHitDie,
      baseScores: baseScores ?? this.baseScores,
      selectedSkills: selectedSkills ?? this.selectedSkills,
      backgroundBonusScores:
          backgroundBonusScores ?? this.backgroundBonusScores,
      speciesBonusScores: speciesBonusScores ?? this.speciesBonusScores,
      bonusScores: bonusScores ?? this.bonusScores,
      savingThrowProficiencies:
          savingThrowProficiencies ?? this.savingThrowProficiencies,
      toolProficiencies: toolProficiencies ?? this.toolProficiencies,
      languages: languages ?? this.languages,
      startingEquipment: startingEquipment ?? this.startingEquipment,
      startingPurse: startingPurse ?? this.startingPurse,
      takesStartingWealth: takesStartingWealth ?? this.takesStartingWealth,
      cantrips: cantrips ?? this.cantrips,
      spellsKnown: spellsKnown ?? this.spellsKnown,
      spellsPrepared: spellsPrepared ?? this.spellsPrepared,
      originFeats: originFeats ?? this.originFeats,
      startingSubclassRef: startingSubclassRef ?? this.startingSubclassRef,
      selectedFeatureOptions:
          selectedFeatureOptions ?? this.selectedFeatureOptions,
      baseSpeedFeet: baseSpeedFeet ?? this.baseSpeedFeet,
      pendingFlexibleAbilityChoices:
          pendingFlexibleAbilityChoices ?? this.pendingFlexibleAbilityChoices,
    );
  }

  // --- Granular Validation Getters ---
  bool get hasValidSpecies => speciesRef != null;
  bool get hasValidClass => startingClassRef != null;
  bool get hasValidBackground => backgroundRef != null;
  bool get hasValidScores => baseScores != null;

  // --- Master Validation Getter ---
  bool get isReadyForCompilation =>
      hasValidSpecies &&
      hasValidClass &&
      hasValidBackground &&
      hasValidScores &&
      characterName != null &&
      characterName!.trim().isNotEmpty;
}
