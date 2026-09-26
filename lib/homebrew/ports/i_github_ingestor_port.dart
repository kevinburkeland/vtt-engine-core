import 'package:meta/meta.dart';
import '../models/homebrew_entity.dart';
import '../value_objects/github_repo_source.dart';
import '../value_objects/ruleset_version.dart';

/// Base class for all ingestion stream outcomes.
@immutable
abstract class IngestionResult {
  final String sourceUrl;
  final RulesetVersion ruleset;

  const IngestionResult({
    required this.sourceUrl,
    required this.ruleset,
  });
}

/// Emitted when a remote homebrew JSON conforms to schema and chosen ruleset.
@immutable
class IngestionSuccessResult extends IngestionResult {
  final HomebrewEntity entity;

  const IngestionSuccessResult({
    required this.entity,
    required super.sourceUrl,
    required super.ruleset,
  });

  @override
  String toString() =>
      'IngestionSuccessResult(entity: ${entity.name} [${entity.entityType}], ruleset: ${ruleset.name})';
}

/// Emitted when a file is corrupted, violates ruleset boundaries, or is non-conforming.
/// Allows streaming to continue without terminating the batch import.
@immutable
class IngestionSkipResult extends IngestionResult {
  final String reason;
  final String? errorDetails;

  const IngestionSkipResult({
    required this.reason,
    this.errorDetails,
    required super.sourceUrl,
    required super.ruleset,
  });

  @override
  String toString() =>
      'IngestionSkipResult(url: $sourceUrl, reason: $reason, details: $errorDetails)';
}

/// Port interface for discovering and ingesting GitHub-hosted homebrew repositories.
///
/// Follows Hexagonal Architecture principles (pure domain interface, zero Flutter imports).
abstract class IGithubIngestorPort {
  /// Queries GitHub's Git Trees API for all file paths ending in `.json`.
  /// Returns a list of full raw content download URLs.
  Future<List<String>> discoverJsonManifest(GithubRepoSource source);

  /// Streams ingestion results for the provided raw URLs under the specified ruleset.
  ///
  /// Processing must execute concurrently using a bounded worker pool (max 4 connections),
  /// offloading parsing to background workers and yielding individual [IngestionResult]s.
  Stream<IngestionResult> ingestPayloadStream({
    required List<String> rawUrls,
    required RulesetVersion ruleset,
  });
}
