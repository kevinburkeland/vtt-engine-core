import 'package:meta/meta.dart';
import 'value_objects/hit_points.dart';

/// Pure domain categorical classification of minion and entity sizes.
/// Decoupled from concrete ruleset combat statistics.
enum EntitySize {
  tiny(displayName: 'Tiny'),
  small(displayName: 'Small'),
  medium(displayName: 'Medium'),
  large(displayName: 'Large'),
  huge(displayName: 'Huge');

  final String displayName;

  const EntitySize({required this.displayName});

  static const Map<String, EntitySize> _lookup = {
    'tiny': EntitySize.tiny,
    'small': EntitySize.small,
    'medium': EntitySize.medium,
    'large': EntitySize.large,
    'huge': EntitySize.huge,
  };

  /// Safe parser mapping raw string inputs (e.g., 'Large Beast', 'Tiny') to [EntitySize] with fallback.
  static EntitySize fromString(String rawSize) {
    final normalized = rawSize.trim().toLowerCase();
    final direct = _lookup[normalized];
    if (direct != null) return direct;

    final tokens = normalized.split(' ');
    for (final token in tokens) {
      if (token.isEmpty) continue;
      final match = _lookup[token];
      if (match != null) return match;
    }
    return EntitySize.medium;
  }

  /// Resolves the minion statistics via the pluggable ruleset adapter / provider.
  MinionStats get stats => MinionStats.defaultProvider(this);

  int get pointCost => stats.pointCost;
  int get maxHp => stats.maxHp;
  int get ac => stats.ac;
  int get attackBonus => stats.attackBonus;
  int get damageDiceCount => stats.damageDiceCount;
  int get damageDiceSides => stats.damageDiceSides;
  int get damageBonus => stats.damageBonus;
  int get strScore => stats.strScore;
  int get dexScore => stats.dexScore;
  String get defaultExample => stats.defaultExample;
  String get damageFormula => stats.damageFormula;
}

/// Pure immutable value object representing combat and physical metrics for a minion.
@immutable
class MinionStats {
  final int pointCost;
  final int maxHp;
  final int ac;
  final int attackBonus;
  final int damageDiceCount;
  final int damageDiceSides;
  final int damageBonus;
  final int strScore;
  final int dexScore;
  final String defaultExample;

  const MinionStats({
    required this.pointCost,
    required this.maxHp,
    required this.ac,
    required this.attackBonus,
    required this.damageDiceCount,
    required this.damageDiceSides,
    required this.damageBonus,
    required this.strScore,
    required this.dexScore,
    required this.defaultExample,
  });

  String get damageFormula {
    final bonusStr = damageBonus == 0
        ? ''
        : (damageBonus > 0 ? '+$damageBonus' : '$damageBonus');
    return '${damageDiceCount}d$damageDiceSides$bonusStr';
  }

  /// Default pluggable stats provider across ruleset adapters.
  /// Decoupled from concrete 5e ruleset mechanics; populated via DI or the active ruleset module.
  static MinionStats Function(EntitySize size) defaultProvider = (size) {
    return _genericFallbackBaselines[size] ??
        _genericFallbackBaselines[EntitySize.medium]!;
  };

  static const Map<EntitySize, MinionStats> _genericFallbackBaselines = {
    EntitySize.tiny: MinionStats(
      pointCost: 1,
      maxHp: 1,
      ac: 10,
      attackBonus: 0,
      damageDiceCount: 1,
      damageDiceSides: 4,
      damageBonus: 0,
      strScore: 10,
      dexScore: 10,
      defaultExample: 'Tiny Object',
    ),
    EntitySize.small: MinionStats(
      pointCost: 1,
      maxHp: 5,
      ac: 10,
      attackBonus: 0,
      damageDiceCount: 1,
      damageDiceSides: 4,
      damageBonus: 0,
      strScore: 10,
      dexScore: 10,
      defaultExample: 'Small Object',
    ),
    EntitySize.medium: MinionStats(
      pointCost: 2,
      maxHp: 10,
      ac: 10,
      attackBonus: 0,
      damageDiceCount: 1,
      damageDiceSides: 6,
      damageBonus: 0,
      strScore: 10,
      dexScore: 10,
      defaultExample: 'Medium Object',
    ),
    EntitySize.large: MinionStats(
      pointCost: 4,
      maxHp: 15,
      ac: 10,
      attackBonus: 0,
      damageDiceCount: 1,
      damageDiceSides: 8,
      damageBonus: 0,
      strScore: 10,
      dexScore: 10,
      defaultExample: 'Large Object',
    ),
    EntitySize.huge: MinionStats(
      pointCost: 8,
      maxHp: 20,
      ac: 10,
      attackBonus: 0,
      damageDiceCount: 2,
      damageDiceSides: 6,
      damageBonus: 0,
      strScore: 10,
      dexScore: 10,
      defaultExample: 'Huge Object',
    ),
  };
}

