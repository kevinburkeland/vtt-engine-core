import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../utils/deep_immutable.dart';
import 'room_entity_link.dart';

const _deepEquality = DeepCollectionEquality();

/// Dynamic Combat and Turn-Tracker Participant in an active room encounter.
/// Decoupled from mandatory HP, defense, initiative, and death assumptions.
@immutable
class EncounterParticipant {
  final String participantId;
  final RoomEntityLink entityLink;
  final int? initiativeScore;
  final int? initiativeTieBreaker;
  final int? currentHp;
  final int? maxHp;
  final int? tempHp;
  final int? defense;
  final List<String> activeConditions;
  final bool? isDefeated;
  final bool? isDead;
  final bool isActiveTurn;
  final Map<String, dynamic> customProperties;

  int? get defenseRating => defense;

  EncounterParticipant({
    required this.participantId,
    required this.entityLink,
    this.initiativeScore,
    this.initiativeTieBreaker,
    this.currentHp,
    this.maxHp,
    this.tempHp,
    this.defense,
    List<String> activeConditions = const [],
    this.isDefeated,
    this.isDead,
    this.isActiveTurn = false,
    Map<String, dynamic> customProperties = const {},
  })  : activeConditions = List.unmodifiable(activeConditions),
        customProperties = deepFreezeMap(customProperties);

  const EncounterParticipant.empty()
      : participantId = '',
        entityLink = const RoomEntityLink.empty(),
        initiativeScore = null,
        initiativeTieBreaker = null,
        currentHp = null,
        maxHp = null,
        tempHp = null,
        defense = null,
        activeConditions = const [],
        isDefeated = null,
        isDead = null,
        isActiveTurn = false,
        customProperties = const {};

  EncounterParticipant copyWith({
    String? participantId,
    RoomEntityLink? entityLink,
    int? initiativeScore,
    int? initiativeTieBreaker,
    dynamic hitPoints,
    int? currentHp,
    int? maxHp,
    int? tempHp,
    int? defense,
    List<String>? activeConditions,
    bool? isDefeated,
    bool? isDead,
    bool? isActiveTurn,
    Map<String, dynamic>? customProperties,
  }) {
    int? hpCurrent;
    int? hpMax;
    int? hpTemp;
    bool? hpDead;
    if (hitPoints != null) {
      try {
        hpCurrent = (hitPoints as dynamic).currentHp as int?;
        hpMax = (hitPoints as dynamic).maxHp as int?;
        hpTemp = (hitPoints as dynamic).tempHp as int?;
        hpDead = (hitPoints as dynamic).isDead as bool?;
      } catch (_) {}
    }

    return EncounterParticipant(
      participantId: participantId ?? this.participantId,
      entityLink: entityLink ?? this.entityLink,
      initiativeScore: initiativeScore ?? this.initiativeScore,
      initiativeTieBreaker: initiativeTieBreaker ?? this.initiativeTieBreaker,
      currentHp: hpCurrent ?? currentHp ?? this.currentHp,
      maxHp: hpMax ?? maxHp ?? this.maxHp,
      tempHp: hpTemp ?? tempHp ?? this.tempHp,
      defense: defense ?? this.defense,
      activeConditions: activeConditions ?? this.activeConditions,
      isDefeated: isDefeated ?? this.isDefeated,
      isDead: hpDead ?? isDead ?? this.isDead,
      isActiveTurn: isActiveTurn ?? this.isActiveTurn,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  Map<String, dynamic> toMap() => {
        'participantId': participantId,
        'entityLink': entityLink.toMap(),
        if (initiativeScore != null) 'initiativeScore': initiativeScore,
        if (initiativeTieBreaker != null)
          'initiativeTieBreaker': initiativeTieBreaker,
        if (currentHp != null) 'currentHp': currentHp,
        if (maxHp != null) 'maxHp': maxHp,
        if (tempHp != null) 'tempHp': tempHp,
        if (defense != null) 'defense': defense,
        'activeConditions': activeConditions,
        if (isDefeated != null) 'isDefeated': isDefeated,
        if (isDead != null) 'isDead': isDead,
        'isActiveTurn': isActiveTurn,
        if (customProperties.isNotEmpty)
          'customProperties': customProperties,
      };

  factory EncounterParticipant.fromMap(Map<String, dynamic> map) {
    int? cur = (map['currentHp'] as num?)?.toInt();
    int? max = (map['maxHp'] as num?)?.toInt();
    int? temp = (map['tempHp'] as num?)?.toInt();
    bool? isDead = map['isDead'] as bool?;
    if (map['hitPoints'] is Map) {
      final hpMap = map['hitPoints'] as Map;
      cur ??= (hpMap['currentHp'] as num?)?.toInt();
      max ??= (hpMap['maxHp'] as num?)?.toInt();
      temp ??= (hpMap['tempHp'] as num?)?.toInt();
      isDead ??= hpMap['isDead'] as bool?;
    }

    return EncounterParticipant(
      participantId: map['participantId']?.toString() ?? '',
      entityLink: RoomEntityLink.fromMap(
          Map<String, dynamic>.from(map['entityLink'] as Map? ?? {})),
      initiativeScore: (map['initiativeScore'] as num?)?.toInt(),
      initiativeTieBreaker: (map['initiativeTieBreaker'] as num?)?.toInt(),
      currentHp: cur,
      maxHp: max,
      tempHp: temp,
      defense: (map['defense'] as num?)?.toInt() ??
          (map['defenseRating'] as num?)?.toInt() ??
          (map['ac'] as num?)?.toInt(),
      activeConditions:
          (map['activeConditions'] as List? ?? []).whereType<String>().toList(),
      isDefeated: map['isDefeated'] is bool ? map['isDefeated'] as bool : null,
      isDead: isDead ?? (map['isDead'] is bool ? map['isDead'] as bool : null),
      isActiveTurn: map['isActiveTurn'] == true,
      customProperties:
          Map<String, dynamic>.from(map['customProperties'] as Map? ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncounterParticipant &&
          runtimeType == other.runtimeType &&
          participantId == other.participantId &&
          entityLink == other.entityLink &&
          initiativeScore == other.initiativeScore &&
          initiativeTieBreaker == other.initiativeTieBreaker &&
          currentHp == other.currentHp &&
          maxHp == other.maxHp &&
          tempHp == other.tempHp &&
          defense == other.defense &&
          _deepEquality.equals(activeConditions, other.activeConditions) &&
          isDefeated == other.isDefeated &&
          isDead == other.isDead &&
          isActiveTurn == other.isActiveTurn &&
          _deepEquality.equals(customProperties, other.customProperties);

  @override
  int get hashCode => Object.hash(
        participantId,
        entityLink,
        initiativeScore,
        initiativeTieBreaker,
        currentHp,
        maxHp,
        tempHp,
        defense,
        _deepEquality.hash(activeConditions),
        isDefeated,
        isDead,
        isActiveTurn,
        _deepEquality.hash(customProperties),
      );
}
