import '../models/character_models.dart';
import '../models/generic_tabletop_primitives.dart';
import 'ruleset_edition.dart';
import '../models/character_draft.dart';

enum ValidationSeverity { warning, error }

class ValidationIssue {
  final String code;
  final String message;
  final ValidationSeverity severity;

  const ValidationIssue({
    required this.code,
    required this.message,
    this.severity = ValidationSeverity.error,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationIssue &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          severity == other.severity;

  @override
  int get hashCode => code.hashCode ^ message.hashCode ^ severity.hashCode;

  @override
  String toString() => 'ValidationIssue($code: $message [$severity])';
}

class CharacterValidationEngine {
  const CharacterValidationEngine._();

  /// Calculates overlapping proficiencies between Background, Species, and Class.
  /// Returns an exact integer count of refunded wildcard skills to drive the UI state.
  /// Under 5e RAW, class skill choice pools do not grant skill refunds upon
  /// overlapping with background/species proficiencies because players select
  /// alternative skills from the choice pool. Only fixed auto-granted proficiencies collide.
  static int calculateSkillRefunds(CharacterDraft draft) {
    final Set<dynamic> grantedPool = {};
    int collisions = 0;

    void applySkills(Iterable<dynamic> incoming) {
      for (final skill in incoming) {
        if (grantedPool.contains(skill)) {
          collisions++;
        } else {
          grantedPool.add(skill);
        }
      }
    }

    applySkills(draft.backgroundRef?.grantedSkills ?? []);
    applySkills(draft.speciesRef?.grantedSkills ?? []);

    // Only fixed auto-granted class proficiencies collide with species/background choices.
    // Choice pools allow selecting alternative skills without granting improper skill refunds.
    final classRef = draft.startingClassRef;
    if (classRef != null) {
      final isFixedClassSkill = classRef.customProperties['isFixed'] == true;
      if (isFixedClassSkill) {
        applySkills(classRef.grantedSkills);
      }
    }

    return collisions;
  }

  /// ASI Bifurcation Guard
  static CharacterDraft reconcileAsiBifurcation(CharacterDraft draft) {
    var updated = draft;
    if (updated.rulesEdition == RulesetEdition.v2014) {
      // 2014: Strip background ASIs
      updated =
          updated.copyWith(backgroundBonusScores: const AbilityScores.zero());
    } else {
      // 2024: Strip species ASIs
      updated =
          updated.copyWith(speciesBonusScores: const AbilityScores.zero());
    }
    return updated;
  }

  /// Reconciles draft invariants across ruleset shifts and prerequisite changes.
  static CharacterDraft reconcileDraft(CharacterDraft draft) {
    draft.reconcile();
    var updated = draft;

    // Rule 1: Strip Origin Feats in 2014 mode
    if (updated.rulesEdition == RulesetEdition.v2014 &&
        updated.originFeats.isNotEmpty) {
      updated = updated.copyWith(originFeats: const []);
    }

    // Rule 2: Enforce ASI source bifurcation
    updated = reconcileAsiBifurcation(updated);
    if (updated.rulesEdition == RulesetEdition.v2014) {
      // In 2014, bonuses come from Species/Race, not Background
      updated = updated.copyWith(bonusScores: updated.speciesBonusScores);
    }

    return updated;
  }

  static final RegExp _numberPattern = RegExp(r'\b(\d{1,2})\b');

  /// Evaluates prerequisites for an arbitrary trait against character ability scores dynamically.
  static List<ValidationIssue> evaluateTraitPrerequisites({
    required ITraitDefinition trait,
    required AbilityScores totalScores,
  }) {
    final issues = <ValidationIssue>[];

    // 1. Structured prerequisite scores map check
    final prereqScores = trait.properties['prerequisiteScores'];
    if (prereqScores is Map) {
      final mode =
          trait.properties['prerequisiteMode']?.toString().toLowerCase() ??
              'and';
      final scoresMap = {
        'strength': totalScores.strength,
        'dexterity': totalScores.dexterity,
        'constitution': totalScores.constitution,
        'intelligence': totalScores.intelligence,
        'wisdom': totalScores.wisdom,
        'charisma': totalScores.charisma,
      };

      var met = mode == 'or' ? false : true;
      for (final entry in prereqScores.entries) {
        final attr = entry.key.toString().toLowerCase();
        final requiredVal = entry.value is num
            ? (entry.value as num).toInt()
            : int.tryParse(entry.value.toString()) ?? 0;
        final currentVal = scoresMap[attr] ?? 0;
        final satisfies = currentVal >= requiredVal;

        if (mode == 'or') {
          if (satisfies) {
            met = true;
            break;
          }
        } else {
          if (!satisfies) {
            met = false;
            break;
          }
        }
      }

      if (!met) {
        issues.add(ValidationIssue(
          code: 'feat_prereq_unmet',
          message: '${trait.name} prerequisites not met.',
        ));
        return issues;
      }
    }

    // 2. Dynamic string prerequisite parsing (e.g. "Strength or Dexterity 13+", "Charisma 13 or higher")
    final prereqStr = trait.properties['prerequisite']?.toString();
    if (prereqStr != null && prereqStr.isNotEmpty) {
      final scoresMap = {
        'strength': totalScores.strength,
        'dexterity': totalScores.dexterity,
        'constitution': totalScores.constitution,
        'intelligence': totalScores.intelligence,
        'wisdom': totalScores.wisdom,
        'charisma': totalScores.charisma,
      };

      final lower = prereqStr.toLowerCase();
      final isOr = lower.contains(' or ');

      final mentionedAbilities = <String>[];
      for (final attr in scoresMap.keys) {
        if (lower.contains(attr)) {
          mentionedAbilities.add(attr);
        }
      }

      if (mentionedAbilities.isNotEmpty) {
        final numMatch = _numberPattern.firstMatch(prereqStr);
        if (numMatch != null) {
          final targetScore = int.parse(numMatch.group(1)!);
          final satisfiesAny = mentionedAbilities
              .any((attr) => (scoresMap[attr] ?? 0) >= targetScore);
          final satisfiesAll = mentionedAbilities
              .every((attr) => (scoresMap[attr] ?? 0) >= targetScore);

          final meetsRequirement = isOr ? satisfiesAny : satisfiesAll;
          if (!meetsRequirement) {
            issues.add(ValidationIssue(
              code: 'feat_prereq_unmet',
              message: '${trait.name} requires $prereqStr.',
            ));
          }
        }
      }
    }

    return issues;
  }

  /// Evaluates prerequisites for feats, multiclassing, and illegal score thresholds.
  static List<ValidationIssue> validateDraft(CharacterDraft draft) {
    final issues = <ValidationIssue>[];

    if (!draft.hasValidScores) return issues;
    final totalScores = draft.baseScores! + draft.bonusScores;

    // Dynamic Feat Prerequisites Check
    for (final featRef in draft.originFeats) {
      final trait = featRef.toTraitDefinition();
      issues.addAll(
          evaluateTraitPrerequisites(trait: trait, totalScores: totalScores));
    }

    return issues;
  }
}