/// Pure domain representation of minion identity markers for table distinguishing.
/// Decoupled from Flutter UI colors.
enum MinionMarker {
  standard,
  alpha,
  beta,
  gamma,
  delta,
  epsilon;

  static MinionMarker fromString(String? name) {
    if (name == null) return MinionMarker.standard;
    return MinionMarker.values.firstWhere(
      (m) => m.name.toLowerCase() == name.toLowerCase(),
      orElse: () => MinionMarker.standard,
    );
  }
}

@immutable
class MinionInstance {
  final String id;
  final String name;
  final EntitySize size;
  final HitPoints hitPoints;
  final String damageType;
  final int? customAc;
  final int? customAttackBonus;
  final int? customDamageDiceCount;
  final int? customDamageDiceSides;
  final int? customDamageBonus;
  final int secondaryDamageDiceCount;
  final int secondaryDamageDiceSides;
  final String? secondaryDamageType;
  final String? specialTrait;
  final String? statBlockId;
  final MinionMarker marker;
  final Map<String, dynamic> customProperties;

  MinionInstance({
    required this.id,
    required this.name,
    required this.size,
    HitPoints? hitPoints,
    int? currentHp,
    int? maxHp,
    int tempHp = 0,
    this.damageType = 'Bludgeoning',
    this.statBlockId,
    this.customAc,
    this.customAttackBonus,
    this.customDamageDiceCount,
    this.customDamageDiceSides,
    this.customDamageBonus,
    this.secondaryDamageDiceCount = 0,
    this.secondaryDamageDiceSides = 0,
    this.secondaryDamageType,
    this.specialTrait,
    this.marker = MinionMarker.standard,
    Map<String, dynamic>? customProperties,
  })  : hitPoints = hitPoints ??
            HitPoints(
              currentHp: currentHp ?? (maxHp ?? 10),
              maxHp: maxHp ?? 10,
              tempHp: tempHp,
            ),
        customProperties = Map.unmodifiable(customProperties ?? const {});

  int get currentHp => hitPoints.currentHp;

  int get maxHp => hitPoints.maxHp;

  int get tempHp => hitPoints.tempHp;

  // Effective Stat Getters
  int get ac => customAc ?? size.ac;
  int get attackBonus => customAttackBonus ?? size.attackBonus;
  int get damageDiceCount => customDamageDiceCount ?? size.damageDiceCount;
  int get damageDiceSides => customDamageDiceSides ?? size.damageDiceSides;
  int get damageBonus => customDamageBonus ?? size.damageBonus;

  /// Convenience getters for arbitrary ruleset attributes stored in [customProperties].
  bool get isSilvered => customProperties['isSilvered'] == true;
  bool get hasPackTactics => customProperties['hasPackTactics'] == true;

  /// Formatted damage formula string (e.g., "1d4+4 Bludgeoning").
  String get damageFormula {
    final bonusStr = damageBonus == 0
        ? ''
        : (damageBonus > 0 ? '+$damageBonus' : '$damageBonus');
    final typeStr = damageType.trim().isNotEmpty ? ' ${damageType.trim()}' : '';
    final primary = '${damageDiceCount}d$damageDiceSides$bonusStr$typeStr';
    if (secondaryDamageDiceCount > 0 &&
        secondaryDamageType != null &&
        secondaryDamageType!.trim().isNotEmpty) {
      final secTypeStr = ' ${secondaryDamageType!.trim()}';
      return '$primary + ${secondaryDamageDiceCount}d$secondaryDamageDiceSides$secTypeStr';
    }
    return primary;
  }

