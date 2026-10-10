import '../crdt/hybrid_logical_clock.dart';
import 'campaign_profile.dart';
import 'session_graph_models.dart';

/// Pure helper extracting all non-zero physical time [HybridLogicalClock] timestamps
/// from a [CampaignProfile], including its notes register and room state.
List<HybridLogicalClock> extractCampaignProfileTimestamps(CampaignProfile profile) {
  final result = <HybridLogicalClock>[];
  if (profile.notesRegister.timestamp.physicalTime > 0) {
    result.add(profile.notesRegister.timestamp);
  }
  result.addAll(extractRoomNodeTimestamps(profile.roomState));
  return result;
}

/// Pure helper extracting all non-zero physical time [HybridLogicalClock] timestamps
/// from a [RoomNodeState], including active minions and active encounter collections.
List<HybridLogicalClock> extractRoomNodeTimestamps(RoomNodeState roomState) {
  final result = <HybridLogicalClock>[];
  result.addAll(roomState.activeMinions.extractTimestamps());
  result.addAll(roomState.activeEncounter.extractTimestamps());
  return result;
}
