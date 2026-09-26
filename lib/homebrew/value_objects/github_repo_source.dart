import 'package:meta/meta.dart';

/// Immutable Value Object representing a sanitized GitHub repository source.
///
/// Ensures zero Flutter dependencies and encapsulates URL parsing,
/// branch extraction, and API / Raw content URI resolution.
@immutable
class GithubRepoSource {
  final String owner;
  final String repo;
  final String branch;

  const GithubRepoSource({
    required this.owner,
    required this.repo,
    this.branch = 'main',
  });

  /// Parses and sanitizes a raw repository URL.
  ///
  /// Supported formats:
  /// - `https://github.com/owner/repo`
  /// - `https://github.com/owner/repo.git`
  /// - `https://github.com/owner/repo/tree/branch-name`
  /// - `https://github.com/owner/repo/tree/branch-name/sub/path`
  ///
  /// Throws [FormatException] if the URL is invalid, not from github.com,
  /// or missing required owner/repo segments.
  factory GithubRepoSource.parse(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Repository URL cannot be empty.');
    }

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      throw FormatException('Invalid URL structure: $e');
    }

    final host = uri.host.toLowerCase();
    if (host != 'github.com' && host != 'www.github.com') {
      throw FormatException(
        'Invalid repository host: "$host". Only "github.com" repositories are supported.',
      );
    }

    // Path segments: ignore empty parts
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) {
      throw const FormatException(
        'GitHub URL must contain at least owner and repository name (e.g., https://github.com/owner/repo).',
      );
    }

    final owner = segments[0];
    var repo = segments[1];
    if (repo.endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }

    if (owner.isEmpty || repo.isEmpty) {
      throw const FormatException(
          'Repository owner and name must not be empty.');
    }

    String branch = 'main';
    // Check for /tree/:branch pattern
    if (segments.length >= 4 && segments[2] == 'tree') {
      branch = segments[3];
    }

    return GithubRepoSource(
      owner: owner,
      repo: repo,
      branch: branch,
    );
  }

  /// GitHub Git Trees API URI for recursively listing repository contents.
  Uri get apiTreeUri => Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
      );

  /// Raw content base URI for downloading file blobs.
  Uri get rawContentBaseUri => Uri.parse(
        'https://raw.githubusercontent.com/$owner/$repo/$branch/',
      );

  /// Resolves the raw content download URI for a relative file path in the repository.
  Uri rawFileUri(String relativePath) {
    final sanitizedPath =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return Uri.parse(
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$sanitizedPath');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GithubRepoSource &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          repo == other.repo &&
          branch == other.branch;

  @override
  int get hashCode => Object.hash(owner, repo, branch);

  @override
  String toString() => 'GithubRepoSource($owner/$repo@$branch)';
}
