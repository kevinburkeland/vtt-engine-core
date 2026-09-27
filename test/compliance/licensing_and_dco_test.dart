import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Licensing and DCO Compliance Tests', () {
    test('LICENSE file exists and defines AGPLv3 with retroactive coverage', () {
      final licenseFile = File('LICENSE');
      expect(licenseFile.existsSync(), isTrue, reason: 'LICENSE file must exist in repo root');

      final content = licenseFile.readAsStringSync();
      expect(content, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      expect(content, contains('Version 3, 19 November 2007'));
      expect(content, contains('Copyright (C) 2026 Kevin Burkeland'));
      expect(content, contains('RETROACTIVE LICENSING SCOPE'));
      expect(content, contains('commit e5ecce3'));
      expect(content, contains('September 26, 2026'));
    });

    test('CONTRIBUTING.md exists, rejects CLA in favor of DCO, and mandates commit sign-off', () {
      final contributingFile = File('CONTRIBUTING.md');
      expect(contributingFile.existsSync(), isTrue, reason: 'CONTRIBUTING.md must exist in repo root');

      final content = contributingFile.readAsStringSync();
      expect(content, contains('Developer Certificate of Origin'));
      expect(content, contains('Version 1.1'));
      expect(content, contains('we deliberately do not use a Contributor License Agreement (CLA)'));
      expect(content, contains('git commit -s'));
      expect(content, contains('GNU Affero General Public License v3.0 (AGPL-3.0)'));
      expect(content, contains('Retroactive Licensing Scope'));
    });

    test('CODE_OF_CONDUCT.md exists and contains Contributor Covenant standards', () {
      final cocFile = File('CODE_OF_CONDUCT.md');
      expect(cocFile.existsSync(), isTrue, reason: 'CODE_OF_CONDUCT.md must exist in repo root');

      final content = cocFile.readAsStringSync();
      expect(content, contains('Contributor Covenant Code of Conduct'));
      expect(content, contains('Our Pledge'));
      expect(content, contains('Our Standards'));
    });

    test('README.md exists and references AGPL-3.0 license, DCO, and volatility disclaimer', () {
      final readmeFile = File('README.md');
      expect(readmeFile.existsSync(), isTrue, reason: 'README.md must exist in repo root');

      final content = readmeFile.readAsStringSync();
      expect(content, contains('AGPL-3.0'));
      expect(content, contains('Developer Certificate of Origin'));
      expect(content, contains('Retroactive Protection'));
      expect(content, contains('Decoupling from D&D is still actively in progress'));
      expect(content, contains('none of the internal structure'));
      expect(content, contains('Use at your own risk'));
    });

    test('.github/PULL_REQUEST_TEMPLATE.md exists and includes DCO sign-off check', () {
      final prTemplateFile = File('.github/PULL_REQUEST_TEMPLATE.md');
      expect(prTemplateFile.existsSync(), isTrue, reason: 'PULL_REQUEST_TEMPLATE.md must exist');

      final content = prTemplateFile.readAsStringSync();
      expect(content, contains('Developer Certificate of Origin (DCO)'));
      expect(content, contains('git commit -s'));
    });
  });
}
