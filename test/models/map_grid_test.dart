import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('MapGrid Model Tests (G1 - G3)', () {
    const validSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('G1 (shape): round trip, boundaries accepted and rejected', () {
      final base = MapGrid(
        mapSha256Hex: validSha,
        cellCentiPx: 5000,
        offsetXCentiPx: 100,
        offsetYCentiPx: 200,
        feetPerCell: 5,
        visible: true,
      );

      final map = base.toMap();
      final restored = MapGrid.fromMap(map);
      expect(restored, equals(base));
      expect(restored.mapSha256Hex, equals(validSha));
      expect(restored.cellCentiPx, equals(5000));
      expect(restored.offsetXCentiPx, equals(100));
      expect(restored.offsetYCentiPx, equals(200));
      expect(restored.feetPerCell, equals(5));
      expect(restored.visible, isTrue);

      // Boundaries accepted:
      // cellCentiPx 1,000 and 51,200
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 1000,
          offsetXCentiPx: 0,
          offsetYCentiPx: 0,
          feetPerCell: 5,
          visible: true,
        ).cellCentiPx,
        equals(1000),
      );
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 51200,
          offsetXCentiPx: 0,
          offsetYCentiPx: 0,
          feetPerCell: 5,
          visible: true,
        ).cellCentiPx,
        equals(51200),
      );

      // offsets 0 and cellCentiPx - 1
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 5000,
          offsetXCentiPx: 0,
          offsetYCentiPx: 4999,
          feetPerCell: 5,
          visible: true,
        ).offsetYCentiPx,
        equals(4999),
      );
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 5000,
          offsetXCentiPx: 4999,
          offsetYCentiPx: 0,
          feetPerCell: 5,
          visible: true,
        ).offsetXCentiPx,
        equals(4999),
      );

      // feetPerCell 1 and 100
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 5000,
          offsetXCentiPx: 0,
          offsetYCentiPx: 0,
          feetPerCell: 1,
          visible: false,
        ).feetPerCell,
        equals(1),
      );
      expect(
        MapGrid(
          mapSha256Hex: validSha,
          cellCentiPx: 5000,
          offsetXCentiPx: 0,
          offsetYCentiPx: 0,
          feetPerCell: 100,
          visible: true,
        ).feetPerCell,
        equals(100),
      );

      // Rejected by constructor (ArgumentError) and by fromMap (FormatException):
      final invalidCases = <Map<String, dynamic>>[
        // hash 63 chars
        {
          'mapSha256Hex': validSha.substring(0, 63),
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // hash 65 chars
        {
          'mapSha256Hex': '${validSha}a',
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // hash with uppercase letter
        {
          'mapSha256Hex': validSha.replaceRange(0, 1, 'E'),
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // hash with 'g'
        {
          'mapSha256Hex': validSha.replaceRange(0, 1, 'g'),
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // cellCentiPx 999
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 999,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // cellCentiPx 51201
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 51201,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // offset -1 (X axis)
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': -1,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // offset -1 (Y axis)
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': -1,
          'feetPerCell': 5,
          'visible': true,
        },
        // offset equal to cellCentiPx (X axis)
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': 5000,
          'offsetYCentiPx': 0,
          'feetPerCell': 5,
          'visible': true,
        },
        // offset equal to cellCentiPx (Y axis)
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 5000,
          'feetPerCell': 5,
          'visible': true,
        },
        // feetPerCell 0
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 0,
          'visible': true,
        },
        // feetPerCell 101
        {
          'mapSha256Hex': validSha,
          'cellCentiPx': 5000,
          'offsetXCentiPx': 0,
          'offsetYCentiPx': 0,
          'feetPerCell': 101,
          'visible': true,
        },
      ];

      for (final bad in invalidCases) {
        expect(
          () => MapGrid(
            mapSha256Hex: bad['mapSha256Hex'] as String,
            cellCentiPx: bad['cellCentiPx'] as int,
            offsetXCentiPx: bad['offsetXCentiPx'] as int,
            offsetYCentiPx: bad['offsetYCentiPx'] as int,
            feetPerCell: bad['feetPerCell'] as int,
            visible: bad['visible'] as bool,
          ),
          throwsArgumentError,
          reason: 'Constructor should reject: $bad',
        );
        expect(
          () => MapGrid.fromMap(bad),
          throwsFormatException,
          reason: 'fromMap should reject: $bad',
        );
      }

      // fromMap alone also rejects:
      // each missing key
      for (final key in [
        'mapSha256Hex',
        'cellCentiPx',
        'offsetXCentiPx',
        'offsetYCentiPx',
        'feetPerCell',
        'visible',
      ]) {
        final missing = Map<String, dynamic>.from(base.toMap())..remove(key);
        expect(
          () => MapGrid.fromMap(missing),
          throwsFormatException,
          reason: 'fromMap should reject missing key $key',
        );
      }

      // one extra key
      final extra = Map<String, dynamic>.from(base.toMap())..['extraKey'] = 123;
      expect(
        () => MapGrid.fromMap(extra),
        throwsFormatException,
        reason: 'fromMap should reject extra key',
      );

      // visible: 1
      final badVis1 = Map<String, dynamic>.from(base.toMap())..['visible'] = 1;
      expect(() => MapGrid.fromMap(badVis1), throwsFormatException);

      // visible: "true"
      final badVisStr = Map<String, dynamic>.from(base.toMap())..['visible'] = 'true';
      expect(() => MapGrid.fromMap(badVisStr), throwsFormatException);

      // feetPerCell: "5"
      final badFeetStr = Map<String, dynamic>.from(base.toMap())..['feetPerCell'] = '5';
      expect(() => MapGrid.fromMap(badFeetStr), throwsFormatException);

      // cellCentiPx: null
      final badCellNull = Map<String, dynamic>.from(base.toMap())..['cellCentiPx'] = null;
      expect(() => MapGrid.fromMap(badCellNull), throwsFormatException);
    });

    test('G2 (law, seeded, at least 500 cases)', () {
      final rng = Random(987654);

      String randomSha() {
        const hex = '0123456789abcdef';
        return List.generate(64, (_) => hex[rng.nextInt(16)]).join();
      }

      MapGrid randomGrid() {
        final cell = 1000 + rng.nextInt(51200 - 1000 + 1);
        final offX = rng.nextInt(cell);
        final offY = rng.nextInt(cell);
        final feet = 1 + rng.nextInt(100);
        final vis = rng.nextBool();
        return MapGrid(
          mapSha256Hex: randomSha(),
          cellCentiPx: cell,
          offsetXCentiPx: offX,
          offsetYCentiPx: offY,
          feetPerCell: feet,
          visible: vis,
        );
      }

      for (var i = 0; i < 500; i++) {
        final a = randomGrid();
        final b = randomGrid();

        // fromMap(toMap(a)) == a
        expect(MapGrid.fromMap(a.toMap()), equals(a));

        // a == b exactly when toMap(a) equals toMap(b)
        final mapA = a.toMap();
        final mapB = b.toMap();
        final mapsEqual = mapA.keys.every((k) => mapA[k] == mapB[k]);
        expect(a == b, equals(mapsEqual));

        // equal grids have equal hashCode
        if (a == b) {
          expect(a.hashCode, equals(b.hashCode));
        }

        final duplicateA = MapGrid.fromMap(mapA);
        expect(duplicateA.hashCode, equals(a.hashCode));

        // For random maps built from random keys and values of random types:
        final randomMap = <String, dynamic>{};
        final keyCount = rng.nextInt(10);
        for (var k = 0; k < keyCount; k++) {
          final key = rng.nextBool() ? ['mapSha256Hex', 'cellCentiPx', 'offsetXCentiPx', 'offsetYCentiPx', 'feetPerCell', 'visible'][rng.nextInt(6)] : 'random_key_$k';
          final type = rng.nextInt(5);
          dynamic val;
          switch (type) {
            case 0:
              val = rng.nextInt(60000) - 1000;
            case 1:
              val = rng.nextBool() ? randomSha() : 'bad_string';
            case 2:
              val = rng.nextBool();
            case 3:
              val = rng.nextDouble();
            case 4:
              val = null;
          }
          randomMap[key] = val;
        }

        try {
          final parsed = MapGrid.fromMap(randomMap);
          expect(parsed, isA<MapGrid>());
        } on FormatException {
          // Expected for malformed maps
        } catch (e) {
          fail('fromMap threw unexpected exception ${e.runtimeType}: $e');
        }
      }
    });

    test('G3 (source bar): map_grid.dart contains no double, num, List, Map field declarations and declares final class MapGrid', () {
      final file = File('lib/models/value_objects/map_grid.dart');
      expect(file.existsSync(), isTrue);
      final lines = file.readAsLinesSync();

      var foundFinalClass = false;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNum = i + 1;
        if (line.contains('final class MapGrid')) {
          foundFinalClass = true;
        }

        // Check for field declarations of double, num , List<, Map<String, dynamic>
        if (line.trim().startsWith('final ') || line.trim().startsWith('late final ')) {
          if (line.contains('double ') || line.contains('double?') ||
              line.contains('num ') || line.contains('num?') ||
              line.contains('List<') || line.contains('Map<')) {
            fail('Forbidden field type on line $lineNum: "$line"');
          }
        }
      }
      expect(foundFinalClass, isTrue, reason: 'Must declare final class MapGrid');

      // Control: run scanner on in-memory string with double field
      const badContent = '''
final class MapGrid {
  final double x;
}
''';
      var controlHit = false;
      for (final line in badContent.split('\n')) {
        if ((line.trim().startsWith('final ') || line.trim().startsWith('late final ')) &&
            line.contains('double ')) {
          controlHit = true;
          break;
        }
      }
      expect(controlHit, isTrue, reason: 'Control must catch double field');
    });
  });
}
