import '../models/storage_snapshot_bundle.dart';

/// Port defining atomic physical cold-storage export and import file operations.
abstract interface class IPhysicalSnapshotPort {
  /// Packages and exports an atomic binary snapshot bundle to the host file system.
  Future<void> exportAtomicSnapshot({
    required String fileName,
    required StorageSnapshotBundle bundle,
  });

  /// Prompts the user to select and import an atomic snapshot bundle from the host file system.
  /// Returns null if the user cancels selection or the file cannot be read.
  Future<StorageSnapshotBundle?> importAtomicSnapshot();
}
