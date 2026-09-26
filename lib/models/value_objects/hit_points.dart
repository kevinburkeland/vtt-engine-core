import 'dart:math' as math;
import 'package:meta/meta.dart';

/// Immutable Value Object encapsulating Hit Points, Temporary Hit Points,
/// damage absorption (5e RAW), and healing bounded by maximum HP.
@immutable
class HitPoints {
  final int currentHp;
  final int maxHp;
  final int tempHp;
  final bool isDead;

  const HitPoints({
    required int currentHp,
    required int maxHp,
    int tempHp = 0,
    this.isDead = false,
  })  : maxHp = maxHp < 1 ? 1 : maxHp,
        currentHp = currentHp < 0
            ? 0
            : (currentHp > (maxHp < 1 ? 1 : maxHp)
                ? (maxHp < 1 ? 1 : maxHp)
                : currentHp),
        tempHp = tempHp < 0 ? 0 : tempHp;

  /// Convenience factory creating full-health hit points.
  factory HitPoints.full(int maxHp, {int tempHp = 0}) {
    final validMax = maxHp < 1 ? 1 : maxHp;
    return HitPoints(
      currentHp: validMax,
      maxHp: validMax,
      tempHp: tempHp,
      isDead: false,
    );
  }

  /// Whether current HP has reached 0 (unconscious/downed or dying).
  bool get isDowned => currentHp <= 0;

  /// Safe calculation of remaining HP percentage [0.0, 1.0].
  double get hpPercent => maxHp > 0 ? (currentHp / maxHp).clamp(0.0, 1.0) : 0.0;

  /// Applies damage bounded by [maxHp] and 0.
  /// Pure math operation that clamps current HP. Ruleset-specific vitals resolution
  /// (e.g. 5e Temporary HP absorption, Massive Damage instant death) is resolved
  /// via [ICombatResolver.resolveVitalsChange].
  HitPoints takeDamage(int amount) {
    if (amount <= 0) return this;
    final newCurrent = (currentHp - amount).clamp(0, maxHp);
    return HitPoints(
      currentHp: newCurrent,
      maxHp: maxHp,
      tempHp: tempHp,
      isDead: isDead,
    );
  }

  /// Applies healing bounded by [maxHp]. Does not affect temporary hit points.
  /// Under 5e RAW:
  /// - A downed creature at 0 HP (unconscious/dying, but not permanently dead)
  ///   regains hit points and wakes up from standard healing.
  /// - A creature that has suffered permanent death ([isDead] == true) cannot be
  ///   healed unless explicit revival semantics are specified via [allowRevive].
  HitPoints heal(int amount, {bool allowRevive = false}) {
    if (amount <= 0) return this;
    if (isDead && !allowRevive) return this;
    final newCurrent = (currentHp + amount).clamp(0, maxHp);
    return HitPoints(
      currentHp: newCurrent,
      maxHp: maxHp,
      tempHp: tempHp,
      isDead: allowRevive ? false : isDead,
    );
  }

  /// Explicit revival method to restore a permanently dead actor to positive HP.
  HitPoints revive(int amount) =>
      heal(amount, allowRevive: true).copyWith(isDead: false);

  /// Grants Temporary Hit Points (5e RAW: non-stacking; overrides if higher, or if [forceOverride]).
  HitPoints grantTempHp(int amount, {bool forceOverride = false}) {
    if (amount <= 0 && !forceOverride) return this;
    final newTemp = forceOverride
        ? math.max(0, amount)
        : math.max(tempHp, math.max(0, amount));
    return HitPoints(
      currentHp: currentHp,
      maxHp: maxHp,
      tempHp: newTemp,
      isDead: isDead,
    );
  }

  /// Overrides Temporary Hit Points explicitly.
  HitPoints setTempHp(int amount) => grantTempHp(amount, forceOverride: true);

  HitPoints copyWith({
    int? currentHp,
    int? maxHp,
    int? tempHp,
    bool? isDead,
  }) {
    return HitPoints(
      currentHp: currentHp ?? this.currentHp,
      maxHp: maxHp ?? this.maxHp,
      tempHp: tempHp ?? this.tempHp,
      isDead: isDead ?? this.isDead,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HitPoints &&
          runtimeType == other.runtimeType &&
          currentHp == other.currentHp &&
          maxHp == other.maxHp &&
          tempHp == other.tempHp &&
          isDead == other.isDead;

  @override
  int get hashCode => Object.hash(currentHp, maxHp, tempHp, isDead);

  @override
  String toString() =>
      'HitPoints($currentHp/$maxHp + $tempHp temp${isDead ? ', DEAD' : ''})';
}
