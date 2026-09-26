import '../rules/ruleset_context.dart';

class ExhaustionState {
  final int level;
  final RulesetVersion ruleset;
  final int baseSpeed;

  const ExhaustionState({
    required this.level,
    this.ruleset = RulesetVersion.v2024,
    this.baseSpeed = 30,
  });

  int get clampedLevel => level.clamp(0, 6);

  bool get isDead => clampedLevel >= 6;

  int get d20Penalty {
    final engine = RulesetEngine.forVersion(ruleset);
    return engine.calculateExhaustionD20Penalty(clampedLevel);
  }

  int speedReduction([int? entityBaseSpeed]) {
    final speed = entityBaseSpeed ?? baseSpeed;
    final engine = RulesetEngine.forVersion(ruleset);
    return engine.calculateExhaustionSpeedPenalty(clampedLevel, speed);
  }

  List<String> get activeEffectsDescription {
    final lvl = clampedLevel;
    if (lvl == 0) return const [];

    if (ruleset == RulesetVersion.v2024) {
      if (lvl >= 6) {
        return [
          'Death',
          'D20 Test Penalty: -12',
          'Speed Reduction: -30 ft',
        ];
      }
      return [
        'D20 Test Penalty: -$d20Penalty (applies to d20 rolls: attack rolls, ability checks, saving throws)',
        'Speed Reduction: -${speedReduction()} ft',
      ];
    } else {
      // 2014 SRD 5.1 cumulative effects
      final effects = <String>[];
      if (lvl >= 1) effects.add('Disadvantage on ability checks');
      if (lvl >= 2) effects.add('Speed halved');
      if (lvl >= 3)
        effects.add('Disadvantage on attack rolls and saving throws');
      if (lvl >= 4) effects.add('Hit point maximum halved');
      if (lvl >= 5) effects.add('Speed reduced to 0');
      if (lvl >= 6) effects.add('Death');
      return effects;
    }
  }

  ExhaustionState copyWith(
      {int? level, RulesetVersion? ruleset, int? baseSpeed}) {
    return ExhaustionState(
      level: level ?? this.level,
      ruleset: ruleset ?? this.ruleset,
      baseSpeed: baseSpeed ?? this.baseSpeed,
    );
  }

  ExhaustionState increment() => copyWith(level: (level + 1).clamp(0, 6));

  ExhaustionState decrement() => copyWith(level: (level - 1).clamp(0, 6));

  ExhaustionState reset() => copyWith(level: 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExhaustionState &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          ruleset == other.ruleset &&
          baseSpeed == other.baseSpeed;

  @override
  int get hashCode => Object.hash(level, ruleset, baseSpeed);
}
