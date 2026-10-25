import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:vtt_engine_core/vtt_engine_core.dart';

void main() {
  group('BlobRef Tests', () {
    const validSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('B1 (shape): valid ref round-trips and boundaries are accepted', () {
      final ref = BlobRef(
        sha256Hex: validSha,
        byteSize: 1024,
        width: 1920,
        height: 1080,
        format: BlobFormat.webp,
      );

      final map = ref.toMap();
      final roundTripped = BlobRef.fromMap(map);
      expect(roundTripped, equals(ref));

      // Boundaries accepted
      expect(
        () => BlobRef(
          sha256Hex: validSha,
          byteSize: 1,
          width: 1,
          height: 1,
          format: BlobFormat.jpeg,
        ),
        returnsNormally,
      );
      expect(
        () => BlobRef(
          sha256Hex: validSha,
          byteSize: BlobRef.maxByteSize,
          width: 4096,
          height: 4096,
          format: BlobFormat.webp,
        ),
        returnsNormally,
      );

      // Constructor rejects with ArgumentError, fromMap rejects with FormatException
      final invalidCases = <({String sha, int byteSize, int width, int height})>[
        // hash 63 chars
        (sha: validSha.substring(0, 63), byteSize: 100, width: 100, height: 100),
        // hash 65 chars
        (sha: '${validSha}0', byteSize: 100, width: 100, height: 100),
        // hash with upper-case letter
        (sha: validSha.replaceRange(0, 1, 'A'), byteSize: 100, width: 100, height: 100),
        // hash containing 'g'
        (sha: validSha.replaceRange(0, 1, 'g'), byteSize: 100, width: 100, height: 100),
        // byteSize 0
        (sha: validSha, byteSize: 0, width: 100, height: 100),
        // byteSize -1
        (sha: validSha, byteSize: -1, width: 100, height: 100),
        // byteSize maxByteSize + 1
        (sha: validSha, byteSize: BlobRef.maxByteSize + 1, width: 100, height: 100),
        // width 0
        (sha: validSha, byteSize: 100, width: 0, height: 100),
        // width -1
        (sha: validSha, byteSize: 100, width: -1, height: 100),
        // width 4097
        (sha: validSha, byteSize: 100, width: 4097, height: 100),
        // height 0
        (sha: validSha, byteSize: 100, width: 100, height: 0),
        // height 4097
        (sha: validSha, byteSize: 100, width: 100, height: 4097),
      ];

      for (final c in invalidCases) {
        expect(
          () => BlobRef(
            sha256Hex: c.sha,
            byteSize: c.byteSize,
            width: c.width,
            height: c.height,
            format: BlobFormat.webp,
          ),
          throwsArgumentError,
          reason: 'Constructor must reject $c with ArgumentError',
        );

        final rawMap = {
          'sha256Hex': c.sha,
          'byteSize': c.byteSize,
          'width': c.width,
          'height': c.height,
          'format': 'webp',
        };
        expect(
          () => BlobRef.fromMap(rawMap),
          throwsA(isA<FormatException>()),
          reason: 'fromMap must reject $c with FormatException',
        );
      }

      // fromMap alone also rejects: each missing key
      for (final key in ['sha256Hex', 'byteSize', 'width', 'height', 'format']) {
        final missingMap = Map<String, dynamic>.from(map)..remove(key);
        expect(
          () => BlobRef.fromMap(missingMap),
          throwsA(isA<FormatException>()),
          reason: 'fromMap must reject missing key $key',
        );
      }

      // one extra key
      final extraKeyMap = Map<String, dynamic>.from(map)..['extra'] = 'unexpected';
      expect(
        () => BlobRef.fromMap(extraKeyMap),
        throwsA(isA<FormatException>()),
        reason: 'fromMap must reject extra key',
      );

      // byteSize: 10.5
      expect(
        () => BlobRef.fromMap({...map, 'byteSize': 10.5}),
        throwsA(isA<FormatException>()),
      );

      // byteSize: 10.0
      const bool onWeb = identical(0, 0.0);
      if (onWeb) {
        final refFromWeb = BlobRef.fromMap({...map, 'byteSize': 10.0});
        expect(refFromWeb.byteSize, equals(10));
      } else {
        expect(
          () => BlobRef.fromMap({...map, 'byteSize': 10.0}),
          throwsA(isA<FormatException>()),
        );
      }

      // width: "10"
      expect(
        () => BlobRef.fromMap({...map, 'width': '10'}),
        throwsA(isA<FormatException>()),
      );

      // height: null
      expect(
        () => BlobRef.fromMap({...map, 'height': null}),
        throwsA(isA<FormatException>()),
      );

      // formats png, svg, gif, WEBP, jpg, ""
      for (final badFormat in ['png', 'svg', 'gif', 'WEBP', 'jpg', '']) {
        expect(
          () => BlobRef.fromMap({...map, 'format': badFormat}),
          throwsA(isA<FormatException>()),
          reason: 'fromMap must reject format $badFormat',
        );
      }
    });

    test('B2 (law, seeded, at least 500 cases)', () {
      final rng = Random(42);
      const hexChars = '0123456789abcdef';

      String randomSha() {
        return List.generate(64, (_) => hexChars[rng.nextInt(16)]).join();
      }

      BlobRef randomRef() {
        return BlobRef(
          sha256Hex: randomSha(),
          byteSize: rng.nextInt(BlobRef.maxByteSize) + 1,
          width: rng.nextInt(BlobRef.maxLongestSidePx) + 1,
          height: rng.nextInt(BlobRef.maxLongestSidePx) + 1,
          format: rng.nextBool() ? BlobFormat.webp : BlobFormat.jpeg,
        );
      }

      for (var i = 0; i < 500; i++) {
        final a = randomRef();
        final b = randomRef();

        // fromMap(toMap(a)) == a
        expect(BlobRef.fromMap(a.toMap()), equals(a));

        // a == b exactly when toMap(a) equals toMap(b)
        final mapA = a.toMap();
        final mapB = b.toMap();
        final mapsEqual = mapA['sha256Hex'] == mapB['sha256Hex'] &&
            mapA['byteSize'] == mapB['byteSize'] &&
            mapA['width'] == mapB['width'] &&
            mapA['height'] == mapB['height'] &&
            mapA['format'] == mapB['format'];

        expect(a == b, equals(mapsEqual));
        if (a == b) {
          expect(a.hashCode, equals(b.hashCode));
        }

        // Self equality and hashCode
        final aCopy = BlobRef.fromMap(a.toMap());
        expect(a == aCopy, isTrue);
        expect(a.hashCode, equals(aCopy.hashCode));

        // Random maps test: fromMap either returns a ref or throws FormatException, never any other error type
        final randomMap = <String, dynamic>{};
        final keys = ['sha256Hex', 'byteSize', 'width', 'height', 'format', 'extra'];
        final numKeys = rng.nextInt(7);
        for (var k = 0; k < numKeys; k++) {
          final key = keys[rng.nextInt(keys.length)];
          final dynamic val;
          switch (rng.nextInt(6)) {
            case 0:
              val = randomSha();
            case 1:
              val = rng.nextInt(5000);
            case 2:
              val = rng.nextDouble() * 5000;
            case 3:
              val = rng.nextBool() ? 'webp' : 'jpeg';
            case 4:
              val = null;
            default:
              val = ['nested', rng.nextInt(10)];
          }
          randomMap[key] = val;
        }

        try {
          final res = BlobRef.fromMap(randomMap);
          expect(res, isA<BlobRef>());
        } on FormatException {
          // Expected for invalid payloads
        } catch (e, st) {
          fail('fromMap threw an unexpected error type (${e.runtimeType}): $e\n$st');
        }
      }
    });

    test('B3 (source bar): no image bytes in blob_ref.dart', testOn: 'vm', () {
      final file = File('lib/models/value_objects/blob_ref.dart');
      expect(file.existsSync(), isTrue, reason: 'blob_ref.dart must exist');
      final lines = file.readAsLinesSync();

      var foundFinalClass = false;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNum = i + 1;
        if (line.contains('Uint8List')) {
          fail('blob_ref.dart contains Uint8List on line $lineNum: $line');
        }
        if (line.contains('List<int>')) {
          fail('blob_ref.dart contains List<int> on line $lineNum: $line');
        }
        if (line.contains('ByteBuffer')) {
          fail('blob_ref.dart contains ByteBuffer on line $lineNum: $line');
        }
        if (line.contains('final class BlobRef')) {
          foundFinalClass = true;
        }
      }
      expect(foundFinalClass, isTrue,
          reason: 'blob_ref.dart must declare "final class BlobRef"');
    });
  });
}
