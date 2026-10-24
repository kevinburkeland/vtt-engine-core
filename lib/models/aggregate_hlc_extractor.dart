import '../crdt/hybrid_logical_clock.dart';
import 'campaign_profile.dart';
import 'session_graph_models.dart';

/// Pure helper extracting all non-zero physical time [HybridLogicalClock] timestamps
/// from a [CampaignProfile], including its name, notes register, pinned rules, party roster, and room state.
List<HybridLogicalClock> extractCampaignProfileTimestamps(CampaignProfile profile) {
  final result = <HybridLogicalClock>[];
  if (profile.nameRegister.timestamp.physicalTime > 0) {
    result.add(profile.nameRegister.timestamp);
  }
  if (profile.notesRegister.timestamp.physicalTime > 0) {
    result.add(profile.notesRegister.timestamp);
  }
  if (profile.activeMapRegister.timestamp.physicalTime > 0) {
    result.add(profile.activeMapRegister.timestamp);
  }
  result.addAll(profile.pinnedRules.extractTimestamps());
  result.addAll(profile.partyRoster.extractTimestamps());
  result.addAll(extractRoomNodeTimestamps(profile.roomState));
  return result;
}

/// Pure helper extracting all non-zero physical time [HybridLogicalClock] timestamps
/// from a [RoomNodeState], including title, description, entity links (and individual link notes),
/// entity instances (displayName), containers (name), active minions, and active encounter collections.
List<HybridLogicalClock> extractRoomNodeTimestamps(RoomNodeState roomState) {
  final result = <HybridLogicalClock>[];
  if (roomState.titleRegister.timestamp.physicalTime > 0) {
    result.add(roomState.titleRegister.timestamp);
  }
  if (roomState.descriptionRegister.timestamp.physicalTime > 0) {
    result.add(roomState.descriptionRegister.timestamp);
  }
  result.addAll(roomState.entityLinksCrdt.extractTimestamps());
  for (final instance in roomState.entityInstances) {
    if (instance.displayNameRegister.timestamp.physicalTime > 0) {
      result.add(instance.displayNameRegister.timestamp);
    }
  }
  for (final container in roomState.containers) {
    if (container.nameRegister.timestamp.physicalTime > 0) {
      result.add(container.nameRegister.timestamp);
    }
  }
  result.addAll(roomState.activeMinions.extractTimestamps());
  result.addAll(roomState.activeEncounter.extractTimestamps());
  return result;
}
