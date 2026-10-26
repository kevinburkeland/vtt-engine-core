@TestOn('vm')
library;

import 'dart:io';
import 'package:test/test.dart';

String _getDirname(String filePath) {
  final idx = filePath.lastIndexOf('/');
  if (idx == -1) return '.';
  if (idx == 0) return '/';
  return filePath.substring(0, idx);
}

String _joinAndNormalize(String dir, String rel) {
  final combined = (dir == '.' || dir.isEmpty) ? rel : '$dir/$rel';
  final isAbsolute = combined.startsWith('/');
  final segments = <String>[];
  for (final part in combined.split('/')) {
    if (part == '' || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else {
        segments.add('..');
      }
    } else {
      segments.add(part);
    }
  }
  final res = segments.join('/');
  if (isAbsolute) return '/$res';
  return res.isEmpty ? '.' : res;
}

List<String> findMarkdownFiles(String repoRoot) {
  final rootDir = Directory(repoRoot);
  final skipNames = {'.git', '.dart_tool', 'build', 'ephemeral', 'node_modules'};
  final results = <String>[];

  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      final p = entity.path.replaceAll('\\', '/');
      final segs = p.split('/');
      if (segs.any((s) => skipNames.contains(s))) continue;
      if (p.contains('test/fixtures')) continue;
      if (entity is Directory) {
        walk(entity);
      } else if (entity is File) {
        var rel = p.startsWith('./') ? p.substring(2) : p;
        if (repoRoot != '.' && repoRoot.isNotEmpty && rel.startsWith('$repoRoot/')) {
          rel = rel.substring(repoRoot.length + 1);
        }
        if (rel.startsWith('./')) rel = rel.substring(2);
        if (rel.endsWith('.md') || rel.endsWith('.antigravityrules')) {
          results.add(rel);
        }
      }
    }
  }

  walk(rootDir);
  results.sort();
  return results;
}

List<String> markdownLinkProblems(String markdown, String fileDir) {
  // 1. Strip fenced code blocks (``` or ~~~) line by line
  final lines = markdown.split('\n');
  final withoutFencesLines = <String>[];
  bool inFence = false;
  String fenceChar = '';
  int fenceLen = 0;

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (!inFence) {
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = true;
        fenceChar = trimmed[0];
        fenceLen = 0;
        while (fenceLen < trimmed.length && trimmed[fenceLen] == fenceChar) {
          fenceLen++;
        }
        continue;
      }
      withoutFencesLines.add(line);
    } else {
      if (trimmed.startsWith(fenceChar * fenceLen)) {
        inFence = false;
      }
    }
  }
  final withoutFences = withoutFencesLines.join('\n');

  // 2. Strip inline code (`code` or ``code``)
  final codePattern = RegExp(r'`+[^`\n]+`+');
  final cleanMarkdown = withoutFences.replaceAll(codePattern, '');

  final problems = <String>[];

  void checkTarget(String label, String rawTarget) {
    var t = rawTarget.trim();
    if (t.startsWith('<') && t.endsWith('>')) {
      t = t.substring(1, t.length - 1).trim();
    }
    final titleMatch = RegExp(r'''^(\S+)(?:\s+["'].*?["'])?$''').firstMatch(t);
    if (titleMatch != null) {
      t = titleMatch.group(1)!;
    }

    final lower = t.toLowerCase();
    if (lower.startsWith('file:')) {
      problems.add('$label($t): file: scheme is forbidden');
      return;
    }
    if (lower.startsWith('http:') || lower.startsWith('https:') || lower.startsWith('mailto:')) {
      return;
    }
    if (t.startsWith('#')) {
      return;
    }
    if (t.startsWith('/')) {
      problems.add('$label($t): leading slash is forbidden');
      return;
    }

    var targetPath = t.split('#').first.split('?').first;
    try {
      targetPath = Uri.decodeComponent(targetPath);
    } catch (_) {}
    if (targetPath.isEmpty) return;

    final resolved = _joinAndNormalize(fileDir, targetPath);
    if (!File(resolved).existsSync() && !Directory(resolved).existsSync()) {
      problems.add('$label($t): target does not exist: $resolved');
    }
  }

  // Reference definitions: ^[id]: target (excluding footnote definitions)
  final refDefPattern = RegExp(r'^[ \t]*\[([^\]]+)\]:[ \t]*([^\s]+)', multiLine: true);
  for (final m in refDefPattern.allMatches(cleanMarkdown)) {
    final ref = m.group(1)!;
    if (ref.startsWith('^')) {
      continue;
    }
    checkTarget('[$ref]', m.group(2)!);
  }

  // Autolinks: <scheme:...>
  final autolinkPattern = RegExp(r'<([a-zA-Z][a-zA-Z0-9+.-]*:[^>\s]+)>');
  for (final m in autolinkPattern.allMatches(cleanMarkdown)) {
    final target = m.group(1)!;
    checkTarget('<$target>', target);
  }

  // Inline links and images: find every ](target)
  final targetPattern = RegExp(r'\]\(([^)\n]+)\)');
  for (final m in targetPattern.allMatches(cleanMarkdown)) {
    final target = m.group(1)!;
    final closeBracketIdx = m.start;

    int depth = 1;
    int idx = closeBracketIdx - 1;
    int startBracketIdx = -1;

    while (idx >= 0) {
      final ch = cleanMarkdown[idx];
      if (ch == '\n') break;
      if (ch == ']') {
        depth++;
      } else if (ch == '[') {
        depth--;
        if (depth == 0) {
          startBracketIdx = idx;
          break;
        }
      }
      idx--;
    }

    String label;
    if (startBracketIdx != -1) {
      if (startBracketIdx > 0 && cleanMarkdown[startBracketIdx - 1] == '!') {
        label = cleanMarkdown.substring(startBracketIdx - 1, closeBracketIdx + 1);
      } else {
        label = cleanMarkdown.substring(startBracketIdx, closeBracketIdx + 1);
      }
    } else {
      label = '[link]';
    }

    checkTarget(label, target);
  }

  // HTML src and href attributes
  final htmlPattern = RegExp(r'''\b(?:src|href)=["']([^"']+)["']''', caseSensitive: false);
  for (final m in htmlPattern.allMatches(cleanMarkdown)) {
    checkTarget('[<HTML>]', m.group(1)!);
  }

  return problems;
}

