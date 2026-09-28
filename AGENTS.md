# vtt_engine_core: Architecture & AI Directives

Welcome, AI Agent / Core Architect. When generating, refactoring, or reviewing code in this repository, you must strictly uphold the architectural boundaries and mechanical rules described below.

---

## 🧭 Codebase Index

```
vtt_engine_core/
├── lib/
│   ├── crdt/          # Conflict-Free Replicated Data Types & causality clocks
│   │   ├── hybrid_logical_clock.dart   # HLC monotonic clock with deterministic tie-breaking
│   │   ├── crdt_lww_register.dart      # Last-Write-Wins Register
│   │   ├── crdt_or_set.dart            # Observed-Remove Set (Add-Wins with tombstones)
│   │   └── pn_counter.dart             # Positive-Negative Counter
│   ├── currency/      # Abstract currency systems & denomination lattices
│   ├── homebrew/      # Ingestion interfaces & value objects
│   ├── models/        # Generic tabletop domain models & value objects
│   │   ├── value_objects/              # HitPoints, scalar invariants
│   │   ├── campaign_profile.dart       # Campaign state & metadata
│   │   ├── party_purse.dart            # Shared currency CRDT tracking
│   │   └── session_graph_models.dart   # Session timeline & room events
│   ├── ports/         # Abstract I/O, persistence & transport contracts
│   ├── rules/         # Abstract ruleset SPI / anti-corruption layer
│   │   ├── i_ruleset_module.dart       # Extensible ruleset plug-in interface
│   │   ├── i_combat_resolver.dart      # Abstract combat resolution contract
│   │   └── ruleset_edition.dart        # Ruleset identification and versioning
│   ├── simulation/    # Probabilistic dice & combat simulation engines
│   │   ├── dpr_simulator.dart          # Damage-per-round mathematical modeling
│   │   ├── precomputed_attack.dart     # Precomputed attack distributions
│   │   └── combat_rider.dart           # Hit/crit condition triggers & riders
│   └── storage/       # Durability and serialization ports
└── test/
    ├── compliance/    # Purity, licensing, and ruleset leakage audits
    ├── crdt/          # CRDT mathematical convergence tests
    ├── currency/      # Currency lattice join & reduction tests
    ├── models/        # Domain model invariant tests
    └── simulation/    # DPR and Monte Carlo simulation tests
```

---

## 🛡️ Core Directives

### 0. Cross-Boundary Repository Invariant & Context Pivot
When inspecting, editing, or testing consuming applications (such as `../dangerously_nerdy_5e_toolkit`):
- **Mandatory Ingestion:** The agent MUST read `../<target-repo>/.antigravityrules` and `../<target-repo>/AGENTS.md` before making modifications.
- **Context Suspension:** The agent must suspend engine-only assumptions and respect host application conventions (Flutter UI, 5e modules, 48dp touch targets).
- **Core Isolation:** Never import or leak concrete application or system mechanics back into `vtt_engine_core`.

### 1. Pure Dart & Zero UI Engine
- No `package:flutter/...` imports in `lib/`. Use `package:meta/meta.dart` for annotations like `@immutable`.
- Enforced on every build via `test/compliance/domain_purity_test.dart`.

### 2. Strict Ruleset Neutrality (Zero 5E Leakage)
- `vtt_engine_core` is a system-agnostic engine. It must never hardcode D&D 5e-specific terminology, mechanics, or assumptions.
- Explicitly banned in `lib/`: `dnd`, `5e`, `srd5`, `strength`, `dexterity`, `constitution`, `wisdom`, `charisma`, `armorClass`, `challengeRating`, `spellSlot`, `weaponMastery`, `bonusAction`, `shortRest`, `longRest`.
- Tabletop systems implement `IRulesetModule` and `ICombatResolver` to provide concrete mechanics.
- Enforced on every build via `test/compliance/ruleset_leakage_test.dart`.

### 3. Unknown Stays Unknown
- Never infer, synthesize, or hallucinate plausible tabletop defaults (e.g. speed, size, or defenses).
- Missing attributes remain `null`. Retain all unrecognized attributes in `unparsedPayload` maps.

### 4. CvRDT Mathematical Invariants
- **HLC:** Combines physical millisecond `l`, logical counter `c`, and cryptographic UUID v4 `nodeId`. Deterministic tie-breaker: `nodeId.compareTo(other.nodeId)`.
- **CrdtOrSet:** Additions must use `addBatch` to prevent $O(N^2)$ re-allocations. Removals record tombstones unconditionally. Obsolete tombstones older than active items are suppressed on merge to preserve commutativity ($A \sqcup B = B \sqcup A$). Milestone pruning anchors strictly to authoritative network time.
- **PnCounter:** Balances decrement differentially against `effectiveCounter` (`counter.decrement(nodeId, delta)`). Never re-seed counters with positive scalars.
- **CrdtLwwRegister:** Immutability invariant: `set()` and `merge()` return a new instance.

### 5. Performance & Hot-Loop Math
- Zero runtime regular expressions (`RegExp`) in combat or simulation loops.
- Action traits and attack profiles are pre-parsed into numeric ASTs (`CombatEffectRider`, `PrecomputedAttack`).
- High-iteration simulations must be bit-identically reproducible via seeded random generators (`Random(seed)`).

### 6. Licensing & DCO
- Licensed under GNU AGPLv3 with retroactive copyright notice (Kevin Burkeland).
- All contributions must include DCO 1.1 sign-off (`git commit -s`).
- Enforced via `test/compliance/licensing_and_dco_test.dart`.
