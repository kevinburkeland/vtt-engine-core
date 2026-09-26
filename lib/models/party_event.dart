import 'dart:convert';
import 'package:meta/meta.dart';

/// Immutable audit log event stored in /rooms/{roomCode}/events/{eventId}
@immutable
class PartyEvent {
  final String id;
  final String roomCode;
  final String
      type; // 'coinDeposit', 'coinWithdraw', 'itemAdd', 'itemClaim', 'itemAttune', 'itemArchive', 'itemRestore', 'roomRehydrate'
  final String playerName;
  final String details;
  final DateTime timestamp;

  const PartyEvent({
    required this.id,
    required this.roomCode,
    required this.type,
    required this.playerName,
    required this.details,
    required this.timestamp,
  });

  PartyEvent copyWith({
    String? id,
    String? roomCode,
    String? type,
    String? playerName,
    String? details,
    DateTime? timestamp,
  }) {
    return PartyEvent(
      id: id ?? this.id,
      roomCode: roomCode ?? this.roomCode,
      type: type ?? this.type,
      playerName: playerName ?? this.playerName,
      details: details ?? this.details,
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
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PartyEvent.fromMap(Map<String, dynamic> map) {
    return PartyEvent(
      id: map['id'] as String? ?? '',
      roomCode: map['roomCode'] as String? ?? '',
      type: map['type'] as String? ?? 'info',
      playerName: map['playerName'] as String? ?? 'Anonymous',
      details: map['details'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory PartyEvent.fromJson(String source) =>
      PartyEvent.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
