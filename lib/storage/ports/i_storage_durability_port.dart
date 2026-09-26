import '../models/engine_profile.dart';
import '../models/storage_telemetry_report.dart';

/// Port defining low-level browser storage durability inspection and persistence requests.
abstract interface class IStorageDurabilityPort {
  /// Inspects browser storage manager to determine persisted status, usage, and quota limits.
  Future<StorageTelemetryReport> inspectStorage();

  /// Requests eviction-immune persistent storage permissions from the host browser.
  Future<bool> requestPersistence();

  /// Synchronously detects the active browser engine, operating system, and standalone display mode.
  EngineProfile detectProfile();
}
