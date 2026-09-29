/// Standalone, pure Dart Virtual Tabletop (VTT) domain engine.
///
/// Provides CRDT distributed state synchronization primitives, pure domain entities,
/// pluggable multi-ruleset architecture, and ruleset-agnostic combat/dice simulation.
library vtt_engine_core;

// CRDT primitives
export 'crdt/crdt_lww_register.dart';
export 'crdt/crdt_or_set.dart';
export 'crdt/hybrid_logical_clock.dart';
export 'crdt/pn_counter.dart';

// Currency
export 'currency/i_currency_system.dart';

// Homebrew
export 'homebrew/models/homebrew_entity.dart';
export 'homebrew/ports/i_github_ingestor_port.dart';
export 'homebrew/value_objects/github_repo_source.dart';
export 'homebrew/value_objects/ruleset_version.dart';

// Domain Models & Value Objects
export 'models/campaign_profile.dart';
export 'models/character_models.dart';
export 'models/core_types.dart';
export 'models/entity_reference.dart';
export 'models/generic_tabletop_primitives.dart';
export 'models/loot_models.dart';
export 'models/party_event.dart';
export 'models/party_purse.dart';
export 'models/room_roll.dart';
export 'models/session_graph_models.dart';
export 'models/spell_monster_equipment.dart';
export 'models/value_objects/hit_points.dart';

// Domain Ports
export 'ports/i_campaign_repository.dart';
export 'ports/i_character_repository.dart';
export 'ports/i_network_time_port.dart';
export 'ports/i_p2p_transport_port.dart';
export 'ports/i_room_sync_payload_port.dart';
export 'ports/transport_state.dart';

// Domain Rules
export 'rules/i_combat_resolver.dart';
export 'rules/i_ruleset_module.dart';
export 'rules/ruleset_edition.dart';

// Simulation
export 'simulation/combat_rider.dart';
export 'simulation/dpr_simulator.dart';
export 'simulation/i_simulation_strategy.dart';
export 'simulation/precomputed_attack.dart';

// Storage models & ports
export 'storage/models/engine_profile.dart';
export 'storage/models/storage_checksum.dart';
export 'storage/models/storage_snapshot_bundle.dart';
export 'storage/models/storage_telemetry_report.dart';
export 'storage/ports/i_campaign_snapshot_serializer_port.dart';
export 'storage/ports/i_physical_snapshot_port.dart';
export 'storage/ports/i_storage_durability_port.dart';
