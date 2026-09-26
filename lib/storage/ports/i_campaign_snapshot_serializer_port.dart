import 'dart:async';
import 'dart:typed_data';
import '../../models/campaign_profile.dart';

/// Abstract port for serializing and deserializing campaign snapshots
/// for tamper-evident cold storage exports and hydrations.
abstract interface class ICampaignSnapshotSerializerPort {
  /// Default provider hook configured during application bootstrap.
  static ICampaignSnapshotSerializerPort Function()? defaultProvider;

  /// Serializes a [CampaignProfile] into raw bytes.
  FutureOr<Uint8List> serializeToBytes(CampaignProfile profile);

  /// Deserializes raw snapshot bytes back into a [CampaignProfile].
  FutureOr<CampaignProfile> deserializeFromBytes(Uint8List bytes);
}
