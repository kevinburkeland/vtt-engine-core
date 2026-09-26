import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'storage_checksum.dart';

/// Immutable snapshot container encapsulating campaign cold-storage payloads
/// protected by a constant-time cryptographic SHA-256 integrity seal.
@immutable
class StorageSnapshotBundle {
  final String schemaVersion;
  final String vaultId;
  final Uint8List payloadBytes;
  final String sha256Checksum;
  final DateTime exportedAt;

  const StorageSnapshotBundle({
    required this.schemaVersion,
    required this.vaultId,
    required this.payloadBytes,
    required this.sha256Checksum,
    required this.exportedAt,
  });

  /// Factory creating an authentic snapshot bundle with an automatically computed SHA-256 seal.
  factory StorageSnapshotBundle.create({
    required String vaultId,
    required Uint8List payloadBytes,
    String schemaVersion = '1.0.0',
    DateTime? exportedAt,
  }) {
    final checksum =
        StorageChecksum.computeBundleChecksum(vaultId, payloadBytes);
    return StorageSnapshotBundle(
      schemaVersion: schemaVersion,
      vaultId: vaultId,
      payloadBytes: payloadBytes,
      sha256Checksum: checksum,
      exportedAt: exportedAt ?? DateTime.now(),
    );
  }

  /// Factory creating an authentic snapshot bundle and verifying integrity immediately.
  /// Throws [ArgumentError] if the checksum is tampered or invalid.
  factory StorageSnapshotBundle.validated({
    required String schemaVersion,
    required String vaultId,
    required Uint8List payloadBytes,
    required String sha256Checksum,
    required DateTime exportedAt,
  }) {
    final bundle = StorageSnapshotBundle(
      schemaVersion: schemaVersion,
      vaultId: vaultId,
      payloadBytes: payloadBytes,
      sha256Checksum: sha256Checksum,
      exportedAt: exportedAt,
    );
    bundle.validateOrThrow();
    return bundle;
  }

  /// Evaluates cryptographic integrity via constant-time verification against `SHA-256(vaultId + payloadBytes)`.
  bool get isValid => StorageChecksum.verifyBundleChecksum(
        vaultId: vaultId,
        payloadBytes: payloadBytes,
        expectedChecksum: sha256Checksum,
      );

  /// Asserts bundle validity, throwing [StateError] if corrupted or tampered.
  void validateOrThrow() {
    if (!isValid) {
      throw StateError(
        'StorageSnapshotBundle integrity check failed: SHA-256 checksum mismatch for vault "$vaultId".',
      );
    }
  }

  /// Serializes this bundle into an envelope byte array suitable for atomic disk persistence.
  Uint8List toBytes() {
    final envelope = <String, dynamic>{
      'magic': 'DNDVAULT',
      'schemaVersion': schemaVersion,
      'vaultId': vaultId,
      'exportedAt': exportedAt.toIso8601String(),
      'sha256Checksum': sha256Checksum,
      'payload': base64Encode(payloadBytes),
    };
    final jsonStr = jsonEncode(envelope);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// Deserializes a bundle from an envelope byte array.
  factory StorageSnapshotBundle.fromBytes(Uint8List bytes) {
    final jsonStr = utf8.decode(bytes);
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Invalid cold storage snapshot: expected JSON envelope');
    }

    final schemaVersion = decoded['schemaVersion']?.toString() ?? '1.0.0';
    final vaultId = decoded['vaultId']?.toString() ?? '';
    final sha256Checksum = decoded['sha256Checksum']?.toString() ?? '';
    final exportedAtStr = decoded['exportedAt']?.toString();
    final exportedAt =
        (exportedAtStr != null ? DateTime.tryParse(exportedAtStr) : null) ??
            DateTime.now();

    final payloadStr = decoded['payload']?.toString() ?? '';
    final payloadBytes = base64Decode(payloadStr);

    return StorageSnapshotBundle(
      schemaVersion: schemaVersion,
      vaultId: vaultId,
      payloadBytes: payloadBytes,
      sha256Checksum: sha256Checksum,
      exportedAt: exportedAt,
    );
  }

  StorageSnapshotBundle copyWith({
    String? schemaVersion,
    String? vaultId,
    Uint8List? payloadBytes,
    String? sha256Checksum,
    DateTime? exportedAt,
  }) {
    return StorageSnapshotBundle(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      vaultId: vaultId ?? this.vaultId,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      sha256Checksum: sha256Checksum ?? this.sha256Checksum,
      exportedAt: exportedAt ?? this.exportedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageSnapshotBundle &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          vaultId == other.vaultId &&
          sha256Checksum == other.sha256Checksum &&
          exportedAt == other.exportedAt &&
          const ListEquality<int>().equals(payloadBytes, other.payloadBytes);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        vaultId,
        sha256Checksum,
        exportedAt,
        const ListEquality<int>().hash(payloadBytes),
      );

  @override
  String toString() =>
      'StorageSnapshotBundle(vault: $vaultId, version: $schemaVersion, checksum: ${sha256Checksum.substring(0, 8)}..., size: ${payloadBytes.length} bytes)';
}
