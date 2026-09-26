import 'package:meta/meta.dart';
import '../crdt/crdt_or_set.dart';
import '../models/campaign_profile.dart';
import '../models/party_purse.dart';
import '../models/room_roll.dart';

/// Sealed hierarchy of incoming network sync messages parsed from raw JSON transport payloads.
@immutable
sealed class IncomingRoomSyncMessage {
  final String originNodeId;
  final int originSeq;
  final int timestamp;

  const IncomingRoomSyncMessage({
    required this.originNodeId,
    required this.originSeq,
    required this.timestamp,
  });
}

/// Full campaign profile broadcast message with optional embedded CRDT sets and purse deltas.
@immutable
class FullProfileSyncMessage extends IncomingRoomSyncMessage {
  final CampaignProfile profile;
  final PartyPurse? purseDelta;
  final CrdtOrSet<String>? pinnedRulesDelta;

  const FullProfileSyncMessage({
    required super.originNodeId,
    required super.originSeq,
    required super.timestamp,
    required this.profile,
    this.purseDelta,
    this.pinnedRulesDelta,
  });
}

/// Focused CRDT currency delta message for high-frequency conflict-free purse convergence.
@immutable
class PurseDeltaSyncMessage extends IncomingRoomSyncMessage {
  final String campaignId;
  final PartyPurse purse;

  const PurseDeltaSyncMessage({
    required super.originNodeId,
    required super.originSeq,
    required super.timestamp,
    required this.campaignId,
    required this.purse,
  });
}

/// Focused CRDT OR-Set delta message for pinned rules or generic set convergence.
@immutable
class OrSetDeltaSyncMessage extends IncomingRoomSyncMessage {
  final String campaignId;
  final CrdtOrSet<String> rulesSet;

  const OrSetDeltaSyncMessage({
    required super.originNodeId,
    required super.originSeq,
    required super.timestamp,
    required this.campaignId,
    required this.rulesSet,
  });
}

/// Ephemeral room dice roll event broadcast.
@immutable
class DiceRollSyncMessage extends IncomingRoomSyncMessage {
  final RoomRoll roll;

  const DiceRollSyncMessage({
    required super.originNodeId,
    required super.originSeq,
    required super.timestamp,
    required this.roll,
  });
}

/// Unrecognized or corrupt network payload.
@immutable
class UnknownSyncMessage extends IncomingRoomSyncMessage {
  const UnknownSyncMessage()
      : super(originNodeId: '', originSeq: 0, timestamp: 0);
}

/// Port defining synchronization payload parsing, hashing, and serialization.
abstract interface class IRoomSyncPayloadPort {
  /// Default provider hook configured during application initialization.
  static IRoomSyncPayloadPort Function()? defaultProvider;

  /// Computes a deterministic SHA-256 hash string for payload deduplication.
  String computePayloadHash(String jsonPayload);

  /// Parses a raw incoming JSON string into an [IncomingRoomSyncMessage].
  IncomingRoomSyncMessage parsePayload(String jsonPayload);

  /// Serializes a full campaign profile sync broadcast into an envelope JSON string.
  String serializeFullProfileSync({
    required CampaignProfile profile,
    required String originNodeId,
    required int originSeq,
    required int timestamp,
    CrdtOrSet<String>? trackedRulesSet,
  });

  /// Serializes a focused purse delta broadcast into an envelope JSON string.
  String serializePurseDelta({
    required String campaignId,
    required PartyPurse purse,
    required String originNodeId,
    required int originSeq,
    required int timestamp,
  });

  /// Serializes a focused OR-Set delta broadcast into an envelope JSON string.
  String serializeOrSetDelta({
    required String campaignId,
    required CrdtOrSet<String> rulesSet,
    required String originNodeId,
    required int originSeq,
    required int timestamp,
  });
}
