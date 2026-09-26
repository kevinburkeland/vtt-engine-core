import 'package:test/test.dart';
import 'package:vtt_engine_core/homebrew/value_objects/github_repo_source.dart';

void main() {
  group('GithubRepoSource Value Object Tests', () {
    test('Parses standard GitHub repository URL', () {
      final source = GithubRepoSource.parse(
          'https://github.com/DnD-Brewers/spells-compendium');
      expect(source.owner, equals('DnD-Brewers'));
      expect(source.repo, equals('spells-compendium'));
      expect(source.branch, equals('main'));
      expect(
        source.apiTreeUri.toString(),
        equals(
            'https://api.github.com/repos/DnD-Brewers/spells-compendium/git/trees/main?recursive=1'),
      );
      expect(
        source.rawContentBaseUri.toString(),
        equals(
            'https://raw.githubusercontent.com/DnD-Brewers/spells-compendium/main/'),
      );
    });

    test('Strips .git suffix correctly', () {
      final source = GithubRepoSource.parse(
          'https://github.com/dnd-brewers/campaign-setting.git');
      expect(source.owner, equals('dnd-brewers'));
      expect(source.repo, equals('campaign-setting'));
      expect(source.branch, equals('main'));
    });

    test('Parses custom branch from /tree/:branch path', () {
      final source = GithubRepoSource.parse(
          'https://github.com/tabletop-vault/vault/tree/v2-development');
      expect(source.owner, equals('tabletop-vault'));
      expect(source.repo, equals('vault'));
      expect(source.branch, equals('v2-development'));
      expect(
        source.apiTreeUri.toString(),
        equals(
            'https://api.github.com/repos/tabletop-vault/vault/git/trees/v2-development?recursive=1'),
      );
      expect(
        source.rawFileUri('monsters/aberration.json').toString(),
        equals(
            'https://raw.githubusercontent.com/tabletop-vault/vault/v2-development/monsters/aberration.json'),
      );
    });

    test('Handles subpaths after /tree/:branch correctly', () {
      final source = GithubRepoSource.parse(
          'https://github.com/archmage/5e-content/tree/dev/packs/core');
      expect(source.owner, equals('archmage'));
      expect(source.repo, equals('5e-content'));
      expect(source.branch, equals('dev'));
    });

    test('Rejects non-github domains with FormatException', () {
      expect(
        () => GithubRepoSource.parse('https://gitlab.com/dnd/spells'),
        throwsFormatException,
      );
      expect(
        () => GithubRepoSource.parse('https://bitbucket.org/dnd/spells'),
        throwsFormatException,
      );
    });

    test('Rejects incomplete or malformed URLs with FormatException', () {
      expect(() => GithubRepoSource.parse(''), throwsFormatException);
      expect(() => GithubRepoSource.parse('   '), throwsFormatException);
      expect(() => GithubRepoSource.parse('https://github.com'),
          throwsFormatException);
      expect(() => GithubRepoSource.parse('https://github.com/owner-only'),
          throwsFormatException);
    });

    test('Value equality and toString tests', () {
      final src1 = GithubRepoSource.parse('https://github.com/dnd/core');
      const src2 = GithubRepoSource(owner: 'dnd', repo: 'core', branch: 'main');
      const src3 = GithubRepoSource(owner: 'dnd', repo: 'core', branch: 'dev');

      expect(src1, equals(src2));
      expect(src1.hashCode, equals(src2.hashCode));
      expect(src1, isNot(equals(src3)));
      expect(src1.toString(), equals('GithubRepoSource(dnd/core@main)'));
    });
  });
}
