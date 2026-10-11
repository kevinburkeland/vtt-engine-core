import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/crdt_or_set.dart';
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
  final CrdtOrSet<String> partyRoster;
  final CrdtOrSet<String> pinnedRules;
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

  /// Derived view of currently active pinned rule identifiers.
  Set<String> get pinnedRuleIds => Set.unmodifiable(pinnedRules.activeValues.toSet());

  /// Derived view of currently active party character identifiers, sorted deterministically.
  List<String> get partyCharacterIds =>
      List.unmodifiable(partyRoster.activeValues.toList()..sort());

  static const _listEventEquality = ListEquality<PartyEvent>();

  CampaignProfile.raw({
    required this.id,
    required this.name,
    this.edition = const RulesetIdentifier('generic_tabletop'),
    required this.createdAt,
    required this.lastPlayedAt,
    required this.roomState,
    CrdtOrSet<String>? partyRoster,
    List<String>? partyCharacterIds,
    Set<String>? pinnedRuleIds,
    CrdtOrSet<String>? pinnedRules,
    required this.notesRegister,
    this.partyPurse = const PartyPurse.empty(),
    List<PartyEvent> changeLog = const [],
  })  : partyRoster = partyRoster ??
            (partyCharacterIds != null && partyCharacterIds.isNotEmpty
                ? _buildInitialPartyRoster(partyCharacterIds)
                : const CrdtOrSet<String>.empty()),
        pinnedRules = pinnedRules ??
            (pinnedRuleIds != null && pinnedRuleIds.isNotEmpty
                ? _buildInitialPinnedRules(pinnedRuleIds)
                : const CrdtOrSet<String>.empty()),
        changeLog = List.unmodifiable(changeLog);

  static CrdtOrSet<String> _buildInitialPartyRoster(Iterable<String> ids) {
    final entries =
        <({String id, String item, HybridLogicalClock timestamp})>[];
    for (final id in ids) {
      entries.add((
        id: id,
        item: id,
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      ));
    }
    return const CrdtOrSet<String>.empty().addBatch(entries);
  }

  static CrdtOrSet<String> _buildInitialPinnedRules(Set<String> ruleIds) {
    final entries =
        <({String id, String item, HybridLogicalClock timestamp})>[];
    for (final id in ruleIds) {
      entries.add((
        id: id,
        item: id,
        timestamp: const HybridLogicalClock(
          physicalTime: 0,
          logicalCounter: 0,
          nodeId: 'genesis',
        ),
      ));
    }
    return const CrdtOrSet<String>.empty().addBatch(entries);
  }

  factory CampaignProfile({
    required String id,
    required String name,
    dynamic edition = const RulesetIdentifier('generic_tabletop'),
    String? rulesetId,
    required DateTime createdAt,
    required DateTime lastPlayedAt,
    required RoomNodeState roomState,
    CrdtOrSet<String>? partyRoster,
    List<String>? partyCharacterIds,
    Set<String>? pinnedRuleIds,
    CrdtOrSet<String>? pinnedRules,
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
      partyRoster: partyRoster,
      partyCharacterIds: partyCharacterIds,
      pinnedRuleIds: pinnedRuleIds,
      pinnedRules: pinnedRules,
      notesRegister: effectiveNotesRegister,
      partyPurse: partyPurse,
      changeLog: changeLog,
    );
  }

  /// Factory creating an initial/blank campaign profile.
  factory CampaignProfile.initial({
    required String id,
    required String name,
    dynamic edition,
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
    CrdtOrSet<String>? partyRoster,
    List<String>? partyCharacterIds,
    Set<String>? pinnedRuleIds,
    CrdtOrSet<String>? pinnedRules,
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

    final effectivePartyRoster = partyRoster ??
        (partyCharacterIds != null
            ? _buildInitialPartyRoster(partyCharacterIds)
            : this.partyRoster);

    final effectivePinnedRules = pinnedRules ??
        (pinnedRuleIds != null
            ? _buildInitialPinnedRules(pinnedRuleIds)
            : this.pinnedRules);

    return CampaignProfile.raw(
      id: id ?? this.id,
      name: name ?? this.name,
      edition: edition ?? rulesetId ?? this.edition,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      roomState: roomState ?? this.roomState,
      partyRoster: effectivePartyRoster,
      pinnedRules: effectivePinnedRules,
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

    final canonicalEdition = a.edition == b.edition
        ? a.edition
        : RulesetIdentifier(a.rulesetId);

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

    // 3. Pinned Rules: pure CRDT OR-Set join
    final mergedPinnedRules = joinPinnedRules(a.pinnedRules, b.pinnedRules);

    // 4. Change Log: pure canonical changelog join
    final mergedEvents = joinChangeLog(a.changeLog, b.changeLog);

    // 5. Party Roster: pure CRDT OR-Set join
    final mergedPartyRoster = joinPartyRosterCrdt(a.partyRoster, b.partyRoster);

    // 6. Nested RoomNodeState: recursive canonical join
    final mergedRoomState = RoomNodeState.join(a.roomState, b.roomState);

    return CampaignProfile.raw(
      id: mergedId,
      name: mergedName,
      edition: canonicalEdition,
      createdAt: mergedCreatedAt,
      lastPlayedAt: mergedLastPlayedAt,
      roomState: mergedRoomState,
      partyRoster: mergedPartyRoster,
      pinnedRules: mergedPinnedRules,
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
          rulesetId == other.rulesetId &&
          createdAt.isAtSameMomentAs(other.createdAt) &&
          lastPlayedAt.isAtSameMomentAs(other.lastPlayedAt) &&
          roomState == other.roomState &&
          partyRoster == other.partyRoster &&
          pinnedRules == other.pinnedRules &&
          notesRegister == other.notesRegister &&
          partyPurse == other.partyPurse &&
          _listEventEquality.equals(changeLog, other.changeLog);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        rulesetId,
        createdAt.toUtc().millisecondsSinceEpoch,
        lastPlayedAt.toUtc().millisecondsSinceEpoch,
        roomState,
        partyRoster,
        pinnedRules,
        notesRegister,
        partyPurse,
        _listEventEquality.hash(changeLog),
      );
}
