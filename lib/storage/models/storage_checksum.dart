import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Pure Dart SHA-256 and constant-time digest comparison utility for the domain layer.
/// Uses standard package:crypto with zero Flutter engine dependencies.
class StorageChecksum {
  const StorageChecksum._();

  /// Computes the standard SHA-256 hex digest for [vaultId] + [payloadBytes].
  static String computeBundleChecksum(String vaultId, Uint8List payloadBytes) {
    final vaultBytes = utf8.encode(vaultId);
    final combined = Uint8List(vaultBytes.length + payloadBytes.length);
    combined.setRange(0, vaultBytes.length, vaultBytes);
    combined.setRange(vaultBytes.length, combined.length, payloadBytes);
    return computeSha256(combined);
  }

  /// Verifies [checksum] against `SHA-256(vaultId + payloadBytes)` using constant-time comparison.
  static bool verifyBundleChecksum({
    required String vaultId,
    required Uint8List payloadBytes,
    required String expectedChecksum,
  }) {
    final actual = computeBundleChecksum(vaultId, payloadBytes);
    return constantTimeEquals(
        actual.toLowerCase(), expectedChecksum.toLowerCase());
  }

  /// Constant-time string equality check to eliminate timing side-channel attacks.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Computes SHA-256 digest on raw bytes, returning a 64-character lowercase hex string.
  static String computeSha256(Uint8List message) {
    return crypto.sha256.convert(message).toString();
  }
}
