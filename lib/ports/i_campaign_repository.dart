import '../models/campaign_profile.dart';

/// Port (interface) defining campaign persistence operations in the Domain layer.
abstract class ICampaignRepository {
  /// Currently active profile ID, or null if unset.
  String? get activeProfileId;

  /// Currently active in-memory campaign profile.
  CampaignProfile? get activeProfile;

  /// List of all loaded campaign profiles.
  List<CampaignProfile> get allProfiles;

  /// Loads all saved campaign profiles from persistent storage.
  Future<List<CampaignProfile>> loadAllProfiles();

  /// Retrieves a campaign profile by ID from cache or persistent storage.
  Future<CampaignProfile?> getProfile(String id);

  /// Retrieves the active campaign profile.
  Future<CampaignProfile?> getActiveProfile();

  /// Atomically transforms a campaign profile by ID through a serialized update path.
  ///
  /// Updates to the same id are serialized: each transform receives the result of the previous one.
  /// The in-memory cache is updated synchronously inside that serialized section, before any await
  /// that lets another update read it. Persistence and stream emission occur after.
  Future<CampaignProfile> updateProfile(
    String id,
    CampaignProfile Function(CampaignProfile current) transform,
  );

  /// Writes a whole campaign profile record to persistent storage.
  ///
  /// Used for create, restore, or import only; never for edits.
  Future<void> putProfile(CampaignProfile profile);

  /// Deletes a campaign profile by ID from storage and cache.
  Future<void> deleteProfile(String id);

  /// Sets the active campaign profile ID and persists the selection.
  Future<void> setActiveProfileId(String id);

  /// Reactive stream broadcasting updates to the active campaign profile.
  Stream<CampaignProfile?> watchActiveProfile();

  /// Reactive stream broadcasting updates to the list of all campaign profiles.
  Stream<List<CampaignProfile>> watchAllProfiles();
}
