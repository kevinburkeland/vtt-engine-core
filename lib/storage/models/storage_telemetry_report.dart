import 'package:meta/meta.dart';
import 'engine_profile.dart';

/// Immutable diagnostic report detailing browser persistence status, storage quota, and eviction risks.
@immutable
class StorageTelemetryReport {
  final bool isPersisted;
  final int bytesUsed;
  final int byteQuota;
  final EngineProfile profile;
  final DateTime timestamp;

  const StorageTelemetryReport({
    required this.isPersisted,
    required this.bytesUsed,
    required this.byteQuota,
    required this.profile,
    required this.timestamp,
  })  : assert(bytesUsed >= 0, 'bytesUsed must be non-negative: $bytesUsed'),
        assert(
          byteQuota >= bytesUsed,
          'byteQuota ($byteQuota) cannot be less than bytesUsed ($bytesUsed)',
        );

  /// Safe factory ensuring domain bounds invariants even with anomalous browser reports.
  factory StorageTelemetryReport.safe({
    required bool isPersisted,
    required int bytesUsed,
    required int byteQuota,
    required EngineProfile profile,
    DateTime? timestamp,
  }) {
    final clampedBytesUsed = bytesUsed < 0 ? 0 : bytesUsed;
    final clampedByteQuota =
        byteQuota < clampedBytesUsed ? clampedBytesUsed : byteQuota;

    return StorageTelemetryReport(
      isPersisted: isPersisted,
      bytesUsed: clampedBytesUsed,
      byteQuota: clampedByteQuota,
      profile: profile,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Percentage of quota consumed (0.0 to 100.0).
  double get quotaUsagePercent =>
      byteQuota > 0 ? (bytesUsed / byteQuota) * 100.0 : 0.0;

  /// Critical pressure threshold at 80% or greater quota saturation.
  bool get isCriticalPressure => quotaUsagePercent >= 80.0;

  /// Convenience forwarder to [EngineProfile.isWebKitEvictionRisk].
  bool get isWebKitEvictionRisk => profile.isWebKitEvictionRisk;

  /// Unprotected if not explicitly persisted while exposed to WebKit 7-day eviction policies.
  bool get isUnprotected => !isPersisted && isWebKitEvictionRisk;

  StorageTelemetryReport copyWith({
    bool? isPersisted,
    int? bytesUsed,
    int? byteQuota,
    EngineProfile? profile,
    DateTime? timestamp,
  }) {
    final nextUsed = bytesUsed ?? this.bytesUsed;
    final nextQuota = byteQuota ?? this.byteQuota;
    return StorageTelemetryReport(
      isPersisted: isPersisted ?? this.isPersisted,
      bytesUsed: nextUsed,
      byteQuota: nextQuota < nextUsed ? nextUsed : nextQuota,
      profile: profile ?? this.profile,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageTelemetryReport &&
          runtimeType == other.runtimeType &&
          isPersisted == other.isPersisted &&
          bytesUsed == other.bytesUsed &&
          byteQuota == other.byteQuota &&
          profile == other.profile &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
        isPersisted,
        bytesUsed,
        byteQuota,
        profile,
        timestamp,
      );

  @override
  String toString() =>
      'StorageTelemetryReport(persisted: $isPersisted, used: $bytesUsed, quota: $byteQuota, usage: ${quotaUsagePercent.toStringAsFixed(1)}%, unprotected: $isUnprotected, profile: $profile)';
}
