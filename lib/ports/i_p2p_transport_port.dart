import 'dart:async';
import 'transport_state.dart';

export 'transport_state.dart';

/// Protocol-agnostic port interface for peer-to-peer and relay payload transport.
///
/// Decouples network communication details (WebRTC DataChannels, cloud relays)
/// from the core domain and CRDT state synchronization mechanisms.
abstract class IP2pTransportPort {
  /// Current transport state (connecting, localWifi, webRtc, fallbackRelay, offline).
  TransportState get currentState;

  /// Map of connected peer node IDs to their last active timestamp (epoch ms).
  Map<String, int> get peerLastSeen;

  /// Time-to-live threshold for active peer heartbeats before being flagged as zombie/pruned.
  Duration get heartbeatTtl => const Duration(seconds: 15);

  /// Prepares the transport session before initialization (e.g. cleans up stale signaling documents).
  Future<void> prepareSession() async {}

  /// Tests if this adapter can establish a viable connection without disrupting active streams.
  Future<bool> probeViability(String roomCode, String localNodeId) async =>
      false;

  /// Initializes room network topology for the given [roomCode] and [localNodeId].
  Future<void> initializeRoom(String roomCode, String localNodeId);

  /// Broadcasts a JSON string payload to all active room participants.
  Future<void> broadcastPayload(String jsonPayload);

  /// Emits incoming JSON string payloads received from remote peers or relays.
  Stream<String> watchIncomingPayloads();

  /// Gracefully tears down connections, closes channels, and releases resources.
  Future<void> disconnect();
}
