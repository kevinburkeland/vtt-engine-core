import 'dart:math' as math;
import 'package:meta/meta.dart';

/// Value object tracking physical time and logical causality for distributed state reconciliation.
/// Implements deterministic lexicographical tie-breaking by [nodeId] when physical time
/// and logical counter are identical.
@immutable
class HybridLogicalClock implements Comparable<HybridLogicalClock> {
  final int physicalTime;
  final int logicalCounter;
  final String nodeId;

  const HybridLogicalClock({
    required this.physicalTime,
    required this.logicalCounter,
    required this.nodeId,
  });

  factory HybridLogicalClock.now(
    String nodeId, {
    int offsetMs = 0,
    int Function()? timeProvider,
  }) {
    final base = timeProvider != null
        ? timeProvider()
        : DateTime.now().toUtc().millisecondsSinceEpoch;
    return HybridLogicalClock(
      physicalTime: base + offsetMs,
      logicalCounter: 0,
      nodeId: nodeId,
    );
  }

  /// Advances the clock locally. If physical time has moved forward, resets
  /// the logical counter to 0; otherwise increments the logical counter.
  HybridLogicalClock tick({
    int offsetMs = 0,
    int Function()? timeProvider,
  }) {
    final base = timeProvider != null
        ? timeProvider()
        : DateTime.now().toUtc().millisecondsSinceEpoch;
    final now = base + offsetMs;
    if (now > physicalTime) {
      return HybridLogicalClock(
        physicalTime: now,
        logicalCounter: 0,
        nodeId: nodeId,
      );
    }
    return HybridLogicalClock(
      physicalTime: physicalTime,
      logicalCounter: logicalCounter + 1,
      nodeId: nodeId,
    );
  }

  /// Reconciles local clock with a remote clock, taking the max physical time
  /// and resolving the logical counter causality.
  HybridLogicalClock merge(
    HybridLogicalClock remote, {
    int offsetMs = 0,
    int Function()? timeProvider,
  }) {
    final base = timeProvider != null
        ? timeProvider()
        : DateTime.now().toUtc().millisecondsSinceEpoch;
    final now = base + offsetMs;
    final maxPhysical = math.max(physicalTime, remote.physicalTime);
    final nextPhysical = math.max(maxPhysical, now);

    int nextCounter = 0;
    if (nextPhysical == physicalTime && nextPhysical == remote.physicalTime) {
      nextCounter = math.max(logicalCounter, remote.logicalCounter) + 1;
    } else if (nextPhysical == physicalTime) {
      nextCounter = logicalCounter + 1;
    } else if (nextPhysical == remote.physicalTime) {
      nextCounter = remote.logicalCounter + 1;
    }

    return HybridLogicalClock(
      physicalTime: nextPhysical,
      logicalCounter: nextCounter,
      nodeId: nodeId,
    );
  }

  @override
  int compareTo(HybridLogicalClock other) {
    if (physicalTime == other.physicalTime) {
      if (logicalCounter == other.logicalCounter) {
        return nodeId.compareTo(other.nodeId); // Lexicographical tie-breaker
      }
      return logicalCounter.compareTo(other.logicalCounter);
    }
    return physicalTime.compareTo(other.physicalTime);
  }

  bool isAfter(HybridLogicalClock other) => compareTo(other) > 0;
  bool isBefore(HybridLogicalClock other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HybridLogicalClock &&
          runtimeType == other.runtimeType &&
          physicalTime == other.physicalTime &&
          logicalCounter == other.logicalCounter &&
          nodeId == other.nodeId;

  @override
  int get hashCode =>
      physicalTime.hashCode ^ logicalCounter.hashCode ^ nodeId.hashCode;

  Map<String, dynamic> toMap() => {
        'pt': physicalTime,
        'lc': logicalCounter,
        'node': nodeId,
      };

  factory HybridLogicalClock.fromMap(Map<dynamic, dynamic> map) {
    final rawNodeId = map['node'] ?? map['nodeId'];
    if (rawNodeId == null || rawNodeId.toString().trim().isEmpty) {
      throw const FormatException('Missing required nodeId in HLC payload');
    }

    final rawPt = map['pt'] ?? map['physicalTime'];
    if (rawPt == null) {
      throw const FormatException('Missing required physicalTime in HLC payload');
    }

    final int pt;
    if (rawPt is int) {
      pt = rawPt;
    } else if (rawPt is double) {
      if (!rawPt.isFinite || rawPt.truncateToDouble() != rawPt) {
        throw FormatException('Malformed fractional physicalTime in HLC payload: $rawPt');
      }
      pt = rawPt.toInt();
    } else if (rawPt is String) {
      final parsedInt = int.tryParse(rawPt);
      if (parsedInt != null) {
        pt = parsedInt;
      } else {
        final parsedDouble = double.tryParse(rawPt);
        if (parsedDouble != null &&
            parsedDouble.isFinite &&
            parsedDouble.truncateToDouble() == parsedDouble) {
          pt = parsedDouble.toInt();
        } else {
          throw FormatException('Malformed physicalTime in HLC payload: $rawPt');
        }
      }
    } else {
      throw FormatException('Malformed physicalTime in HLC payload: $rawPt');
    }

    final rawLc = map['lc'] ?? map['logicalCounter'];
    final int lc;
    if (rawLc == null) {
      lc = 0;
    } else if (rawLc is int) {
      lc = rawLc;
    } else if (rawLc is double) {
      if (!rawLc.isFinite || rawLc.truncateToDouble() != rawLc) {
        throw FormatException('Malformed fractional logicalCounter in HLC payload: $rawLc');
      }
      lc = rawLc.toInt();
    } else if (rawLc is String) {
      final parsedInt = int.tryParse(rawLc);
      if (parsedInt != null) {
        lc = parsedInt;
      } else {
        final parsedDouble = double.tryParse(rawLc);
        if (parsedDouble != null &&
            parsedDouble.isFinite &&
            parsedDouble.truncateToDouble() == parsedDouble) {
          lc = parsedDouble.toInt();
        } else {
          throw FormatException('Malformed logicalCounter in HLC payload: $rawLc');
        }
      }
    } else {
      throw FormatException('Malformed logicalCounter in HLC payload: $rawLc');
    }

    if (lc < 0) {
      throw FormatException('logicalCounter must be non-negative (>= 0), got $lc');
    }

    return HybridLogicalClock(
      physicalTime: pt,
      logicalCounter: lc,
      nodeId: rawNodeId.toString(),
    );
  }

  @override
  String toString() =>
      'HybridLogicalClock(pt: $physicalTime, lc: $logicalCounter, node: $nodeId)';
}
