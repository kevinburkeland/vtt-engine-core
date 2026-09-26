import 'package:test/test.dart';
import 'package:vtt_engine_core/models/value_objects/hit_points.dart';

void main() {
  group('HitPoints Value Object Tests', () {
    test('initializes with bounds clamping', () {
      const hp = HitPoints(currentHp: 15, maxHp: 10, tempHp: -5);
      expect(hp.maxHp, equals(10));
      expect(hp.currentHp, equals(10)); // clamped to maxHp
      expect(hp.tempHp, equals(0)); // clamped to >= 0
      expect(hp.isDead, isFalse);
      expect(hp.hpPercent, equals(1.0));
    });

    test('takeDamage applies pure bounds math clamping between 0 and maxHp',
        () {
      const hp = HitPoints(currentHp: 20, maxHp: 20, tempHp: 5);

      final after3 = hp.takeDamage(3);
      expect(after3.currentHp, equals(17));
      expect(after3.tempHp, equals(5));

      final after25 = hp.takeDamage(25);
      expect(after25.currentHp, equals(0));
      expect(after25.isDowned, isTrue);
      expect(after25.hpPercent, equals(0.0));
    });

    test('heal increases current HP up to maxHp and does not affect tempHp',
        () {
      const hp = HitPoints(currentHp: 10, maxHp: 25, tempHp: 4);

      final healed = hp.heal(8);
      expect(healed.currentHp, equals(18));
      expect(healed.tempHp, equals(4)); // unchanged

      final overHealed = hp.heal(30);
      expect(overHealed.currentHp, equals(25)); // clamped to maxHp
      expect(overHealed.tempHp, equals(4));
    });

    test('non-massive damage to 0 HP leaves actor downed but not dead', () {
      const hp = HitPoints(currentHp: 10, maxHp: 20);
      // 15 damage: 10 damage to HP -> 0 HP, excess 5 is less than 20 maxHp
      final downed = hp.takeDamage(15);
      expect(downed.currentHp, equals(0));
      expect(downed.isDowned, isTrue);
      expect(downed.isDead, isFalse);

      // Standard healing can revive/heal a downed actor per 5e RAW
      final healed = downed.heal(8);
      expect(healed.currentHp, equals(8));
      expect(healed.isDowned, isFalse);
      expect(healed.isDead, isFalse);
    });

    test(
        'heal does not revive a permanently dead actor unless allowRevive is true',
        () {
      const dead = HitPoints(currentHp: 0, maxHp: 20, isDead: true);
      expect(dead.isDead, isTrue);
      expect(dead.isDowned, isTrue);

      // Normal heal cannot revive a permanently dead actor
      final stillDead = dead.heal(10);
      expect(stillDead.currentHp, equals(0));
      expect(stillDead.isDead, isTrue);

      // Explicit allowRevive restores HP and revives actor
      final revived = dead.heal(10, allowRevive: true);
      expect(revived.currentHp, equals(10));
      expect(revived.isDead, isFalse);
      expect(revived.isDowned, isFalse);

      // Convenience revive() restores HP and clears isDead
      final revivedMethod = dead.revive(15);
      expect(revivedMethod.currentHp, equals(15));
      expect(revivedMethod.isDead, isFalse);
      expect(revivedMethod.isDowned, isFalse);
    });

    test('grantTempHp does not stack and takes highest unless forceOverride',
        () {
      const hp = HitPoints(currentHp: 15, maxHp: 20, tempHp: 5);

      // Lower grant ignored
      final lower = hp.grantTempHp(3);
      expect(lower.tempHp, equals(5));

      // Higher grant taken
      final higher = hp.grantTempHp(8);
      expect(higher.tempHp, equals(8));

      // Force override sets lower
      final forced = hp.setTempHp(2);
      expect(forced.tempHp, equals(2));
    });

    test('supports value equality and copyWith', () {
      const hp1 = HitPoints(currentHp: 12, maxHp: 15, tempHp: 3);
      const hp2 = HitPoints(currentHp: 12, maxHp: 15, tempHp: 3);
      final hp3 = hp1.copyWith(currentHp: 14);

      expect(hp1, equals(hp2));
      expect(hp1.hashCode, equals(hp2.hashCode));
      expect(hp1, isNot(equals(hp3)));
    });
  });
}
