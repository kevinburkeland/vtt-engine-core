import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import '../crdt/stateful_hlc_clock.dart';
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
  final CrdtLwwRegister<String> nameRegister;
  final dynamic edition;
  final DateTime createdAt;
  final DateTime lastPlayedAt;
  final RoomNodeState roomState;
  final CrdtOrSet<String> partyRoster;
  final CrdtOrSet<String> pinnedRules;
  final CrdtLwwRegister<String> notesRegister;
  final PartyPurse partyPurse;
  final Map<String, PartyPurse> memberPurses;
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

  String get name => nameRegister.value;
  String get notesMarkdown => notesRegister.value;

  /// Derived view of currently active pinned rule identifiers.
  Set<String> get pinnedRuleIds => Set.unmodifiable(pinnedRules.activeValues.toSet());

  /// Derived view of currently active party character identifiers, sorted deterministically.
  List<String> get partyCharacterIds =>
      List.unmodifiable(partyRoster.activeValues.toList()..sort());

  static const _listEventEquality = ListEquality<PartyEvent>();
  static const _mapPurseEquality = MapEquality<String, PartyPurse>();

  CampaignProfile.raw({
    required this.id,
    CrdtLwwRegister<String>? nameRegister,
    String? name,
    HybridLogicalClock? nameTimestamp,
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
    Map<String, PartyPurse> memberPurses = const {},
    List<PartyEvent> changeLog = const [],
  })  : memberPurses = Map.unmodifiable(memberPurses), nameRegister = nameRegister ??
            (nameTimestamp != null
                ? CrdtLwwRegister<String>(
                    value: name ?? '',
                    timestamp: nameTimestamp,
                  )
                : CrdtLwwRegister<String>(
                    value: name ?? '',
                    timestamp: const HybridLogicalClock(
                      physicalTime: 0,
                      logicalCounter: 0,
                      nodeId: 'genesis',
                    ),
                  )),
        partyRoster = partyRoster ??
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
    String? name,
    CrdtLwwRegister<String>? nameRegister,
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
    Map<String, PartyPurse> memberPurses = const {},
    List<PartyEvent> changeLog = const [],
    required String nodeId,
  }) {
    final effectiveEdition =
        rulesetId ?? edition ?? const RulesetIdentifier('generic_tabletop');
    final effectiveNameRegister = nameRegister ??
        (name != null
            ? CrdtLwwRegister<String>(
                value: name,
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
      nameRegister: effectiveNameRegister,
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
      memberPurses: memberPurses,
      changeLog: changeLog,
    );
  }

  /// Factory creating an initial/blank campaign profile.
  factory CampaignProfile.initial({
    required String id,
    required String name,
    CrdtLwwRegister<String>? nameRegister,
    dynamic edition,
    String? rulesetId,
    required String nodeId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now().toUtc();
    return CampaignProfile(
      id: id,
      name: name,
      nameRegister: nameRegister,
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
    CrdtLwwRegister<String>? nameRegister,
    dynamic edition,
    String? rulesetId,
    Set<String> defaultPinnedRules = const {},
    IRulesetModule? rulesetModule,
    required String nodeId,
    HybridLogicalClock? timestamp,
    StatefulHlcClock? clock,
  }) {
    final authoritativeTimestamp = timestamp ?? clock?.nextTimestamp();
    if (authoritativeTimestamp == null) {
      throw ArgumentError(
        'CampaignProfile.defaultProfile requires an authoritative timestamp or StatefulHlcClock at active creation boundary.',
      );
    }
    if (authoritativeTimestamp.nodeId == 'genesis') {
      throw ArgumentError(
        'CampaignProfile.defaultProfile: "genesis" sentinel cannot be used for active creation causality.',
      );
    }
    if (nodeId.isNotEmpty && nodeId != authoritativeTimestamp.nodeId) {
      throw ArgumentError(
        'CampaignProfile.defaultProfile writer identity mismatch: '
        'nodeId ("$nodeId") does not match timestamp.nodeId ("${authoritativeTimestamp.nodeId}").',
      );
    }

    final now = DateTime.now();
    final profileId = id ?? 'campaign_${now.millisecondsSinceEpoch}';
    final campaignName = name ?? 'My Campaign';
    final effectiveEdition = rulesetId ??
        edition ??
        defaultRulesetEdition;
    final effectivePinned = defaultPinnedRules.isNotEmpty
        ? defaultPinnedRules
        : (rulesetModule?.defaultPinnedRules ?? defaultPinnedRulesFallback);

    final entries = <({String id, String item, HybridLogicalClock timestamp})>[];
    for (final ruleId in effectivePinned) {
      entries.add((
        id: ruleId,
        item: ruleId,
        timestamp: authoritativeTimestamp,
      ));
    }
    final initialPinned = const CrdtOrSet<String>.empty().addBatch(entries);

    final effectiveNameRegister = nameRegister ??
        CrdtLwwRegister<String>(
          value: campaignName,
          timestamp: authoritativeTimestamp,
        );

    final effectiveNotesRegister = CrdtLwwRegister<String>(
      value: '',
      timestamp: authoritativeTimestamp,
    );

    return CampaignProfile.raw(
      id: profileId,
      nameRegister: effectiveNameRegister,
      edition: effectiveEdition,
      createdAt: now,
      lastPlayedAt: now,
      roomState: const RoomNodeState.empty(),
      partyRoster: const CrdtOrSet<String>.empty(),
      partyCharacterIds: const [],
      pinnedRuleIds: effectivePinned,
      pinnedRules: initialPinned,
      notesRegister: effectiveNotesRegister,
      partyPurse: const PartyPurse.empty(),
      memberPurses: const {},
      changeLog: const [],
    );
  }

  CampaignProfile copyWith({
    String? id,
    String? name,
    CrdtLwwRegister<String>? nameRegister,
    HybridLogicalClock? nameTimestamp,
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
    Map<String, PartyPurse>? memberPurses,
    List<PartyEvent>? changeLog,
    HybridLogicalClock? notesTimestamp,
  }) {
    final CrdtLwwRegister<String> resolvedNameRegister;
    if (nameRegister != null) {
      resolvedNameRegister = nameRegister;
    } else if (name != null) {
      if (nameTimestamp == null) {
        throw ArgumentError(
          'Updating name via copyWith requires an authoritative nameTimestamp stamped by StatefulHlcClock.',
        );
      }
      resolvedNameRegister = CrdtLwwRegister<String>(
        value: name,
        timestamp: nameTimestamp,
      );
    } else if (nameTimestamp != null) {
      throw ArgumentError(
        'Updating nameTimestamp via copyWith requires an authoritative name.',
      );
    } else {
      resolvedNameRegister = this.nameRegister;
    }

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
    } else if (notesTimestamp != null) {
      throw ArgumentError(
        'Updating notesTimestamp via copyWith requires an authoritative notesMarkdown.',
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
      nameRegister: resolvedNameRegister,
      edition: edition ?? rulesetId ?? this.edition,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      roomState: roomState ?? this.roomState,
      partyRoster: effectivePartyRoster,
      pinnedRules: effectivePinnedRules,
      notesRegister: resolvedNotesRegister,
      partyPurse: partyPurse ?? this.partyPurse,
      memberPurses: memberPurses != null ? Map<String, PartyPurse>.from(memberPurses) : this.memberPurses,
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

    // Name: pure LWW CRDT register merge
    final mergedNameRegister = a.nameRegister.merge(b.nameRegister);

    // Derived metadata timestamps: earliest created, latest played
    final mergedCreatedAt =
        a.createdAt.isBefore(b.createdAt) ? a.createdAt : b.createdAt;
    final mergedLastPlayedAt =
        a.lastPlayedAt.isAfter(b.lastPlayedAt) ? a.lastPlayedAt : b.lastPlayedAt;

    // 1. Notes: pure LWW CRDT register merge
    final mergedNotes = a.notesRegister.merge(b.notesRegister);

    // 2. Party Purse: pure PN-counter CvRDT lattice join across denominations
    final mergedPurse = a.partyPurse.merge(b.partyPurse);

    // 2b. Member Purses: pure PN-counter CvRDT lattice join key by key
    final mergedMemberPurses = <String, PartyPurse>{};
    final allMemberKeys = {...a.memberPurses.keys, ...b.memberPurses.keys};
    for (final key in allMemberKeys) {
      final purseA = a.memberPurses[key];
      final purseB = b.memberPurses[key];
      if (purseA != null && purseB != null) {
        mergedMemberPurses[key] = purseA.merge(purseB);
      } else {
        mergedMemberPurses[key] = purseA ?? purseB!;
      }
    }

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
      nameRegister: mergedNameRegister,
      edition: canonicalEdition,
      createdAt: mergedCreatedAt,
      lastPlayedAt: mergedLastPlayedAt,
      roomState: mergedRoomState,
      partyRoster: mergedPartyRoster,
      pinnedRules: mergedPinnedRules,
      notesRegister: mergedNotes,
      partyPurse: mergedPurse,
      memberPurses: mergedMemberPurses,
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
          nameRegister == other.nameRegister &&
          rulesetId == other.rulesetId &&
          createdAt.isAtSameMomentAs(other.createdAt) &&
          lastPlayedAt.isAtSameMomentAs(other.lastPlayedAt) &&
          roomState == other.roomState &&
          partyRoster == other.partyRoster &&
          pinnedRules == other.pinnedRules &&
          notesRegister == other.notesRegister &&
          partyPurse == other.partyPurse &&
          _mapPurseEquality.equals(memberPurses, other.memberPurses) &&
          _listEventEquality.equals(changeLog, other.changeLog);

  @override
  int get hashCode => Object.hash(
        id,
        nameRegister,
        rulesetId,
        createdAt.toUtc().millisecondsSinceEpoch,
        lastPlayedAt.toUtc().millisecondsSinceEpoch,
        roomState,
        partyRoster,
        pinnedRules,
        notesRegister,
        partyPurse,
        _mapPurseEquality.hash(memberPurses),
        _listEventEquality.hash(changeLog),
      );
}
