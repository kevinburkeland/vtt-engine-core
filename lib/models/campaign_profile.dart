import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../crdt/crdt_lww_register.dart';
import '../crdt/crdt_or_set.dart';
import '../crdt/hybrid_logical_clock.dart';
import '../rules/i_ruleset_module.dart';
import '../rules/ruleset_edition.dart';
import 'session_graph_models.dart';
import 'party_event.dart';
import 'party_purse.dart';

RulesetEdition _resolveRulesetEdition(dynamic raw) {
  if (raw == null) return RulesetEdition.v2024;
  if (raw is RulesetEdition) return raw;
  if (raw is IRulesetModule) {
    return raw.moduleId.contains('2014')
        ? RulesetEdition.v2014
        : RulesetEdition.v2024;
  }
  return RulesetEdition.fromString(raw.toString());
}

/// Immutable Campaign Profile representing an isolated campaign / DM workspace state.
/// This is a pure Domain Entity devoid of persistence and serialization concerns.
@immutable
class CampaignProfile {
  final String id;
  final String name;
  final RulesetEdition edition;
  final DateTime createdAt;
  final DateTime lastPlayedAt;
  final RoomNodeState roomState;
  final List<String> partyCharacterIds;
  final Set<String> pinnedRuleIds;
  final CrdtLwwRegister<String> notesRegister;
  final PartyPurse partyPurse;
  final List<PartyEvent> changeLog;

  /// Identifier of the active ruleset module.
  String get rulesetId =>
      edition == RulesetEdition.v2014 ? 'dnd5e_2014' : 'dnd5e_2024';

  /// Legacy alias for compatibility.
  RulesetEdition get rulesEdition => edition;

  String get notesMarkdown => notesRegister.value;

  static const _listEquality = ListEquality<String>();
  static const _setEquality = SetEquality<String>();

  const CampaignProfile.raw({
    required this.id,
    required this.name,
    this.edition = RulesetEdition.v2024,
    required this.createdAt,
    required this.lastPlayedAt,
    required this.roomState,
    this.partyCharacterIds = const [],
    this.pinnedRuleIds = const {},
    required this.notesRegister,
    this.partyPurse = const PartyPurse(),
    this.changeLog = const [],
  });

  factory CampaignProfile({
    required String id,
    required String name,
    dynamic edition = RulesetEdition.v2024,
    required DateTime createdAt,
    required DateTime lastPlayedAt,
    required RoomNodeState roomState,
    List<String> partyCharacterIds = const [],
    Set<String> pinnedRuleIds = const {},
    CrdtLwwRegister<String>? notesRegister,
    String? notesMarkdown,
    PartyPurse partyPurse = const PartyPurse(),
    List<PartyEvent> changeLog = const [],
    required String nodeId,
  }) {
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
      edition: _resolveRulesetEdition(edition),
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

  /// Factory creating a fresh default campaign profile.
  factory CampaignProfile.defaultProfile({
    String? id,
    String? name,
    dynamic edition = RulesetEdition.v2024,
    Set<String> defaultPinnedRules = const {},
    IRulesetModule? rulesetModule,
    required String nodeId,
  }) {
    final now = DateTime.now();
    final profileId = id ?? 'campaign_${now.millisecondsSinceEpoch}';
    final campaignName = name ?? 'My Campaign';
    final effectivePinned = defaultPinnedRules.isNotEmpty
        ? defaultPinnedRules
        : (rulesetModule?.defaultPinnedRules ??
            const <String>{'concentration', 'grapple_shove'});

    return CampaignProfile(
      id: profileId,
      name: campaignName,
      edition: rulesetModule != null
          ? _resolveRulesetEdition(rulesetModule)
          : _resolveRulesetEdition(edition),
      createdAt: now,
      lastPlayedAt: now,
      roomState: RoomNodeState(
        roomId: 'room_$profileId',
        roomCode: 'CR-101',
        title: '$campaignName - Staging Area',
        description: 'Active DM session staging node.',
        entityLinks: const [],
        containers: const [],
        activeEncounter: const CrdtOrSet<EncounterParticipant>.empty(),
      ),
      partyCharacterIds: const [],
      pinnedRuleIds: effectivePinned,
      partyPurse: const PartyPurse(),
      nodeId: nodeId,
    );
  }

  CampaignProfile copyWith({
    String? id,
    String? name,
    dynamic edition,
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
    String? nodeId,
  }) {
    // Causality Invariant: Strictly resolve nodeId from caller injection or existing
    // CRDT register timestamp. Never fall back to campaign ID (id ?? this.id).
    final effectiveNodeId = nodeId ?? this.notesRegister.timestamp.nodeId;
    final resolvedNotesRegister = notesRegister ??
        (notesMarkdown != null
            ? CrdtLwwRegister<String>(
                value: notesMarkdown,
                timestamp: notesTimestamp ??
                    HybridLogicalClock(
                      physicalTime: DateTime.now().millisecondsSinceEpoch,
                      logicalCounter: 0,
                      nodeId: effectiveNodeId,
                    ),
              )
            : this.notesRegister);

    return CampaignProfile.raw(
      id: id ?? this.id,
      name: name ?? this.name,
      edition: edition != null ? _resolveRulesetEdition(edition) : this.edition,
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