  bool get isDead => hitPoints.isDead || hitPoints.currentHp <= 0;

  /// Safe calculation of remaining HP percentage, strictly protected against NaN / division-by-zero.
  double get hpPercent => hitPoints.hpPercent;

  /// Pure copy-transform damage application with Temporary HP absorption.
  /// When a minion's HP is reduced to 0, it is marked defeated/dead.
  MinionInstance applyDamage(int amount) {
    if (amount <= 0) return this;
    int remaining = amount;
    int newTemp = hitPoints.tempHp;
    if (newTemp > 0) {
      if (remaining <= newTemp) {
        newTemp -= remaining;
        remaining = 0;
      } else {
        remaining -= newTemp;
        newTemp = 0;
      }
    }
    final newHp = hitPoints.takeDamage(remaining).copyWith(tempHp: newTemp);
    return copyWith(
      hitPoints: newHp.copyWith(isDead: newHp.isDead || newHp.currentHp <= 0),
    );
  }

  /// Pure copy-transform healing application capped to Max HP.
  MinionInstance applyHealing(int amount, {bool allowRevive = false}) =>
      copyWith(hitPoints: hitPoints.heal(amount, allowRevive: allowRevive));

  /// Pure copy-transform revival restoring a destroyed minion to positive HP.
  MinionInstance revive(int amount) =>
      copyWith(hitPoints: hitPoints.revive(amount));

  /// Pure copy-transform Temporary HP application.
  MinionInstance applyTempHp(int amount) =>
      copyWith(hitPoints: hitPoints.grantTempHp(amount));

