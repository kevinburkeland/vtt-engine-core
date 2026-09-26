import 'package:meta/meta.dart';

@immutable
class RoomRoll {
  final String id;
  final String roomCode;
  final String playerName;
  final DateTime timestamp;
  final String formulaString;
  final int total;
  final List<int> individualRolls;
  final List<int>? droppedRolls;
  final List<String>? details;
  final bool isCrit;
  final bool isFumble;

  /// Optional pluggable encoder for Firestore Timestamp support in infrastructure.
  static dynamic Function(DateTime)? firestoreTimestampEncoder;

  const RoomRoll({
    required this.id,
    required this.roomCode,
    required this.playerName,
    required this.timestamp,
    required this.formulaString,
    required this.total,
    required this.individualRolls,
    this.droppedRolls,
    this.details,
    required this.isCrit,
    required this.isFumble,
  });

  factory RoomRoll.fromDiceRollResult({
    required String id,
    required String roomCode,
    required String playerName,
    required dynamic result,
    List<String>? details,
  }) {
    return RoomRoll(
      id: id,
      roomCode: roomCode,
      playerName: playerName,
      timestamp: result.timestamp as DateTime,
      formulaString: result.formulaString as String,
      total: (result.total as num).toInt(),
      individualRolls: (result.individualRolls as List)
          .map((e) => (e as num).toInt())
          .toList(),
      droppedRolls: (result.droppedRolls as List?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      details: details,
      isCrit: result.isCrit as bool,
      isFumble: result.isFumble as bool,
    );
  }

  Map<String, dynamic> toMap({
    bool useFirestoreTimestamp = true,
    dynamic Function(DateTime)? timestampEncoder,
  }) {
    final cleanCode = roomCode.trim().toUpperCase();
    final cleanPlayer =
        playerName.trim().isNotEmpty ? playerName.trim() : 'Adventurer';
    final clampedPlayer =
        cleanPlayer.length > 80 ? cleanPlayer.substring(0, 80) : cleanPlayer;
    final clampedFormula = formulaString.length > 200
        ? formulaString.substring(0, 200)
        : formulaString;
    final expireDate = timestamp.add(const Duration(hours: 24));

    final encoder = timestampEncoder ?? firestoreTimestampEncoder;
    final encodedTs = (useFirestoreTimestamp && encoder != null)
        ? encoder(timestamp)
        : timestamp.millisecondsSinceEpoch;
    final encodedExpire = (useFirestoreTimestamp && encoder != null)
        ? encoder(expireDate)
        : expireDate.millisecondsSinceEpoch;

    final map = <String, dynamic>{
      'id': id,
      'roomCode': cleanCode,
      'playerName': clampedPlayer,
      'timestamp': encodedTs,
      'expireAt': encodedExpire,
      'formulaString': clampedFormula,
      'total': total,
      'individualRolls': individualRolls,
      'isCrit': isCrit,
      'isFumble': isFumble,
    };

    if (droppedRolls != null && droppedRolls!.isNotEmpty) {
      map['droppedRolls'] = droppedRolls;
    }
    if (details != null && details!.isNotEmpty) {
      map['details'] = details!.take(50).toList();
    }
    return map;
  }

  factory RoomRoll.fromMap(Map<String, dynamic> map) {
    DateTime ts;
    final rawTs = map['timestamp'];
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is DateTime) {
      ts = rawTs;
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      try {
        ts = (rawTs as dynamic).toDate() as DateTime;
      } catch (_) {
        ts = DateTime.now();
      }
    }

    final rawIndiv = map['individualRolls'] as List?;
    final indivRolls = rawIndiv != null
        ? rawIndiv.map((e) => (e as num).toInt()).toList()
        : <int>[];

    final rawDropped = map['droppedRolls'] as List?;
    final droppedRolls = rawDropped?.map((e) => (e as num).toInt()).toList();

    final rawDetails = map['details'] as List?;
    final details = rawDetails?.map((e) => e.toString()).toList();

    return RoomRoll(
      id: map['id'] as String? ?? '',
      roomCode: map['roomCode'] as String? ?? '',
      playerName: map['playerName'] as String? ?? 'Anonymous',
      timestamp: ts,
      formulaString: map['formulaString'] as String? ?? '',
      total: (map['total'] as num? ?? 0).toInt(),
      individualRolls: indivRolls,
      droppedRolls: droppedRolls,
      details: details,
      isCrit: map['isCrit'] as bool? ?? false,
      isFumble: map['isFumble'] as bool? ?? false,
    );
  }
}
