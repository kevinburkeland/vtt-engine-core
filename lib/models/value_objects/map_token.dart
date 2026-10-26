import 'package:meta/meta.dart';

enum MapTokenKind { character, monster, minion }

/// The identity of one token on one map image. Placed once, never changed.
@immutable
final class MapToken {
  static const int maxRefIdLength = 128;

  final String id; // 'tok_' + 32 lower-case hex characters
  final String mapSha256Hex; // the map this token was placed on
  final MapTokenKind kind; // what refId points at
  final String refId; // a partyRoster slug, an activeEncounter participantId, or an activeMinions id
  final String label; // 1 to 3 characters, each A-Z or 0-9

  MapToken({
    required this.id,
    required this.mapSha256Hex,
    required this.kind,
    required this.refId,
    required this.label,
  }) {
    if (id.length != 36 || !id.startsWith('tok_')) {
      throw ArgumentError.value(
        id,
        'id',
        'id must be 36 characters and start with "tok_"',
      );
    }
    for (var i = 4; i < 36; i++) {
      final code = id.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39; // 0-9
      final isLowerHex = code >= 0x61 && code <= 0x66; // a-f
      if (!isDigit && !isLowerHex) {
        throw ArgumentError.value(
          id,
          'id',
          'id must contain only lowercase hexadecimal characters (0-9, a-f) after "tok_"',
        );
      }
    }

    if (mapSha256Hex.length != 64) {
      throw ArgumentError.value(
        mapSha256Hex,
        'mapSha256Hex',
        'mapSha256Hex must be exactly 64 characters',
      );
    }
    for (var i = 0; i < 64; i++) {
      final code = mapSha256Hex.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39; // 0-9
      final isLowerHex = code >= 0x61 && code <= 0x66; // a-f
      if (!isDigit && !isLowerHex) {
        throw ArgumentError.value(
          mapSha256Hex,
          'mapSha256Hex',
          'mapSha256Hex must contain only lowercase hexadecimal characters (0-9, a-f)',
        );
      }
    }

    if (refId.isEmpty || refId.length > maxRefIdLength) {
      throw ArgumentError.value(
        refId,
        'refId',
        'refId must be between 1 and $maxRefIdLength characters',
      );
    }
    for (var i = 0; i < refId.length; i++) {
      final code = refId.codeUnitAt(i);
      if (code < 0x20 || code == 0x7F) {
        throw ArgumentError.value(
          refId,
          'refId',
          'refId must not contain control characters or DEL',
        );
      }
    }

    if (label.isEmpty || label.length > 3) {
      throw ArgumentError.value(
        label,
        'label',
        'label must be 1 to 3 characters long',
      );
    }
    for (var i = 0; i < label.length; i++) {
      final code = label.codeUnitAt(i);
      final isUpper = code >= 0x41 && code <= 0x5A; // A-Z
      final isDigit = code >= 0x30 && code <= 0x39; // 0-9
      if (!isUpper && !isDigit) {
        throw ArgumentError.value(
          label,
          'label',
          'label must contain only uppercase ASCII letters (A-Z) and digits (0-9)',
        );
      }
    }
  }

  Map<String, Object> toMap() => {
        'id': id,
        'mapSha256Hex': mapSha256Hex,
        'kind': kind.name,
        'refId': refId,
        'label': label,
      };

