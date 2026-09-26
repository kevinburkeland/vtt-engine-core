import 'package:meta/meta.dart';

/// Browser rendering engines with distinct storage eviction characteristics.
enum BrowserEngine {
  chromium,
  webkit,
  gecko,
  other,
}

/// Host operating system classification.
enum PlatformOs {
  ios,
  android,
  macos,
  windows,
  linux,
  other,
}

/// Immutable client profile capturing browser engine and display mode characteristics.
@immutable
class EngineProfile {
  final BrowserEngine engine;
  final PlatformOs os;
  final bool isStandalonePwa;

  const EngineProfile({
    required this.engine,
    required this.os,
    required this.isStandalonePwa,
  });

  /// WebKit 7-day ITP eviction risk applies to non-standalone WebKit engines and all non-standalone iOS browsers.
  bool get isWebKitEvictionRisk =>
      (engine == BrowserEngine.webkit || os == PlatformOs.ios) &&
      !isStandalonePwa;

  /// Firefox enforces strict permission fences requiring explicit user gestures for persistent storage.
  bool get requiresExplicitGesture =>
      engine == BrowserEngine.gecko && !isStandalonePwa;

  EngineProfile copyWith({
    BrowserEngine? engine,
    PlatformOs? os,
    bool? isStandalonePwa,
  }) {
    return EngineProfile(
      engine: engine ?? this.engine,
      os: os ?? this.os,
      isStandalonePwa: isStandalonePwa ?? this.isStandalonePwa,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineProfile &&
          runtimeType == other.runtimeType &&
          engine == other.engine &&
          os == other.os &&
          isStandalonePwa == other.isStandalonePwa;

  @override
  int get hashCode => Object.hash(engine, os, isStandalonePwa);

  @override
  String toString() =>
      'EngineProfile(engine: $engine, os: $os, isStandalonePwa: $isStandalonePwa)';
}
