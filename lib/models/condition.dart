/// Core Conditions & Combat Statuses affecting combat status, advantage, and aerial stability.
/// Pure Dart model decoupled from Flutter UI dependencies.
enum ArenaCondition {
  prone(
    'Prone',
    'PRN',
    'Disadvantage on attacks; melee attacks against within 5 ft have Advantage; costs half speed to stand.',
  ),
  stunned(
    'Stunned',
    'STN',
    'Incapacitated, can’t move, auto-fails STR/DEX saves, attacks against have Advantage.',
  ),
  paralyzed(
    'Paralyzed',
    'PAR',
    'Incapacitated, speed 0, auto-fails STR/DEX saves, attacks against have Advantage, hits within 5 ft are Crits.',
  ),
  restrained(
    'Restrained',
    'RST',
    'Speed 0, attacks against have Advantage, attacks have Disadvantage, DEX save Disadvantage.',
  ),
  grappled(
    'Grappled',
    'GRP',
    'Speed 0; condition ends if grappler is incapacitated or moved away.',
  ),
  unconscious(
    'Unconscious',
    'UNC',
    'Incapacitated, drops items, falls Prone, auto-fails STR/DEX saves, hits within 5 ft are Crits.',
  ),
  incapacitated(
    'Incapacitated',
    'INC',
    'Cannot take actions, bonus actions, or reactions; breaks active concentration.',
  ),
  blinded(
    'Blinded',
    'BLN',
    'Cannot see, auto-fails sight checks, attacks have Disadvantage, attacks against have Advantage.',
  ),
  charmed(
    'Charmed',
    'CHM',
    'Cannot attack or harm charmer; charmer has Advantage on social ability checks.',
  ),
  deafened(
    'Deafened',
    'DEF',
    'Cannot hear, automatically fails any ability check requiring hearing.',
  ),
  frightened(
    'Frightened',
    'FRG',
    'Disadvantage on ability checks and attack rolls while source visible; cannot willingly move closer.',
  ),
  poisoned(
    'Poisoned',
    'POI',
    'Disadvantage on attack rolls and ability checks.',
  ),
  invisible(
    'Invisible',
    'INV',
    'Concealed from sight; attack rolls have Advantage; incoming attacks have Disadvantage.',
  ),
  petrified(
    'Petrified',
    'PET',
    'Incapacitated, weight ×10, unaware, resistance to all damage, poison immunity.',
  ),
  exhaustion(
    'Exhaustion',
    'EXH',
    'Penalties to D20 tests and movement speed.',
  ),
  concentration(
    'Concentration',
    'CNC',
    'Maintaining concentration on an active spell; ends if Incapacitated or fails CON save upon taking damage.',
  ),
  burning(
    'Burning',
    'BRN',
    'Suffers periodic fire damage at start/end of turn until extinguished.',
  ),
  bleeding(
    'Bleeding',
    'BLD',
    'Suffers ongoing bleeding damage upon taking actions or ending turn.',
  );

  final String label;
  final String shortCode;
  final String penaltySummary;

  const ArenaCondition(
    this.label,
    this.shortCode,
    this.penaltySummary,
  );

  /// Helper to get a condition by id or name insensitive.
  static ArenaCondition? fromName(String name) {
    final lower = name.trim().toLowerCase();
    for (final c in ArenaCondition.values) {
      if (c.name.toLowerCase() == lower ||
          c.label.toLowerCase() == lower ||
          c.shortCode.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }
}

/// Agnostic type alias for ruleset-neutral condition modeling.
typedef Condition = ArenaCondition;

/// Represents an active instance of a status condition applied to a combatant token.
class ActiveCondition {
  final ArenaCondition condition;
  final int? durationRounds;
  final String? source;
  final String? customNote;

  const ActiveCondition({
    required this.condition,
    this.durationRounds,
    this.source,
    this.customNote,
  });

  String get id => condition.name;
  String get name => condition.label;
  String get shortCode => condition.shortCode;
  String get penaltySummary => condition.penaltySummary;
  bool get hasFiniteDuration => durationRounds != null;
  bool get isExpired => durationRounds != null && durationRounds! <= 0;

  String get durationDisplay {
    if (durationRounds == null) return 'Until End of Combat / Saved';
    if (durationRounds == 1) return '1 round remaining';
    return '$durationRounds rounds remaining';
  }

  String get durationBadge {
    if (durationRounds == null) return '∞';
    return '${durationRounds}r';
  }

  /// Decrements remaining duration by 1 round (turn tick).
  ActiveCondition tickTurn() {
    if (durationRounds == null) return this;
    return ActiveCondition(
      condition: condition,
      durationRounds: durationRounds! - 1,
      source: source,
      customNote: customNote,
    );
  }

  ActiveCondition copyWith({
    ArenaCondition? condition,
    int? durationRounds,
    String? source,
    String? customNote,
  }) {
    return ActiveCondition(
      condition: condition ?? this.condition,
      durationRounds: durationRounds ?? this.durationRounds,
      source: source ?? this.source,
      customNote: customNote ?? this.customNote,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveCondition &&
          runtimeType == other.runtimeType &&
          condition == other.condition &&
          durationRounds == other.durationRounds &&
          source == other.source;

  @override
  int get hashCode =>
      condition.hashCode ^ durationRounds.hashCode ^ (source?.hashCode ?? 0);
}
