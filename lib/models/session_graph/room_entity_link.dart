import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../crdt/crdt_lww_register.dart';
import '../../crdt/hybrid_logical_clock.dart';
import '../../utils/aggregate_join_utils.dart';
import '../../utils/deep_immutable.dart';
import 'entity_category.dart';

const _deepEquality = DeepCollectionEquality();

/// Contextual pointer linking characters, tokens, objects, or zones to a room or graph node
@immutable
class RoomEntityLink {
  static const Object _sentinel = Object();

  final dynamic refType;
  final String entityId;
  final CrdtLwwRegister<String> displayNameRegister;
  final CrdtLwwRegister<String?> notesRegister;
  final Map<String, dynamic>? position; // e.g. {"x": 2, "y": 5}
  final bool isIsolatedClone; // If true, runtime modifications don't mutate parent template
  final Map<String, dynamic>? cloneRuntimeData;
  final HybridLogicalClock incarnationTimestamp;

  String get displayName => displayNameRegister.value;
  String? get notes => notesRegister.value;

  RoomEntityLink({
    this.refType = const EntityCategory('generic', 'Generic'),
    required this.entityId,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    String? notes,
    CrdtLwwRegister<String?>? notesRegister,
    HybridLogicalClock? notesTimestamp,
    Map<String, dynamic>? position,
    this.isIsolatedClone = false,
    Map<String, dynamic>? cloneRuntimeData,
    HybridLogicalClock? incarnationTimestamp,
  })  : displayNameRegister = displayNameRegister ??
            (displayNameTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: displayName ?? '',
                    timestamp: displayNameTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: displayName ?? '',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        notesRegister = notesRegister ??
            (notesTimestamp != null
                ? CrdtLwwRegister<String?>(
                    value: notes,
                    timestamp: notesTimestamp,
                  )
                : CrdtLwwRegister<String?>(
                    value: notes,
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        position = position != null ? deepFreezeMap(position) : null,
        cloneRuntimeData =
            cloneRuntimeData != null ? deepFreezeMap(cloneRuntimeData) : null,
        incarnationTimestamp = incarnationTimestamp ??
            displayNameRegister?.timestamp ??
            displayNameTimestamp ??
            notesRegister?.timestamp ??
            notesTimestamp ??
            const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            );

  const RoomEntityLink.empty()
      : refType = const EntityCategory('generic', 'Generic'),
        entityId = '',
        displayNameRegister = const CrdtLwwRegister<String>(
          value: '',
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        notesRegister = const CrdtLwwRegister<String?>(
          value: null,
          timestamp: HybridLogicalClock(
            physicalTime: 0,
            logicalCounter: 0,
            nodeId: 'genesis',
          ),
        ),
        position = null,
        isIsolatedClone = false,
        cloneRuntimeData = null,
        incarnationTimestamp = const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        );

  RoomEntityLink copyWith({
    dynamic refType,
    String? entityId,
    String? displayName,
    CrdtLwwRegister<String>? displayNameRegister,
    HybridLogicalClock? displayNameTimestamp,
    Object? notes = _sentinel,
    CrdtLwwRegister<String?>? notesRegister,
    HybridLogicalClock? notesTimestamp,
    bool clearNotes = false,
    Map<String, dynamic>? position,
    bool? isIsolatedClone,
    Map<String, dynamic>? cloneRuntimeData,
    HybridLogicalClock? incarnationTimestamp,
  }) {
    final CrdtLwwRegister<String> resolvedDisplayNameRegister;
    if (displayNameRegister != null) {
      resolvedDisplayNameRegister = displayNameRegister;
    } else if (displayName != null) {
      if (displayNameTimestamp == null) {
        throw ArgumentError(
          'Updating displayName via copyWith requires an authoritative displayNameTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedDisplayNameRegister = CrdtLwwRegister<String>(
        value: displayName,
        timestamp: displayNameTimestamp,
      );
    } else if (displayNameTimestamp != null) {
      throw ArgumentError(
        'Updating displayNameTimestamp via copyWith requires an authoritative displayName.',
      );
    } else {
      resolvedDisplayNameRegister = this.displayNameRegister;
    }

    final CrdtLwwRegister<String?> resolvedNotesRegister;
    if (notesRegister != null) {
      resolvedNotesRegister = notesRegister;
    } else if (clearNotes || (notes != _sentinel && notes == null)) {
      if (notesTimestamp == null) {
        throw ArgumentError(
          'Clearing notes via copyWith requires an authoritative notesTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNotesRegister = CrdtLwwRegister<String?>(
        value: null,
        timestamp: notesTimestamp,
      );
    } else if (notes != _sentinel && notes is String) {
      if (notesTimestamp == null) {
        throw ArgumentError(
          'Updating notes via copyWith requires an authoritative notesTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNotesRegister = CrdtLwwRegister<String?>(
        value: notes,
        timestamp: notesTimestamp,
      );
    } else if (notesTimestamp != null) {
      throw ArgumentError(
        'Updating notesTimestamp via copyWith requires authoritative notes or clearNotes: true.',
      );
    } else {
      resolvedNotesRegister = this.notesRegister;
    }

    return RoomEntityLink(
      refType: refType ?? this.refType,
      entityId: entityId ?? this.entityId,
      displayNameRegister: resolvedDisplayNameRegister,
      notesRegister: resolvedNotesRegister,
      position: position ?? this.position,
      isIsolatedClone: isIsolatedClone ?? this.isIsolatedClone,
      cloneRuntimeData: cloneRuntimeData ?? this.cloneRuntimeData,
      incarnationTimestamp: incarnationTimestamp ?? this.incarnationTimestamp,
    );
  }

  /// Canonicalizes supported [refType] representations (EntityCategory, Enum, String)
  /// into a consistent string key for serialization, equality, and hashing.
  static String canonicalRefTypeKey(dynamic refType) {
    if (refType is EntityCategory) {
      return refType.key;
    } else if (refType is Enum) {
      return refType.name;
    } else if (refType is String) {
      return refType;
    } else if (refType == null) {
      return 'generic';
    } else {
      throw ArgumentError.value(
        refType,
        'refType',
        'Unsupported RoomEntityLink refType. Expected EntityCategory, Enum, or String.',
      );
    }
  }

  /// Returns the canonical string identifier of [refType].
  String get canonicalRefType => canonicalRefTypeKey(refType);

  Map<String, dynamic> toMap() => {
        'refType': canonicalRefTypeKey(refType),
        'entityId': entityId,
        'displayName': displayName,
        'displayNameRegister': {
          'value': displayNameRegister.value,
          'timestamp': displayNameRegister.timestamp.toMap(),
        },
        if (notes != null) 'notes': notes,
        'notesRegister': {
          'value': notesRegister.value,
          'timestamp': notesRegister.timestamp.toMap(),
        },
        'incarnationTimestamp': incarnationTimestamp.toMap(),
        if (position != null) 'position': position,
        if (isIsolatedClone) 'isIsolatedClone': true,
        if (cloneRuntimeData != null) 'cloneRuntimeData': cloneRuntimeData,
      };

  factory RoomEntityLink.fromMap(Map<String, dynamic> map,
      {dynamic Function(String)? refTypeResolver}) {
    final typeStr = map['refType']?.toString() ?? 'generic';
    final resolvedRefType = refTypeResolver != null
        ? refTypeResolver(typeStr)
        : EntityCategory(typeStr, typeStr);

    final CrdtLwwRegister<String> displayNameReg;
    if (map.containsKey('displayNameRegister')) {
      final rawReg = map['displayNameRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      if (rawVal == null) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "displayNameRegister" value cannot be null.',
        );
      }
      displayNameReg = CrdtLwwRegister<String>(
        value: rawVal.toString(),
        timestamp: timestamp,
      );
    } else {
      displayNameReg = CrdtLwwRegister<String>(
        value: map['displayName']?.toString() ?? '',
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    final CrdtLwwRegister<String?> notesReg;
    if (map.containsKey('notesRegister')) {
      final rawReg = map['notesRegister'];
      if (rawReg is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "notesRegister" must be a Map, got ${rawReg.runtimeType}',
        );
      }
      final rawTs = rawReg['timestamp'] ?? rawReg['ts'];
      if (rawTs is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "notesRegister" missing or invalid timestamp: $rawTs',
        );
      }
      final timestamp = HybridLogicalClock.fromMap(rawTs);
      if (!rawReg.containsKey('value') && !rawReg.containsKey('v')) {
        throw const FormatException(
          'RoomEntityLink.fromMap: "notesRegister" missing "value" or "v" field.',
        );
      }
      final rawVal = rawReg.containsKey('value') ? rawReg['value'] : rawReg['v'];
      notesReg = CrdtLwwRegister<String?>(
        value: rawVal?.toString(),
        timestamp: timestamp,
      );
    } else {
      notesReg = CrdtLwwRegister<String?>(
        value: map['notes']?.toString(),
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      );
    }

    final HybridLogicalClock incarnationTs;
    if (map.containsKey('incarnationTimestamp')) {
      final rawInc = map['incarnationTimestamp'];
      if (rawInc is! Map) {
        throw FormatException(
          'RoomEntityLink.fromMap: "incarnationTimestamp" must be a Map, got ${rawInc.runtimeType}',
        );
      }
      incarnationTs = HybridLogicalClock.fromMap(rawInc);
    } else {
      final maxTs = displayNameReg.timestamp.isAfter(notesReg.timestamp)
          ? displayNameReg.timestamp
          : notesReg.timestamp;
      incarnationTs = maxTs.physicalTime > 0
          ? maxTs
          : const HybridLogicalClock(
              physicalTime: 0,
              logicalCounter: 0,
              nodeId: 'genesis',
            );
    }

    return RoomEntityLink(
      refType: resolvedRefType,
      entityId: map['entityId']?.toString() ?? '',
      displayNameRegister: displayNameReg,
      notesRegister: notesReg,
      position: map['position'] != null
          ? Map<String, dynamic>.from(map['position'] as Map)
          : null,
      isIsolatedClone: map['isIsolatedClone'] == true,
      cloneRuntimeData: map['cloneRuntimeData'] != null
          ? Map<String, dynamic>.from(map['cloneRuntimeData'] as Map)
          : null,
      incarnationTimestamp: incarnationTs,
    );
  }

  /// Pure canonical aggregate join of two [RoomEntityLink] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  static RoomEntityLink join(RoomEntityLink a, RoomEntityLink b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedEntityId = joinImmutableId(
      a.entityId,
      b.entityId,
      fieldName: 'RoomEntityLink.entityId',
    );

    if (canonicalRefTypeKey(a.refType) != canonicalRefTypeKey(b.refType)) {
      throw StateError(
        'RoomEntityLink refType mismatch for "${a.entityId}": '
        '"${a.canonicalRefType}" vs "${b.canonicalRefType}".',
      );
    }

    if (a.isIsolatedClone != b.isIsolatedClone) {
      throw StateError(
        'RoomEntityLink isIsolatedClone mismatch for "${a.entityId}": '
        '${a.isIsolatedClone} vs ${b.isIsolatedClone}.',
      );
    }

    // Incarnation boundary: pre-removal nested fields cannot leak across incarnations.
    if (a.incarnationTimestamp != b.incarnationTimestamp) {
      if (a.incarnationTimestamp.isAfter(b.incarnationTimestamp)) {
        return a;
      } else {
        return b;
      }
    }

    final mergedDisplayName = a.displayNameRegister.merge(b.displayNameRegister);
    final mergedNotes = a.notesRegister.merge(b.notesRegister);

    final mergedPosition = joinNullableMap(
      a.position,
      b.position,
      context: 'RoomEntityLink.position',
    );

    final mergedCloneRuntimeData = joinNullableMap(
      a.cloneRuntimeData,
      b.cloneRuntimeData,
      context: 'RoomEntityLink.cloneRuntimeData',
    );

    return RoomEntityLink(
      refType: a.refType,
      entityId: mergedEntityId,
      displayNameRegister: mergedDisplayName,
      notesRegister: mergedNotes,
      position: mergedPosition,
      isIsolatedClone: a.isIsolatedClone,
      cloneRuntimeData: mergedCloneRuntimeData,
      incarnationTimestamp: a.incarnationTimestamp,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  RoomEntityLink merge(RoomEntityLink other) => RoomEntityLink.join(this, other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomEntityLink &&
          runtimeType == other.runtimeType &&
          canonicalRefTypeKey(refType) == canonicalRefTypeKey(other.refType) &&
          entityId == other.entityId &&
          displayNameRegister == other.displayNameRegister &&
          notesRegister == other.notesRegister &&
          incarnationTimestamp == other.incarnationTimestamp &&
          _deepEquality.equals(position, other.position) &&
          isIsolatedClone == other.isIsolatedClone &&
          _deepEquality.equals(cloneRuntimeData, other.cloneRuntimeData);

  @override
  int get hashCode => Object.hash(
        canonicalRefTypeKey(refType),
        entityId,
        displayNameRegister,
        notesRegister,
        incarnationTimestamp,
        _deepEquality.hash(position),
        isIsolatedClone,
        _deepEquality.hash(cloneRuntimeData),
      );
}
