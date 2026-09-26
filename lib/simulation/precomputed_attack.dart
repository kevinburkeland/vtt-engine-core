import 'dart:math';
import 'combat_rider.dart';
export 'combat_rider.dart';

class DamageDieGroup {
  final int count;
  final int faces;

  const DamageDieGroup({
    required this.count,
    required this.faces,
  });

  int roll(Random rng, {bool isCrit = false}) {
    final totalDice = isCrit ? count * 2 : count;
    var total = 0;
    for (var i = 0; i < totalDice; i++) {
      total += rng.nextInt(faces) + 1;
    }
    return total;
  }
}

class PrecomputedAttack {
  final String attackId;
  final int attackBonus;
  final int flatBonus;
  final List<DamageDieGroup> damageGroups;
  final List<CombatEffectRider> riders;

  const PrecomputedAttack({
    required this.attackId,
    required this.attackBonus,
    required this.flatBonus,
    required this.damageGroups,
    this.riders = const [],
  }) : assert(
          identical(riders, const <CombatEffectRider>[]) ||
              identical(riders, const []) ||
              riders.length <= 8,
          'riders.length must be <= 8 to prevent heap overhead',
        );

  int rollDamage(Random rng, {bool isCrit = false}) {
    var sum = flatBonus;
    for (final group in damageGroups) {
      sum += group.roll(rng, isCrit: isCrit);
    }
    return sum;
  }
}

class PrecomputedAttackMap {
  final Map<String, PrecomputedAttack> _attacks;

  PrecomputedAttackMap([Map<String, PrecomputedAttack>? initialAttacks])
      : _attacks = initialAttacks != null
            ? Map<String, PrecomputedAttack>.from(initialAttacks)
            : <String, PrecomputedAttack>{};

  PrecomputedAttack? operator [](String attackId) => _attacks[attackId];

  void register(PrecomputedAttack attack) {
    _attacks[attack.attackId] = attack;
  }

  void remove(String attackId) {
    _attacks.remove(attackId);
  }

  bool contains(String attackId) => _attacks.containsKey(attackId);

  int get length => _attacks.length;

  Iterable<PrecomputedAttack> get all => _attacks.values;

  Map<String, PrecomputedAttack> toMap() => Map.unmodifiable(_attacks);
}
