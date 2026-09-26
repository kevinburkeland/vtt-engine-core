import '../../rules/ruleset_edition.dart';

/// Explicit ruleset baselines for remote homebrew repositories and packs.
enum RulesetVersion {
  v2014,
  v2024,
  homebrew;

  static const RulesetVersion srd2014 = RulesetVersion.v2014;
  static const RulesetVersion srd2024 = RulesetVersion.v2024;
  static const RulesetVersion dnd2014 = RulesetVersion.v2014;
  static const RulesetVersion dnd2024 = RulesetVersion.v2024;

  RulesetEdition toEdition() =>
      this == RulesetVersion.v2024 ? RulesetEdition.v2024 : RulesetEdition.v2014;

  static RulesetVersion fromEdition(RulesetEdition edition) =>
      edition == RulesetEdition.v2024
          ? RulesetVersion.v2024
          : RulesetVersion.v2014;

  static RulesetVersion fromString(String raw) {
    final clean = raw.trim().toLowerCase();
    if (clean.contains('2024') ||
        clean == 'srd5.2.1' ||
        clean == 'srd5.2' ||
        clean == 'srd2024' ||
        clean == 'srd521' ||
        clean == 'srd52' ||
        clean == '5e-2024' ||
        clean == 'v2024' ||
        clean.contains('5.2')) {
      return RulesetVersion.v2024;
    }
    return RulesetVersion.v2014;
  }
}
