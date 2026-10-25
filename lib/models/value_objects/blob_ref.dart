import 'package:meta/meta.dart';

/// Image formats a shared blob may have. The wire names are exactly 'webp' and 'jpeg'.
enum BlobFormat { webp, jpeg }

/// Immutable, content-addressed reference to an image blob held outside the CRDT.
@immutable
final class BlobRef {
  static const int maxLongestSidePx = 4096;
  static const int maxByteSize = 10 * 1024 * 1024; // 10 MiB = 10,485,760 bytes

  final String sha256Hex;
  final int byteSize;
  final int width;
  final int height;
  final BlobFormat format;

  BlobRef({
    required this.sha256Hex,
    required this.byteSize,
    required this.width,
    required this.height,
    required this.format,
  }) {
    if (sha256Hex.length != 64) {
      throw ArgumentError.value(
        sha256Hex,
        'sha256Hex',
        'sha256Hex must be exactly 64 characters',
      );
    }
    for (var i = 0; i < 64; i++) {
      final code = sha256Hex.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39; // 0-9
      final isLowerHex = code >= 0x61 && code <= 0x66; // a-f
      if (!isDigit && !isLowerHex) {
        throw ArgumentError.value(
          sha256Hex,
          'sha256Hex',
          'sha256Hex must contain only lowercase hexadecimal characters (0-9, a-f)',
        );
      }
    }
    if (byteSize < 1 || byteSize > maxByteSize) {
      throw ArgumentError.value(
        byteSize,
        'byteSize',
        'byteSize must be between 1 and $maxByteSize bytes',
      );
    }
    if (width < 1 || width > maxLongestSidePx) {
      throw ArgumentError.value(
        width,
        'width',
        'width must be between 1 and $maxLongestSidePx pixels',
      );
    }
    if (height < 1 || height > maxLongestSidePx) {
      throw ArgumentError.value(
        height,
        'height',
        'height must be between 1 and $maxLongestSidePx pixels',
      );
    }
  }

  Map<String, Object> toMap() => {
        'sha256Hex': sha256Hex,
        'byteSize': byteSize,
        'width': width,
        'height': height,
        'format': format.name,
      };

  factory BlobRef.fromMap(Map<String, dynamic> map) {
    const expectedKeys = {'sha256Hex', 'byteSize', 'width', 'height', 'format'};
    if (map.length != 5 || !map.keys.every(expectedKeys.contains)) {
      throw const FormatException(
        'BlobRef.fromMap: map must contain exactly the 5 keys '
        '(sha256Hex, byteSize, width, height, format)',
      );
    }

    final rawSha = map['sha256Hex'];
    if (rawSha is! String) {
      throw const FormatException('BlobRef.fromMap: "sha256Hex" must be a String.');
    }

    final rawByteSize = map['byteSize'];
    if (rawByteSize is! int) {
      throw const FormatException('BlobRef.fromMap: "byteSize" must be an int.');
    }

    final rawWidth = map['width'];
    if (rawWidth is! int) {
      throw const FormatException('BlobRef.fromMap: "width" must be an int.');
    }

    final rawHeight = map['height'];
    if (rawHeight is! int) {
      throw const FormatException('BlobRef.fromMap: "height" must be an int.');
    }

    final rawFormat = map['format'];
    if (rawFormat is! String) {
      throw const FormatException('BlobRef.fromMap: "format" must be a String.');
    }

    final BlobFormat format;
    if (rawFormat == 'webp') {
      format = BlobFormat.webp;
    } else if (rawFormat == 'jpeg') {
      format = BlobFormat.jpeg;
    } else {
      throw FormatException(
        'BlobRef.fromMap: invalid format "$rawFormat". Expected "webp" or "jpeg".',
      );
    }

    try {
      return BlobRef(
        sha256Hex: rawSha,
        byteSize: rawByteSize,
        width: rawWidth,
        height: rawHeight,
        format: format,
      );
    } on ArgumentError catch (e) {
      throw FormatException('BlobRef.fromMap: invalid BlobRef arguments: ${e.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobRef &&
          sha256Hex == other.sha256Hex &&
          byteSize == other.byteSize &&
          width == other.width &&
          height == other.height &&
          format == other.format;

  @override
  int get hashCode => Object.hash(sha256Hex, byteSize, width, height, format);

  @override
  String toString() =>
      'BlobRef(${sha256Hex.substring(0, 8)}..., ${byteSize}B, ${width}x$height, ${format.name})';
}