  factory MapToken.fromMap(Map<String, dynamic> map) {
    const expectedKeys = {
      'id',
      'mapSha256Hex',
      'kind',
      'refId',
      'label',
    };
    if (map.length != 5 || !map.keys.every(expectedKeys.contains)) {
      throw const FormatException(
        'MapToken.fromMap: map must contain exactly the 5 keys '
        '(id, mapSha256Hex, kind, refId, label)',
      );
    }

    final rawId = map['id'];
    if (rawId is! String) {
      throw const FormatException('MapToken.fromMap: "id" must be a String.');
    }

    final rawSha = map['mapSha256Hex'];
    if (rawSha is! String) {
      throw const FormatException('MapToken.fromMap: "mapSha256Hex" must be a String.');
    }

    final rawKind = map['kind'];
    if (rawKind is! String) {
      throw const FormatException('MapToken.fromMap: "kind" must be a String.');
    }
    final MapTokenKind kind;
    switch (rawKind) {
      case 'character':
        kind = MapTokenKind.character;
      case 'monster':
        kind = MapTokenKind.monster;
      case 'minion':
        kind = MapTokenKind.minion;
      default:
        throw const FormatException('MapToken.fromMap: "kind" must be character, monster, or minion.');
    }

    final rawRefId = map['refId'];
    if (rawRefId is! String) {
      throw const FormatException('MapToken.fromMap: "refId" must be a String.');
    }

    final rawLabel = map['label'];
    if (rawLabel is! String) {
      throw const FormatException('MapToken.fromMap: "label" must be a String.');
    }

    try {
      return MapToken(
        id: rawId,
        mapSha256Hex: rawSha,
        kind: kind,
        refId: rawRefId,
        label: rawLabel,
      );
    } on ArgumentError catch (e) {
      throw FormatException('MapToken.fromMap: invalid MapToken arguments: ${e.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapToken &&
          id == other.id &&
          mapSha256Hex == other.mapSha256Hex &&
          kind == other.kind &&
          refId == other.refId &&
          label == other.label;

  @override
  int get hashCode => Object.hash(
        id,
        mapSha256Hex,
        kind,
        refId,
        label,
      );

  @override
  String toString() {
    final prefix = id.length >= 8 ? id.substring(0, 8) : id;
    final mapPrefix = mapSha256Hex.length >= 8 ? mapSha256Hex.substring(0, 8) : mapSha256Hex;
    return 'MapToken($prefix..., ${kind.name}, $label, refId: $refId, map: $mapPrefix...)';
  }
}

/// A grid square, as column and row of the grid for the token's map.
@immutable
final class MapTokenCell {
  static const int minIndex = -1; // the partial square before the first line
  static const int maxIndex = 4095;

  final int col;
  final int row;

  MapTokenCell({
    required this.col,
    required this.row,
  }) {
    if (col < minIndex || col > maxIndex) {
      throw ArgumentError.value(
        col,
        'col',
        'col must be between $minIndex and $maxIndex',
      );
    }
    if (row < minIndex || row > maxIndex) {
      throw ArgumentError.value(
        row,
        'row',
        'row must be between $minIndex and $maxIndex',
      );
    }
  }

  Map<String, Object> toMap() => {
        'col': col,
        'row': row,
      };

  factory MapTokenCell.fromMap(Map<String, dynamic> map) {
    const expectedKeys = {'col', 'row'};
    if (map.length != 2 || !map.keys.every(expectedKeys.contains)) {
      throw const FormatException(
        'MapTokenCell.fromMap: map must contain exactly col and row',
      );
    }

    final rawCol = map['col'];
    if (rawCol is! int) {
      throw const FormatException('MapTokenCell.fromMap: "col" must be an int.');
    }

    final rawRow = map['row'];
    if (rawRow is! int) {
      throw const FormatException('MapTokenCell.fromMap: "row" must be an int.');
    }

    try {
      return MapTokenCell(
        col: rawCol,
        row: rawRow,
      );
    } on ArgumentError catch (e) {
      throw FormatException('MapTokenCell.fromMap: invalid MapTokenCell arguments: ${e.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapTokenCell && col == other.col && row == other.row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'MapTokenCell(col: $col, row: $row)';
}

/// A token with its current square, for one map.
@immutable
final class PlacedMapToken {
  final MapToken token;
  final MapTokenCell cell;

  PlacedMapToken({
    required this.token,
    required this.cell,
  }) {
    if (token.id.isEmpty) {
      throw ArgumentError.value(token, 'token', 'token must be valid');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacedMapToken && token == other.token && cell == other.cell;

  @override
  int get hashCode => Object.hash(token, cell);

  @override
  String toString() {
    final prefix = token.id.length >= 8 ? token.id.substring(0, 8) : token.id;
    return 'PlacedMapToken($prefix..., ${token.kind.name}, ${token.label}, col: ${cell.col}, row: ${cell.row})';
  }
}
