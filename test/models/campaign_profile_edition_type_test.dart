import 'dart:io';
import 'package:test/test.dart';
import 'package:vtt_engine_core/models/campaign_profile.dart';
import 'package:vtt_engine_core/rules/ruleset_edition.dart';

void main() {
  group('CampaignProfile Edition Type & RulesetRef (Cold Iron Pass 12)', () {
    test('C1: profile built with RulesetIdentifier retains rulesetId, copyWith updates it, and join handles equal vs unequal', () {
      final p1 = CampaignProfile.initial(
        id: 'camp_c1_a',
        name: 'Camp C1 A',
        edition: const RulesetIdentifier('x'),
        nodeId: 'node-c1',
      );
      expect(p1.rulesetId, equals('x'));

      final p1Updated = p1.copyWith(rulesetId: 'y');
      expect(p1Updated.rulesetId, equals('y'));

      final p2 = CampaignProfile.initial(
        id: 'camp_c1_a',
        name: 'Camp C1 B',
        edition: const RulesetIdentifier('x'),
        nodeId: 'node-c1',
      );
      final joinedEqual = CampaignProfile.join(p1, p2);
      expect(joinedEqual.rulesetId, equals('x'));

      final p3 = CampaignProfile.initial(
        id: 'camp_c1_a',
        name: 'Camp C1 C',
        edition: const RulesetIdentifier('different_ruleset'),
        nodeId: 'node-c1',
      );
      expect(
        () => CampaignProfile.join(p1, p3),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Incompatible ruleset edition'),
        )),
      );
    });

    test('C2 (source bar): lib/models/campaign_profile.dart contains zero dynamic tokens', () {
      final file = File('lib/models/campaign_profile.dart');
      expect(file.existsSync(), isTrue, reason: 'lib/models/campaign_profile.dart must exist');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
          continue;
        }
        final dynamicTokenRegex = RegExp(r'\bdynamic\b');
        if (dynamicTokenRegex.hasMatch(line)) {
          fail('Forbidden token "dynamic" found in lib/models/campaign_profile.dart at line ${i + 1}: "$line"');
        }
      }
    });
  });
}
