import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/hybrid_logical_clock.dart';
import '../rules/i_ruleset_module.dart';
import '../rules/ruleset_edition.dart';
import '../utils/aggregate_join_utils.dart';
import 'session_graph_models.dart';
import 'party_event.dart';
import 'party_purse.dart';

/// Immutable Campaign Profile representing an isolated campaign / DM workspace state.
/// This is a pure Domain Entity devoid of persistence and serialization concerns.
@immutable
class CampaignProfile {
  final String id;
  final String name;
  final dynamic edition;
  final DateTime createdAt;
  final DateTime lastPlayedAt;
  final RoomNodeState roomState;
  final List<String> partyCharacterIds;
  final Set<String> pinnedRuleIds;
  final CrdtLwwRegister<String> notesRegister;
  final PartyPurse partyPurse;
  final List<PartyEvent> changeLog;

  /// Identifier of the active ruleset module.
  String get rulesetId {
    if (edition is IRulesetModule) return (edition as IRulesetModule).moduleId;
    if (edition is RulesetIdentifier) return (edition as RulesetIdentifier).rulesetId;
    if (edition is Enum) return (edition as Enum).name;
    return edition?.toString() ?? 'generic_tabletop';
  }

  /// Legacy alias for compatibility.
  dynamic get rulesEdition => edition;

  String get notesMarkdown => notesRegister.value;

  static const _listEquality = ListEquality<String>();
  static const _setEquality = SetEquality<String>();

  CampaignProfile.raw({
    required this.id,
    required this.name,
    this.edition = const RulesetIdentifier('generic_tabletop'),
    required this.createdAt,
    required this.lastPlayedAt,
    required this.roomState,
    List<String> partyCharacterIds = const [],
    Set<String> pinnedRuleIds = const {},
    required this.notesRegister,
    this.partyPurse = const PartyPurse.empty(),
    List<PartyEvent> changeLog = const [],
  })  : partyCharacterIds = List.unmodifiable(partyCharacterIds),
        pinnedRuleIds = Set.unmodifiable(pinnedRuleIds),
        changeLog = List.unmodifiable(changeLog);

  factory CampaignProfile({
    required String id,
    required String name,
    dynamic edition = const RulesetIdentifier('generic_tabletop'),
    String? rulesetId,
    required DateTime createdAt,
    required DateTime lastPlayedAt,
    required RoomNodeState roomState,
    List<String> partyCharacterIds = const [],
    Set<String> pinnedRuleIds = const {},
    CrdtLwwRegister<String>? notesRegister,
    String? notesMarkdown,
    PartyPurse partyPurse = const PartyPurse.empty(),
    List<PartyEvent> changeLog = const [],
    required String nodeId,
  }) {
    final effectiveEdition =
        rulesetId ?? edition ?? const RulesetIdentifier('generic_tabletop');
    final effectiveNotesRegister = notesRegister ??
        (notesMarkdown != null
            ? CrdtLwwRegister<String>(
                value: notesMarkdown,
                timestamp: HybridLogicalClock(
                  physicalTime: 0,
                  logicalCounter: 0,
                  nodeId: nodeId,
                ),
              )
            : CrdtLwwRegister<String>(
                value: '',
                timestamp: HybridLogicalClock(
                  physicalTime: 0,
                  logicalCounter: 0,
                  nodeId: nodeId,
                ),
              ));

    return CampaignProfile.raw(
      id: id,
      name: name,
      edition: effectiveEdition,
      createdAt: createdAt,
      lastPlayedAt: lastPlayedAt,
      roomState: roomState,
      partyCharacterIds: partyCharacterIds,
      pinnedRuleIds: pinnedRuleIds,
      notesRegister: effectiveNotesRegister,
      partyPurse: partyPurse,
      changeLog: changeLog,
    );
  }

