# vtt_engine_core: Operating Manual & Architecture Map

Welcome, AI Agent / Core Architect. This document is the operating manual and architecture map for `vtt_engine_core`. All non-negotiable constitutional invariants are codified in [.antigravityrules](file:///home/kevin/Documents/vtt-engine-core/.antigravityrules). This manual guides repository navigation, code placement, invariant preservation, testing, and cross-repository workflows.

---

## 🧭 Codebase Index & Subsystem Classification

The repository is organized into distinct subsystems. **Agents must distinguish between foundational core abstractions and transitional domain models.**

```
vtt_engine_core/
├── lib/
│   ├── crdt/          # [Foundational Core] Conflict-Free Replicated Data Types & causality clocks
│   │   ├── hybrid_logical_clock.dart   # HLC monotonic causality with deterministic tie-breaking
│   │   ├── crdt_lww_register.dart      # Last-Write-Wins Register (immutable)
│   │   ├── crdt_or_set.dart            # Observed-Remove Set (Add-Wins with tombstone suppression)
│   │   └── pn_counter.dart             # Positive-Negative Counter (differential decrements)
│   ├── currency/      # [Foundational Core] Abstract currency systems & denomination lattices
│   │   └── i_currency_system.dart      # Currency denomination lattice & join contracts
│   ├── ports/         # [Foundational Core] Abstract I/O, persistence & transport contracts
│   │   ├── i_p2p_transport_port.dart   # Abstract peer-to-peer transport contract
│   │   ├── i_network_time_port.dart    # Authoritative network time interface
│   │   ├── i_room_sync_payload_port.dart # Encrypted frame & payload contracts
│   │   ├── i_campaign_repository.dart  # Campaign persistence port
│   │   ├── i_character_repository.dart # Character persistence port
│   │   └── transport_state.dart        # Connection states
│   ├── rules/         # [Foundational Core] Abstract ruleset SPI / anti-corruption layer
│   │   ├── i_ruleset_module.dart       # Extensible ruleset plug-in interface
│   │   ├── i_combat_resolver.dart      # Abstract combat resolution contract
│   │   └── ruleset_edition.dart        # Ruleset identification and versioning
│   ├── storage/       # [Foundational Core] Snapshot serialization & durability ports
│   │   ├── models/                     # StorageSnapshotBundle, EngineProfile, StorageChecksum
│   │   └── ports/                      # Durability and physical snapshot ports
│   ├── homebrew/      # [Agnostic Ingestion] Ruleset-agnostic ingestion interfaces & models
│   │   ├── models/                     # HomebrewEntity
│   │   ├── ports/                      # IGithubIngestorPort
│   │   └── value_objects/              # GithubRepoSource, RulesetVersion
│   ├── models/        # [Transitional Domain] Tabletop domain models (decoupling in progress)
│   │   ├── value_objects/
│   │   │   └── hit_points.dart         # HP clamp/vitals value object (transitional; not all TTRPGs use HP)
│   │   ├── campaign_profile.dart       # Campaign state & metadata
│   │   ├── party_purse.dart            # Shared currency CRDT tracking
│   │   ├── session_graph_models.dart   # Session timeline, room nodes, encounter participants
│   │   ├── character_models.dart       # Generic character entity, AttributePool, condition models
│   │   ├── generic_tabletop_primitives.dart # Agnostic primitives & scalar invariants
│   │   ├── entity_reference.dart       # Typed entity references & polymorphic links
│   │   ├── loot_models.dart            # Inventory & loot containers
│   │   ├── spell_monster_equipment.dart# GenericItem representation
│   │   ├── party_event.dart            # Party timeline events
│   │   └── room_roll.dart              # Agnostic dice roll records
│   └── simulation/    # [Simulation Engine] Probabilistic dice & combat simulation engines
│       ├── i_simulation_strategy.dart  # Simulation strategy contract
│       ├── dpr_simulator.dart          # Damage-per-round mathematical modeling
│       ├── precomputed_attack.dart     # Precomputed attack distributions
│       └── combat_rider.dart           # Hit/crit condition triggers & riders
└── test/
    ├── compliance/    # Purity, licensing, DCO, lexical leakage, and genericity audits
    ├── crdt/          # CRDT mathematical convergence and property tests
    ├── currency/      # Currency lattice join & reduction tests
    ├── models/        # Domain model invariant tests
    ├── simulation/    # DPR and Monte Carlo simulation tests
    └── homebrew/      # Ingestor and source parsing tests
```

### ⚠️ Status Notice: Foundational Core vs. Transitional Domain
Decoupling the engine core from legacy tabletop concepts is actively ongoing:
- **Foundational Core Primitives:** `lib/crdt/`, `lib/ports/`, `lib/rules/`, `lib/storage/`, and `lib/currency/` are architecturally required to remain in core. They define the pure mathematical, transport, and SPI boundaries of the engine.
- **Transitional Domain Models:** The presence of specific files under `lib/models/` and `lib/simulation/` (e.g., `HitPoints`, `PartyPurse`, `DprSimulator`, combat models) reflects **current implementation reality for navigation**, NOT an architectural mandate that these concepts permanently belong in core or an endorsement to add similar mechanics.
- Core models must never assume tabletop conventions as universal:
  - Not all tabletop systems use Hit Points; core models must allow vitals to be optional or nullable (`int?`).
  - Not all tabletop systems use classes, levels, initiative, or traditional combat rounds.
  - Concrete entities (such as `ClassLevelProgression`, `CharacterProgression`, `MinionInstance`, `ArenaCondition`, `FeatureGrant`) have been extracted to ruleset modules and are strictly forbidden from core.

---

## 🏛️ Ownership Boundaries & Code Placement

### 1. Upstream Dependency Isolation
`vtt_engine_core` is strictly upstream. It has zero dependencies on downstream consuming applications (such as `dangerously_nerdy_5e_toolkit`) or concrete rulesets. Core never imports or references host packages.

### 2. Semantic Ruleset Neutrality
- **Semantic, Not Lexical:** Ruleset neutrality is semantic, not lexical. A concept does not belong in `vtt_engine_core` merely because its name is generic or absent from a banned-term list.
- **Ownership Follows Semantics, Not Reuse:** Ownership follows semantics, not reuse. A concept does not belong in `vtt_engine_core` merely because many features or rulesets could reuse it. Ruleset-specific reusable logic remains ruleset-owned. Only concepts whose meaning is independent of a concrete tabletop ruleset belong in the engine.

### 3. The Genericity Pressure Test
Before proposing or placing any public abstraction in `vtt_engine_core`, apply this architectural pressure test:
> *"Would this concept still make coherent sense in materially different tabletop systems, including systems without classes, levels, HP, initiative, or traditional RPG combat?"*

*(Materially different tabletop models serve as architectural pressure tests, not implementation requirements).*

### 4. Placement Guide for New Code
- **Replicated State Primitives:** Put in `lib/crdt/`. Must satisfy CvRDT semilattice properties.
- **I/O, Networking, or Persistence Contracts:** Put in `lib/ports/` or `lib/storage/ports/`. Must be pure Dart abstract contracts.
- **Ruleset Extension Contracts:** Put in `lib/rules/`. Provide abstract SPI hooks (`IRulesetModule`, `ICombatResolver`) for external modules to implement.
- **Ruleset-Specific Mechanics:** Put in the dedicated ruleset package (e.g., `vtt-ruleset-dnd5e`), NEVER in `vtt_engine_core`. Concrete D&D 5e mechanics belong in `../vtt-ruleset-dnd5e`.

---

## 📐 Invariants vs. Implementation Details

Agents must distinguish non-negotiable invariants from refactorable implementation choices.

### 1. CvRDT Invariants (Non-Negotiable)
- **Mathematical Convergence:** All merge operations ($\sqcup$) must be commutative ($A \sqcup B = B \sqcup A$), associative ($(A \sqcup B) \sqcup C = A \sqcup (B \sqcup C)$), and idempotent ($A \sqcup A = A$).
- **Deterministic Causality:** HLC combines physical millisecond timestamp `l`, logical counter `c`, and cryptographic node identifier. Tie-breaking must be strictly deterministic (lexicographical node identifier comparison).
- **Add-Wins with Tombstones:** OR-Set additions must win over concurrent removals. Obsolete tombstones older than active additions must be suppressed on merge to preserve commutativity. Tombstone pruning must strictly anchor to authoritative network time.
- **Differential Counters:** PN-Counter decrements must be applied differentially against negative components; counters must never be re-seeded with positive scalars.
- **Immutability:** Mutators and merge operations must return a new instance. In-place mutation of CvRDT state is forbidden.

*(Implementation details such as internal collection implementations, private field names, or specific batch helper signatures may be refactored as long as algorithmic complexity and convergence invariants are preserved).*

### 2. Simulation & Performance Directives
- **Zero Runtime RegExp in Hot Loops:** Regular expression evaluation inside combat simulation loops, Monte Carlo runs, or DPR calculations is prohibited. String traits and attack profiles must be pre-parsed into numeric ASTs or structured records (`CombatEffectRider`, `PrecomputedAttack`) at the ingestion boundary.
- **Controlled Randomness:** All stochastic simulations must be bit-identically reproducible when supplied with a seeded random number generator (`Random(seed)`).
- **Allocation Efficiency:** Hot state synchronization and simulation iterations must avoid quadratic ($O(N^2)$) allocations.

---

## 🧪 Compliance Gates & Verification Suite

The repository uses automated compliance tests under `test/compliance/` to enforce boundary rules. Agents must understand the precise scope of each gate:

| Test File | Scope & Enforcement Type | Notes |
|:---|:---|:---|
| [domain_purity_test.dart](file:///home/kevin/Documents/vtt-engine-core/test/compliance/domain_purity_test.dart) | **Lexical:** Verifies 0 `package:flutter/...` imports across all files in `lib/`. | Guarantees engine is pure Dart (`meta` package allowed). |
| [ruleset_leakage_test.dart](file:///home/kevin/Documents/vtt-engine-core/test/compliance/ruleset_leakage_test.dart) | **Lexical:** Scans `lib/` for 15 banned 5e tokens (`dnd`, `5e`, `srd5`, `strength`, `dexterity`, `constitution`, `wisdom`, `charisma`, `armorClass`, `challengeRating`, `spellSlot`, `weaponMastery`, `bonusAction`, `shortRest`, `longRest`). | **Does NOT prove semantic neutrality.** Lexical compliance is a baseline safeguard, not proof of generic design. |
| [ruleset_genericity_compliance_test.dart](file:///home/kevin/Documents/vtt-engine-core/test/compliance/ruleset_genericity_compliance_test.dart) | **Structural:** Verifies absence of banned D&D progression types (`ClassLevelProgression`, `CharacterProgression`, `SessionRefType`, `MinionInstance`, `ArenaCondition`, `FeatureGrant`), absence of level-to-PB formulas, nullable combat stats in session models, and zero package dependencies on ruleset toolkits. | Enforces structural decoupling of extracted mechanics. |
| [licensing_and_dco_test.dart](file:///home/kevin/Documents/vtt-engine-core/test/compliance/licensing_and_dco_test.dart) | **Policy:** Verifies AGPLv3 license terms, retroactive copyright scope (Kevin Burkeland), DCO 1.1 sign-off requirements, and PR template checks. | Enforces legal and contribution requirements. |

### Verification Commands
```bash
# Run static analysis
dart analyze

# Run compliance tests
dart test test/compliance/

# Run complete test suite
dart test
```

---

## 🔄 Cross-Repository Context Pivot Protocol

When operating across repositories (such as the sibling consuming application `../dangerously_nerdy_5e_toolkit` or any downstream consumer):

### 1. Context Suspension & Ingestion
1. Read the target repository's `.antigravityrules` and `AGENTS.md`.
2. Explicitly suspend standalone engine-only assumptions.
3. Adhere to the target repository's local governance (e.g. Flutter UI widgets, D&D 5e mechanics, SRD 5.1/5.2.1 licensing, 48dp touch targets).
4. Never leak host application concepts or concrete tabletop mechanics back into `vtt_engine_core`.

### 2. Mandatory Pinned Git Dependency Synchronization Protocol
Consuming applications consume `vtt_engine_core` strictly via pinned Git commit SHAs in `pubspec.yaml`:
```yaml
  vtt_engine_core:
    git:
      url: https://github.com/kevinburkeland/vtt-engine-core.git
      ref: <commit-sha>
```
Never consider repositories integrated merely because local working trees are compatible. When engine changes are made that a consuming repo must consume:
1. Complete and verify engine modifications with `dart analyze` and `dart test`.
2. Commit engine changes with DCO sign-off (`git commit -s`) to produce a concrete commit SHA on `main`.
3. Update the consuming repository's `pubspec.yaml` (`git.ref`) to the exact new engine commit SHA.
4. Remove any local `pubspec_overrides.yaml` or `dependency_overrides` from the consuming repository.
5. Run `flutter pub get` in the consuming repository so the pinned Git commit is actually fetched into the pub cache and locked in `pubspec.lock`.
6. Execute the consuming application's static analysis (`flutter analyze`) and test suites (`flutter test`) against the fetched Git dependency before considering work complete.
