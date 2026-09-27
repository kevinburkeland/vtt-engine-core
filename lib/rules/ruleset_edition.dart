import 'package:meta/meta.dart';

/// Generic opaque ruleset identifier and version representation.
@immutable
class RulesetIdentifier {
  final String moduleId;
  final String version;

  const RulesetIdentifier(
    this.moduleId, [
    this.version = '',
  ]);

  const RulesetIdentifier.unknown()
      : moduleId = 'unknown',
        version = '';

  String get rulesetId => moduleId;
  String get name => moduleId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulesetIdentifier &&
          moduleId == other.moduleId &&
          version == other.version;

  @override
  int get hashCode => Object.hash(moduleId, version);

  @override
  String toString() => version.isEmpty ? moduleId : '$moduleId@$version';
}
