import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

List<String> scanTokenSource(String filename, String content) {
  final violations = <String>[];
  final lines = content.split('\n');

  var foundMapToken = false;
  var foundMapTokenCell = false;
  var foundPlacedMapToken = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineNum = i + 1;

    if (line.contains('final class MapToken ') || line.trim() == 'final class MapToken' || line.contains('final class MapToken{')) {
      foundMapToken = true;
    }
    if (line.contains('final class MapTokenCell ') || line.trim() == 'final class MapTokenCell' || line.contains('final class MapTokenCell{')) {
      foundMapTokenCell = true;
    }
    if (line.contains('final class PlacedMapToken ') || line.trim() == 'final class PlacedMapToken' || line.contains('final class PlacedMapToken{')) {
      foundPlacedMapToken = true;
    }

    final trimmed = line.trim();
    if (trimmed.startsWith('final ') || trimmed.startsWith('late final ')) {
      if (line.contains('double ') ||
          line.contains('double?') ||
          line.contains('num ') ||
          line.contains('num?') ||
          line.contains('List<') ||
          line.contains('Map<String, dynamic>')) {
        violations.add('$filename:$lineNum: forbidden field declaration: "$line"');
      }
    }
  }

  if (!foundMapToken) {
    violations.add('$filename: missing declaration "final class MapToken"');
  }
  if (!foundMapTokenCell) {
    violations.add('$filename: missing declaration "final class MapTokenCell"');
  }
  if (!foundPlacedMapToken) {
    violations.add('$filename: missing declaration "final class PlacedMapToken"');
  }

  return violations;
}

