/// Canonical ruleset version baselines for remote homebrew repositories and packs.
enum RulesetVersion {
  v2014,
  v2024,
  homebrew;

  /// String parser handling compendium and schema identifiers.
  static RulesetVersion fromString(String raw) {
    final clean = raw.trim().toLowerCase();
    if (clean.contains('2024') || clean.contains('v2')) {
      return RulesetVersion.v2024;
    }
    if (clean.contains('homebrew') || clean.contains('custom')) {
      return RulesetVersion.homebrew;
    }
    return RulesetVersion.v2014;
  }
}
