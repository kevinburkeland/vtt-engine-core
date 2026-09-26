import 'minion_instance.dart';

export 'minion_instance.dart';

/// Compatibility aliases preserving backward compatibility for existing callers
/// while the domain layer adopts generic tabletop [MinionInstance] primitives.
typedef AnimatedObjectInstance = MinionInstance;
typedef AnimatedObjectStats = MinionStats;
typedef ObjectSize = EntitySize;