  /// Factory creating an empty/initial campaign state.
  factory CampaignProfile.initial({
    required String id,
    required String name,
    dynamic edition = const RulesetIdentifier('generic_tabletop'),
    String? rulesetId,
    required String nodeId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now().toUtc();
    return CampaignProfile(
      id: id,
      name: name,
      edition: rulesetId ??
          edition ??
          const RulesetIdentifier('generic_tabletop'),
      createdAt: timestamp,
      lastPlayedAt: timestamp,
      roomState: const RoomNodeState.empty(),
      partyCharacterIds: const [],
      pinnedRuleIds: const {},
      notesMarkdown: '',
      partyPurse: const PartyPurse.empty(),
      nodeId: nodeId,
    );
  }

  static dynamic defaultRulesetEdition =
      const RulesetIdentifier('generic_tabletop');
  static Set<String> defaultPinnedRulesFallback = const {};

  /// Factory creating a fresh default campaign profile.
  factory CampaignProfile.defaultProfile({
    String? id,
    String? name,
    dynamic edition,
    String? rulesetId,
    Set<String> defaultPinnedRules = const {},
    IRulesetModule? rulesetModule,
    required String nodeId,
  }) {
    final now = DateTime.now();
    final profileId = id ?? 'campaign_${now.millisecondsSinceEpoch}';
    final campaignName = name ?? 'My Campaign';
    final effectiveEdition = rulesetId ??
        edition ??
        defaultRulesetEdition;
    final effectivePinned = defaultPinnedRules.isNotEmpty
        ? defaultPinnedRules
        : (rulesetModule?.defaultPinnedRules ?? defaultPinnedRulesFallback);
    return CampaignProfile.initial(
      id: profileId,
      name: campaignName,
      edition: effectiveEdition,
      nodeId: nodeId,
      now: now,
    ).copyWith(pinnedRuleIds: effectivePinned);
  }

  CampaignProfile copyWith({
    String? id,
    String? name,
    dynamic edition,
    String? rulesetId,
    DateTime? createdAt,
    DateTime? lastPlayedAt,
    RoomNodeState? roomState,
    List<String>? partyCharacterIds,
    Set<String>? pinnedRuleIds,
    String? notesMarkdown,
    CrdtLwwRegister<String>? notesRegister,
    PartyPurse? partyPurse,
    List<PartyEvent>? changeLog,
    HybridLogicalClock? notesTimestamp,
  }) {
    final CrdtLwwRegister<String> resolvedNotesRegister;
    if (notesRegister != null) {
      resolvedNotesRegister = notesRegister;
    } else if (notesMarkdown != null) {
      if (notesTimestamp == null) {
        throw ArgumentError(
          'Updating notesMarkdown via copyWith requires an authoritative notesTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNotesRegister = CrdtLwwRegister<String>(
        value: notesMarkdown,
        timestamp: notesTimestamp,
      );
    } else {
      resolvedNotesRegister = this.notesRegister;
    }

    return CampaignProfile.raw(
      id: id ?? this.id,
      name: name ?? this.name,
      edition: edition ?? rulesetId ?? this.edition,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      roomState: roomState ?? this.roomState,
      partyCharacterIds: partyCharacterIds != null
          ? List<String>.from(partyCharacterIds)
          : this.partyCharacterIds,
      pinnedRuleIds: pinnedRuleIds != null
          ? Set<String>.from(pinnedRuleIds)
          : this.pinnedRuleIds,
      notesRegister: resolvedNotesRegister,
      partyPurse: partyPurse ?? this.partyPurse,
      changeLog:
          changeLog != null ? List<PartyEvent>.from(changeLog) : this.changeLog,
    );
  }


  /// Pure canonical aggregate join of two [CampaignProfile] instances.
  ///
  /// Guarantees idempotence, commutativity, and associativity across all valid states.
  /// Divergent unversioned or incompatible immutable state fails loudly and symmetrically.
  static CampaignProfile join(CampaignProfile a, CampaignProfile b) {
    if (identical(a, b)) return a;
    if (a == b) return a;

    final mergedId = joinImmutableId(
      a.id,
      b.id,
      fieldName: 'CampaignProfile.id',
    );

    if (a.rulesetId != b.rulesetId) {
      throw StateError(
        'Incompatible ruleset edition: "${a.rulesetId}" vs "${b.rulesetId}".',
      );
    }

    final mergedName = joinUnversionedString(
      a.name,
      b.name,
      fieldName: 'CampaignProfile.name',
    );

    // Derived metadata timestamps: earliest created, latest played
    final mergedCreatedAt =
        a.createdAt.isBefore(b.createdAt) ? a.createdAt : b.createdAt;
    final mergedLastPlayedAt =
        a.lastPlayedAt.isAfter(b.lastPlayedAt) ? a.lastPlayedAt : b.lastPlayedAt;

    // 1. Notes: pure LWW CRDT register merge
    final mergedNotes = a.notesRegister.merge(b.notesRegister);

    // 2. Party Purse: pure PN-counter CvRDT lattice join across denominations
    final mergedPurse = a.partyPurse.merge(b.partyPurse);

    // 3. Pinned Rules: pure set union
    final mergedPinnedRules = a.pinnedRuleIds.union(b.pinnedRuleIds);

    // 4. Change Log: map by event id, sort by timestamp & id, fail loudly on same-id divergence
    final eventMapA = <String, PartyEvent>{};
    for (final ev in a.changeLog) {
      eventMapA[ev.id] = ev;
    }
    final eventMapB = <String, PartyEvent>{};
    for (final ev in b.changeLog) {
      eventMapB[ev.id] = ev;
    }
    final allEventIds = <String>{...eventMapA.keys, ...eventMapB.keys};
    final mergedEvents = <PartyEvent>[];
    for (final id in allEventIds) {
      final evA = eventMapA[id];
      final evB = eventMapB[id];
      if (evA != null && evB != null) {
        if (evA != evB) {
          throw StateError(
            'Divergent PartyEvent under same event id "$id".',
          );
        }
        mergedEvents.add(evA);
      } else if (evA != null) {
        mergedEvents.add(evA);
      } else if (evB != null) {
        mergedEvents.add(evB);
      }
    }
    mergedEvents.sort((x, y) {
      final cmp = x.timestamp.compareTo(y.timestamp);
      if (cmp != 0) return cmp;
      return x.id.compareTo(y.id);
    });

    // 5. Party Roster: Set-like membership respecting removal events in merged changelog, deterministically sorted
    final removed = <String>{};
    for (final event in mergedEvents) {
      if (event.type == 'characterRemove' || event.type == 'playerLeave') {
        if (event.details.trim().isNotEmpty) {
          removed.add(event.details.trim());
        }
      }
    }
    final activeRoster = <String>{
      ...a.partyCharacterIds,
      ...b.partyCharacterIds,
    }..removeAll(removed);
    final mergedPartyCharacterIds = activeRoster.toList()..sort();

    // 6. Nested RoomNodeState: recursive canonical join
    final mergedRoomState = RoomNodeState.join(a.roomState, b.roomState);

    return CampaignProfile.raw(
      id: mergedId,
      name: mergedName,
      edition: a.edition,
      createdAt: mergedCreatedAt,
      lastPlayedAt: mergedLastPlayedAt,
      roomState: mergedRoomState,
      partyCharacterIds: mergedPartyCharacterIds,
      pinnedRuleIds: mergedPinnedRules,
      notesRegister: mergedNotes,
      partyPurse: mergedPurse,
      changeLog: mergedEvents,
    );
  }

  /// Convenience instance method delegating to canonical pure [join].
  CampaignProfile merge(CampaignProfile other) => CampaignProfile.join(this, other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CampaignProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          edition == other.edition &&
          roomState == other.roomState &&
          _listEquality.equals(partyCharacterIds, other.partyCharacterIds) &&
          _setEquality.equals(pinnedRuleIds, other.pinnedRuleIds) &&
          notesRegister == other.notesRegister &&
          partyPurse == other.partyPurse;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        edition,
        roomState,
        _listEquality.hash(partyCharacterIds),
        _setEquality.hash(pinnedRuleIds),
        notesRegister,
        partyPurse,
      );
}