void main() {
  group('Markdown Link Checks', () {
    test('MLC1: real check on all repository markdown files and .antigravityrules', () {
      final files = findMarkdownFiles('.');
      expect(files, contains('README.md'));
      expect(files, contains('AGENTS.md'));
      expect(files, contains('CONTRIBUTING.md'));
      expect(files, contains('.antigravityrules'));
      expect(files, contains('.github/PULL_REQUEST_TEMPLATE.md'));

      final allProblems = <String>[];
      for (final filePath in files) {
        final content = File(filePath).readAsStringSync();
        final fileDir = _getDirname(filePath);
        final problems = markdownLinkProblems(content, fileDir);
        if (problems.isNotEmpty) {
          allProblems.add('$filePath problems:\n  ${problems.join('\n  ')}');
        }
      }

      expect(allProblems, isEmpty,
          reason: 'Found markdown link problems in repository:\n${allProblems.join('\n')}');
    });

    test('MLC2: cases with strings and temporary directory', () {
      final tempDir = Directory.systemTemp.createTempSync('mlc2_cases_');
      try {
        File('${tempDir.path}/good.txt').writeAsStringSync('good');
        File('${tempDir.path}/good.png').writeAsStringSync('png');

        // a missing file
        final missingRes = markdownLinkProblems('[missing](missing.txt)', tempDir.path);
        expect(missingRes, hasLength(1));
        expect(missingRes.first, contains('missing.txt'));

        // a file: link
        final fileRes = markdownLinkProblems('[local](file:///etc/hosts)', tempDir.path);
        expect(fileRes, hasLength(1));
        expect(fileRes.first, contains('file:'));

        // an uppercase FILE: link
        final upperRes = markdownLinkProblems('[a](FILE:///x)', tempDir.path);
        expect(upperRes, hasLength(1));
        expect(upperRes.first, contains('file:'));
        expect(markdownLinkProblems('[a](HTTPS://example.com)', tempDir.path), isEmpty);

        // three badge cases
        final badgeMissingLicense = markdownLinkProblems(
          '[![b](https://x/y.svg)](MISSING_LICENSE)',
          tempDir.path,
        );
        expect(badgeMissingLicense, hasLength(1));
        expect(badgeMissingLicense.first, contains('MISSING_LICENSE'));

        expect(
          markdownLinkProblems('[![b](good.png)](good.txt)', tempDir.path),
          isEmpty,
        );

        final badgeMissingImg = markdownLinkProblems(
          '[![b](missing.png)](good.txt)',
          tempDir.path,
        );
        expect(badgeMissingImg, hasLength(1));
        expect(badgeMissingImg.first, contains('missing.png'));

        // a footnote
        expect(
          markdownLinkProblems('[^1]: Some text here.\nSee this[^1].', tempDir.path),
          isEmpty,
        );

        // two autolink cases
        final autoFile = markdownLinkProblems('<file:///x>', tempDir.path);
        expect(autoFile, hasLength(1));
        expect(autoFile.first, contains('file:'));
        expect(markdownLinkProblems('<https://example.com>', tempDir.path), isEmpty);

        // a link in a code fence (ignored)
        const fencedSample = '''
```
[ignored](missing.txt)
```
''';
        expect(markdownLinkProblems(fencedSample, tempDir.path), isEmpty);

        // two links on one line
        final twoOnOneLine = markdownLinkProblems(
          '[a](good.txt) and [b](missing.txt)',
          tempDir.path,
        );
        expect(twoOnOneLine, hasLength(1));
        expect(twoOnOneLine.first, contains('missing.txt'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
