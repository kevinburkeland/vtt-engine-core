import 'dart:convert';
import 'package:meta/meta.dart';

/// Immutable audit log event stored in /rooms/{roomCode}/events/{eventId}
@immutable
class PartyEvent {
  final String id;
  final String roomCode;
  final String
      type; // 'coinDeposit', 'coinWithdraw', 'itemAdd', 'itemClaim', 'itemAttune', 'itemArchive', 'itemRestore', 'roomRehydrate', 'characterRemove', 'playerLeave'
  final String playerName;
  final String details;
  final String? entityId;
  final DateTime timestamp;

  const PartyEvent({
    required this.id,
    required this.roomCode,
    required this.type,
    required this.playerName,
    required this.details,
    this.entityId,
    required this.timestamp,
  });

  PartyEvent copyWith({
    String? id,
    String? roomCode,
    String? type,
    String? playerName,
    String? details,
    String? entityId,
    DateTime? timestamp,
  }) {
    return PartyEvent(
      id: id ?? this.id,
      roomCode: roomCode ?? this.roomCode,
      type: type ?? this.type,
      playerName: playerName ?? this.playerName,
      details: details ?? this.details,
      entityId: entityId ?? this.entityId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomCode': roomCode,
      'type': type,
      'playerName': playerName,
      'details': details,
      if (entityId != null) 'entityId': entityId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PartyEvent.fromMap(Map<String, dynamic> map) {
    final rawTs = map['timestamp'];
    if (rawTs == null) {
      throw const FormatException('PartyEvent.fromMap: missing required "timestamp".');
    }
    if (rawTs is! String) {
      throw FormatException('PartyEvent.fromMap: "timestamp" must be a String, got $rawTs.');
    }
    final parsedTs = DateTime.tryParse(rawTs);
    if (parsedTs == null) {
      throw FormatException('PartyEvent.fromMap: malformed ISO-8601 timestamp "$rawTs".');
    }

    return PartyEvent(
      id: map['id'] as String? ?? '',
      roomCode: map['roomCode'] as String? ?? '',
      type: map['type'] as String? ?? 'info',
      playerName: map['playerName'] as String? ?? 'Anonymous',
      details: map['details'] as String? ?? '',
      entityId: map['entityId'] as String?,
      timestamp: parsedTs,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory PartyEvent.fromJson(String source) =>
      PartyEvent.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartyEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          roomCode == other.roomCode &&
          type == other.type &&
          playerName == other.playerName &&
          details == other.details &&
          entityId == other.entityId &&
          (timestamp == other.timestamp ||
              timestamp.isAtSameMomentAs(other.timestamp));

  @override
  int get hashCode => Object.hash(
        id,
        roomCode,
        type,
        playerName,
        details,
        entityId,
        timestamp.toUtc().millisecondsSinceEpoch,
      );

  @override
  String toString() =>
      'PartyEvent(id: $id, type: $type, entityId: $entityId, timestamp: $timestamp)';
}
