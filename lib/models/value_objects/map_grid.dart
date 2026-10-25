import 'package:meta/meta.dart';

/// A square grid lined up on one shared map image. All lengths are in
/// hundredths of a pixel of that image (the shared, re-encoded copy).
@immutable
final class MapGrid {
  static const int minCellCentiPx = 1000;   // 10 px
  static const int maxCellCentiPx = 51200;  // 512 px
  static const int maxFeetPerCell = 100;

  final String mapSha256Hex;   // the map this grid was lined up on
  final int cellCentiPx;       // side of one square
  final int offsetXCentiPx;    // where the first vertical line sits, 0 <= x < cellCentiPx
  final int offsetYCentiPx;    // where the first horizontal line sits, 0 <= y < cellCentiPx
  final int feetPerCell;       // 1..maxFeetPerCell, default 5 in the UI
  final bool visible;          // false = the DM hid it; the ruler is off too

  MapGrid({
    required this.mapSha256Hex,
    required this.cellCentiPx,
    required this.offsetXCentiPx,
    required this.offsetYCentiPx,
    required this.feetPerCell,
    required this.visible,
  }) {
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
    if (cellCentiPx < minCellCentiPx || cellCentiPx > maxCellCentiPx) {
      throw ArgumentError.value(
        cellCentiPx,
        'cellCentiPx',
        'cellCentiPx must be between $minCellCentiPx and $maxCellCentiPx centipixels',
      );
    }
    if (offsetXCentiPx < 0 || offsetXCentiPx >= cellCentiPx) {
      throw ArgumentError.value(
        offsetXCentiPx,
        'offsetXCentiPx',
        'offsetXCentiPx must be between 0 and ${cellCentiPx - 1} centipixels',
      );
    }
    if (offsetYCentiPx < 0 || offsetYCentiPx >= cellCentiPx) {
      throw ArgumentError.value(
        offsetYCentiPx,
        'offsetYCentiPx',
        'offsetYCentiPx must be between 0 and ${cellCentiPx - 1} centipixels',
      );
    }
    if (feetPerCell < 1 || feetPerCell > maxFeetPerCell) {
      throw ArgumentError.value(
        feetPerCell,
        'feetPerCell',
        'feetPerCell must be between 1 and $maxFeetPerCell',
      );
    }
  }

  Map<String, Object> toMap() => {
        'mapSha256Hex': mapSha256Hex,
        'cellCentiPx': cellCentiPx,
        'offsetXCentiPx': offsetXCentiPx,
        'offsetYCentiPx': offsetYCentiPx,
        'feetPerCell': feetPerCell,
        'visible': visible,
      };

  factory MapGrid.fromMap(Map<String, dynamic> map) {
    const expectedKeys = {
      'mapSha256Hex',
      'cellCentiPx',
      'offsetXCentiPx',
      'offsetYCentiPx',
      'feetPerCell',
      'visible',
    };
    if (map.length != 6 || !map.keys.every(expectedKeys.contains)) {
      throw const FormatException(
        'MapGrid.fromMap: map must contain exactly the 6 keys '
        '(mapSha256Hex, cellCentiPx, offsetXCentiPx, offsetYCentiPx, feetPerCell, visible)',
      );
    }

    final rawSha = map['mapSha256Hex'];
    if (rawSha is! String) {
      throw const FormatException('MapGrid.fromMap: "mapSha256Hex" must be a String.');
    }

    final rawCell = map['cellCentiPx'];
    if (rawCell is! int) {
      throw const FormatException('MapGrid.fromMap: "cellCentiPx" must be an int.');
    }

    final rawOffsetX = map['offsetXCentiPx'];
    if (rawOffsetX is! int) {
      throw const FormatException('MapGrid.fromMap: "offsetXCentiPx" must be an int.');
    }

    final rawOffsetY = map['offsetYCentiPx'];
    if (rawOffsetY is! int) {
      throw const FormatException('MapGrid.fromMap: "offsetYCentiPx" must be an int.');
    }

    final rawFeet = map['feetPerCell'];
    if (rawFeet is! int) {
      throw const FormatException('MapGrid.fromMap: "feetPerCell" must be an int.');
    }

    final rawVisible = map['visible'];
    if (rawVisible is! bool) {
      throw const FormatException('MapGrid.fromMap: "visible" must be a bool.');
    }

    try {
      return MapGrid(
        mapSha256Hex: rawSha,
        cellCentiPx: rawCell,
        offsetXCentiPx: rawOffsetX,
        offsetYCentiPx: rawOffsetY,
        feetPerCell: rawFeet,
        visible: rawVisible,
      );
    } on ArgumentError catch (e) {
      throw FormatException('MapGrid.fromMap: invalid MapGrid arguments: ${e.message}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapGrid &&
          mapSha256Hex == other.mapSha256Hex &&
          cellCentiPx == other.cellCentiPx &&
          offsetXCentiPx == other.offsetXCentiPx &&
          offsetYCentiPx == other.offsetYCentiPx &&
          feetPerCell == other.feetPerCell &&
          visible == other.visible;

  @override
  int get hashCode => Object.hash(
        mapSha256Hex,
        cellCentiPx,
        offsetXCentiPx,
        offsetYCentiPx,
        feetPerCell,
        visible,
      );

  @override
  String toString() {
    final prefix = mapSha256Hex.length >= 8 ? mapSha256Hex.substring(0, 8) : mapSha256Hex;
    return 'MapGrid($prefix..., cell: $cellCentiPx cpx, offset: ($offsetXCentiPx, $offsetYCentiPx) cpx, ${feetPerCell}ft, visible: $visible)';
  }
}