  MinionInstance copyWith({
    String? id,
    String? name,
    EntitySize? size,
    HitPoints? hitPoints,
    int? currentHp,
    int? maxHp,
    int? tempHp,
    String? damageType,
    int? customAc,
    int? customAttackBonus,
    int? customDamageDiceCount,
    int? customDamageDiceSides,
    int? customDamageBonus,
    int? secondaryDamageDiceCount,
    int? secondaryDamageDiceSides,
    String? secondaryDamageType,
    String? specialTrait,
    String? statBlockId,
    MinionMarker? marker,
    Map<String, dynamic>? customProperties,
  }) {
    final resolvedHp = hitPoints ??
        (currentHp != null || maxHp != null || tempHp != null
            ? this.hitPoints.copyWith(
                  currentHp: currentHp,
                  maxHp: maxHp,
                  tempHp: tempHp,
                )
            : this.hitPoints);

    return MinionInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      hitPoints: resolvedHp,
      damageType: damageType ?? this.damageType,
      statBlockId: statBlockId ?? this.statBlockId,
      customAc: customAc ?? this.customAc,
      customAttackBonus: customAttackBonus ?? this.customAttackBonus,
      customDamageDiceCount:
          customDamageDiceCount ?? this.customDamageDiceCount,
      customDamageDiceSides:
          customDamageDiceSides ?? this.customDamageDiceSides,
      customDamageBonus: customDamageBonus ?? this.customDamageBonus,
      secondaryDamageDiceCount:
          secondaryDamageDiceCount ?? this.secondaryDamageDiceCount,
      secondaryDamageDiceSides:
          secondaryDamageDiceSides ?? this.secondaryDamageDiceSides,
      secondaryDamageType: secondaryDamageType ?? this.secondaryDamageType,
      specialTrait: specialTrait ?? this.specialTrait,
      marker: marker ?? this.marker,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'size': size.name,
      'currentHp': currentHp,
      'maxHp': maxHp,
      'tempHp': tempHp,
      'damageType': damageType,
      'isSilvered': isSilvered,
      'customAc': customAc,
      'customAttackBonus': customAttackBonus,
      'customDamageDiceCount': customDamageDiceCount,
      'customDamageDiceSides': customDamageDiceSides,
      'customDamageBonus': customDamageBonus,
      'secondaryDamageDiceCount': secondaryDamageDiceCount,
      'secondaryDamageDiceSides': secondaryDamageDiceSides,
      'secondaryDamageType': secondaryDamageType,
      'hasPackTactics': hasPackTactics,
      'specialTrait': specialTrait,
      'statBlockId': statBlockId,
      'marker': marker.name,
      'customProperties': customProperties,
    };
  }

  factory MinionInstance.fromMap(Map<String, dynamic> map) {
    int asInt(dynamic val, {required int fallback}) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    final sizeStr = map['size']?.toString() ?? 'medium';
    final parsedSize = EntitySize.fromString(sizeStr);

    final rawMarker = map['marker']?.toString().toLowerCase().trim();
    final marker = MinionMarker.values.firstWhere(
      (m) => m.name == rawMarker,
      orElse: () => MinionMarker.standard,
    );

    final parsedCustomProps = map['customProperties'] is Map
        ? Map<String, dynamic>.from(map['customProperties'] as Map)
        : <String, dynamic>{};

    if (map['isSilvered'] == true) parsedCustomProps['isSilvered'] = true;
    if (map['hasPackTactics'] == true)
      parsedCustomProps['hasPackTactics'] = true;

    final curHp =
        asInt(map['currentHp'] ?? map['hp'], fallback: parsedSize.maxHp)
            .clamp(0, 999);
    final mxHp = asInt(map['maxHp'] ?? map['mhp'], fallback: parsedSize.maxHp)
        .clamp(1, 999);
    final thp = asInt(map['tempHp'] ?? map['thp'], fallback: 0).clamp(0, 999);

    return MinionInstance(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? map['n'] ?? parsedSize.defaultExample).toString(),
      size: parsedSize,
      hitPoints: HitPoints(
        currentHp: curHp,
        maxHp: mxHp,
        tempHp: thp,
        isDead: curHp <= 0,
      ),
      damageType: (map['damageType'] ?? 'Bludgeoning').toString(),
      statBlockId: map['statBlockId']?.toString(),
      customAc:
          map['customAc'] != null ? asInt(map['customAc'], fallback: 10) : null,
      customAttackBonus: map['customAttackBonus'] != null
          ? asInt(map['customAttackBonus'], fallback: 0)
          : null,
      customDamageDiceCount: map['customDamageDiceCount'] != null
          ? asInt(map['customDamageDiceCount'], fallback: 1)
          : null,
      customDamageDiceSides: map['customDamageDiceSides'] != null
          ? asInt(map['customDamageDiceSides'], fallback: 4)
          : null,
      customDamageBonus: map['customDamageBonus'] != null
          ? asInt(map['customDamageBonus'], fallback: 0)
          : null,
      secondaryDamageDiceCount:
          asInt(map['secondaryDamageDiceCount'], fallback: 0),
      secondaryDamageDiceSides:
          asInt(map['secondaryDamageDiceSides'], fallback: 0),
      secondaryDamageType: map['secondaryDamageType']?.toString(),
      specialTrait: map['specialTrait']?.toString(),
      marker: marker,
      customProperties: parsedCustomProps,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinionInstance &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          size == other.size &&
          hitPoints == other.hitPoints &&
          damageType == other.damageType &&
          statBlockId == other.statBlockId &&
          customAc == other.customAc &&
          customAttackBonus == other.customAttackBonus &&
          customDamageDiceCount == other.customDamageDiceCount &&
          customDamageDiceSides == other.customDamageDiceSides &&
          customDamageBonus == other.customDamageBonus &&
          secondaryDamageDiceCount == other.secondaryDamageDiceCount &&
          secondaryDamageDiceSides == other.secondaryDamageDiceSides &&
          secondaryDamageType == other.secondaryDamageType &&
          specialTrait == other.specialTrait &&
          marker == other.marker;

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        size,
        hitPoints,
        damageType,
        statBlockId,
        customAc,
        customAttackBonus,
        customDamageDiceCount,
        customDamageDiceSides,
        customDamageBonus,
        secondaryDamageDiceCount,
        secondaryDamageDiceSides,
        secondaryDamageType,
        specialTrait,
        marker,
      ]);

  @override
  String toString() =>
      'MinionInstance(id: $id, name: $name, size: ${size.displayName}, HP: $currentHp/$maxHp, AC: $ac)';
}