void main() {
  group('MapToken Model Tests (MT1 - MT3)', () {
    const validSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const validId = 'tok_0123456789abcdef0123456789abcdef';

    test('MT1 (shape): round trip, edge boundaries accepted and rejected', () {
      final token = MapToken(
        id: validId,
        mapSha256Hex: validSha,
        kind: MapTokenKind.character,
        refId: 'slug-hero',
        label: 'TO',
      );
      final cell = MapTokenCell(col: 10, row: 20);
      final placed = PlacedMapToken(token: token, cell: cell);

      expect(MapToken.fromMap(token.toMap()), equals(token));
      expect(MapTokenCell.fromMap(cell.toMap()), equals(cell));
      expect(placed.token, equals(token));
      expect(placed.cell, equals(cell));

      // toString checks
      expect(token.toString(), contains('tok_0123'));
      expect(token.toString(), contains('character'));
      expect(token.toString(), contains('TO'));
      expect(cell.toString(), equals('MapTokenCell(col: 10, row: 20)'));
      expect(placed.toString(), contains('tok_0123'));
      expect(placed.toString(), contains('col: 10, row: 20'));

      // Accepted at the edges:
      // labels: A, Z9, AB0
      for (final l in ['A', 'Z9', 'AB0']) {
        final t = MapToken(
          id: validId,
          mapSha256Hex: validSha,
          kind: MapTokenKind.monster,
          refId: 'r1',
          label: l,
        );
        expect(t.label, equals(l));
        expect(MapToken.fromMap(t.toMap()).label, equals(l));
      }

      // refId of 1 and 128 code units
      const ref1 = 'x';
      final ref128 = 'x' * 128;
      expect(
        MapToken(id: validId, mapSha256Hex: validSha, kind: MapTokenKind.minion, refId: ref1, label: 'M').refId,
        equals(ref1),
      );
      expect(
        MapToken(id: validId, mapSha256Hex: validSha, kind: MapTokenKind.minion, refId: ref128, label: 'M').refId,
        equals(ref128),
      );

      // col and row -1 and 4095
      for (final v in [-1, 4095]) {
        final cCol = MapTokenCell(col: v, row: 0);
        final cRow = MapTokenCell(col: 0, row: v);
        expect(cCol.col, equals(v));
        expect(cRow.row, equals(v));
        expect(MapTokenCell.fromMap(cCol.toMap()).col, equals(v));
        expect(MapTokenCell.fromMap(cRow.toMap()).row, equals(v));
      }

      // Rejected by constructor (ArgumentError) and fromMap (FormatException):
      void assertTokenRejected({
        String id = validId,
        String sha = validSha,
        MapTokenKind kind = MapTokenKind.character,
        String kindName = 'character',
        String refId = 'ref1',
        String label = 'T1',
      }) {
        expect(
          () => MapToken(id: id, mapSha256Hex: sha, kind: kind, refId: refId, label: label),
          throwsArgumentError,
        );
        expect(
          () => MapToken.fromMap({
            'id': id,
            'mapSha256Hex': sha,
            'kind': kindName,
            'refId': refId,
            'label': label,
          }),
          throwsFormatException,
        );
      }

      void assertCellRejected(int col, int row) {
        expect(() => MapTokenCell(col: col, row: row), throwsArgumentError);
        expect(
          () => MapTokenCell.fromMap({'col': col, 'row': row}),
          throwsFormatException,
        );
      }

      // id with 31 or 33 hex digits, upper-case hex, or without tok_
      assertTokenRejected(id: 'tok_${'a' * 31}');
      assertTokenRejected(id: 'tok_${'a' * 33}');
      assertTokenRejected(id: 'tok_${'A' * 32}');
      assertTokenRejected(id: 'tok_${'g' * 32}');
      assertTokenRejected(id: 'abc_${'a' * 32}');
      assertTokenRejected(id: 'a' * 36);

      // each MapGrid hash failure
      assertTokenRejected(sha: 'a' * 63);
      assertTokenRejected(sha: 'a' * 65);
      assertTokenRejected(sha: 'A' * 64);
      assertTokenRejected(sha: '${'a' * 63}g');

      // refId empty, 129 code units, containing \n, containing \u007F
      assertTokenRejected(refId: '');
      assertTokenRejected(refId: 'a' * 129);
      assertTokenRejected(refId: 'a\nb');
      assertTokenRejected(refId: 'a\u007Fb');

      // label empty, ab, ABCD, A B, É, -
      assertTokenRejected(label: '');
      assertTokenRejected(label: 'ab');
      assertTokenRejected(label: 'ABCD');
      assertTokenRejected(label: 'A B');
      assertTokenRejected(label: 'É');
      assertTokenRejected(label: '-');

      // col or row -2 or 4096
      assertCellRejected(-2, 0);
      assertCellRejected(0, -2);
      assertCellRejected(4096, 0);
      assertCellRejected(0, 4096);

      // fromMap alone also rejects:
      // each missing key
      final fullTokenMap = {
        'id': validId,
        'mapSha256Hex': validSha,
        'kind': 'character',
        'refId': 'ref1',
        'label': 'A',
      };
      for (final k in fullTokenMap.keys) {
        final m = Map<String, dynamic>.from(fullTokenMap)..remove(k);
        expect(() => MapToken.fromMap(m), throwsFormatException);
      }

      // one extra key
      final extraTokenMap = Map<String, dynamic>.from(fullTokenMap)..['extra'] = 'val';
      expect(() => MapToken.fromMap(extraTokenMap), throwsFormatException);

      // kind: "npc", kind: 0
      final badKindMap1 = Map<String, dynamic>.from(fullTokenMap)..['kind'] = 'npc';
      expect(() => MapToken.fromMap(badKindMap1), throwsFormatException);
      final badKindMap2 = Map<String, dynamic>.from(fullTokenMap)..['kind'] = 0;
      expect(() => MapToken.fromMap(badKindMap2), throwsFormatException);

      // Cell fromMap: missing key, extra key, col: "3", col: null
      expect(() => MapTokenCell.fromMap({'col': 0}), throwsFormatException);
      expect(() => MapTokenCell.fromMap({'row': 0}), throwsFormatException);
      expect(() => MapTokenCell.fromMap({'col': 0, 'row': 0, 'extra': 1}), throwsFormatException);
      expect(() => MapTokenCell.fromMap({'col': '3', 'row': 0}), throwsFormatException);
      expect(() => MapTokenCell.fromMap({'col': null, 'row': 0}), throwsFormatException);
    });

    test('MT2 (law, seeded, at least 500 cases)', () {
      final rng = Random(42);
      const hexChars = '0123456789abcdef';
      const labelChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

      String randomHex(int len) =>
          List.generate(len, (_) => hexChars[rng.nextInt(hexChars.length)]).join();

      String randomLabel() =>
          List.generate(rng.nextInt(3) + 1, (_) => labelChars[rng.nextInt(labelChars.length)]).join();

      MapToken randomToken() {
        return MapToken(
          id: 'tok_${randomHex(32)}',
          mapSha256Hex: randomHex(64),
          kind: MapTokenKind.values[rng.nextInt(MapTokenKind.values.length)],
          refId: 'ref_${rng.nextInt(1000)}',
          label: randomLabel(),
        );
      }

      MapTokenCell randomCell() {
        return MapTokenCell(
          col: rng.nextInt(4097) - 1,
          row: rng.nextInt(4097) - 1,
        );
      }

      for (var i = 0; i < 500; i++) {
        final aToken = randomToken();
        final bToken = randomToken();

        expect(MapToken.fromMap(aToken.toMap()), equals(aToken));
        expect(aToken == bToken, equals(aToken.id == bToken.id &&
            aToken.mapSha256Hex == bToken.mapSha256Hex &&
            aToken.kind == bToken.kind &&
            aToken.refId == bToken.refId &&
            aToken.label == bToken.label));
        if (aToken == bToken) {
          expect(aToken.hashCode, equals(bToken.hashCode));
        }

        final aCell = randomCell();
        final bCell = randomCell();

        expect(MapTokenCell.fromMap(aCell.toMap()), equals(aCell));
        expect(aCell == bCell, equals(aCell.col == bCell.col && aCell.row == bCell.row));
        if (aCell == bCell) {
          expect(aCell.hashCode, equals(bCell.hashCode));
        }

        final aPlaced = PlacedMapToken(token: aToken, cell: aCell);
        final bPlaced = PlacedMapToken(token: bToken, cell: bCell);
        expect(aPlaced == bPlaced, equals(aToken == bToken && aCell == bCell));
        if (aPlaced == bPlaced) {
          expect(aPlaced.hashCode, equals(bPlaced.hashCode));
        }

        // Random maps test: returns a value or throws FormatException, never another error
        final randMap = <String, dynamic>{};
        final keys = ['id', 'mapSha256Hex', 'kind', 'refId', 'label', 'extra', 'col', 'row'];
        final keyCount = rng.nextInt(6);
        for (var k = 0; k < keyCount; k++) {
          final key = keys[rng.nextInt(keys.length)];
          final valChoice = rng.nextInt(4);
          dynamic val;
          if (valChoice == 0) val = 'tok_${randomHex(32)}';
          if (valChoice == 1) val = rng.nextInt(5000);
          if (valChoice == 2) val = rng.nextBool();
          if (valChoice == 3) val = null;
          randMap[key] = val;
        }

        try {
          MapToken.fromMap(randMap);
        } on FormatException {
          // Expected for bad maps
        } catch (e) {
          fail('MapToken.fromMap threw unexpected error: $e');
        }

        try {
          MapTokenCell.fromMap(randMap);
        } on FormatException {
          // Expected for bad maps
        } catch (e) {
          fail('MapTokenCell.fromMap threw unexpected error: $e');
        }
      }
    });

    test('MT3 (source bar)', testOn: 'vm', () {
      final file = File('lib/models/value_objects/map_token.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      final violations = scanTokenSource(file.path, content);
      expect(violations, isEmpty, reason: violations.join('\n'));

      // Control check: in-memory string with double field
      const badContent = '''
final class MapToken {
  final double forbidden;
}
final class MapTokenCell {}
final class PlacedMapToken {}
''';
      final controlViolations = scanTokenSource('control_test.dart', badContent);
      expect(
        controlViolations.length,
        equals(1),
        reason: 'Control check must detect forbidden double field',
      );
      expect(controlViolations.first, contains('control_test.dart:2'));
    });
  });
}
