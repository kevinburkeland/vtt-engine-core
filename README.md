# vtt_engine_core

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![DCO 1.1](https://img.shields.io/badge/DCO-1.1-brightgreen.svg)](CONTRIBUTING.md#developer-certificate-of-origin-dco--licensing)
[![Dart](https://img.shields.io/badge/Dart-3.3%2B-0175C2.svg?logo=dart)](https://dart.dev)

A standalone, pure Dart tabletop virtual tabletop (VTT) domain engine and conflict-free replicated data type (CRDT) state synchronization primitives.

> [!WARNING]
> **Work-In-Progress & Volatility Warning: Use At Your Own Risk Or Not At All**  
> **Decoupling from D&D is still actively in progress, and none of the internal structure or APIs have stabilized yet.**  
> Breaking changes will occur frequently and without deprecation cycles as abstractions are refactored. Do not rely on current interfaces for production projects unless you are prepared to adapt to continuous breaking changes.

---

## ⚠️ Development Status & Volatility Warning

This library is undergoing heavy active development and architectural extraction:
* **Decoupling in Progress:** Decoupling the engine core from 5e-specific concepts and legacy mechanics is actively ongoing.
* **Unstable Internal Structure:** **None of the internal architecture, domain models, CRDT synchronization contracts, or storage serialization formats have stabilized.**
* **Adoption Advisory:** **Use at your own risk, or do not use at all** until API stability is explicitly announced.

---

## Architecture & Core Modules

`vtt_engine_core` is strictly decoupled from UI frameworks (zero Flutter dependencies in `lib/`) and isolated from specific tabletop roleplaying systems (pure ruleset neutrality).

```
lib/
├── crdt/          # Conflict-Free Replicated Data Types & causality clocks
│   ├── hybrid_logical_clock.dart   # HLC monotonic clock with deterministic tie-breaking
│   ├── crdt_lww_register.dart      # Last-Write-Wins Register
│   ├── crdt_or_set.dart            # Observed-Remove Set (Add-Wins with tombstones)
│   └── pn_counter.dart             # Positive-Negative Counter
├── models/        # Generic tabletop domain models & value objects
│   ├── value_objects/              # HitPoints, currencies, and scalar invariants
│   ├── campaign_profile.dart       # Campaign state & metadata
│   ├── party_purse.dart            # Shared & character currency CRDT tracking
│   └── session_graph_models.dart   # Session timeline & room events
├── simulation/    # Probabilistic dice & combat simulation engines
│   ├── dpr_simulator.dart          # Damage-per-round mathematical modeling
│   ├── precomputed_attack.dart     # Precomputed attack and damage distributions
│   └── combat_rider.dart           # Hit/crit condition triggers & riders
├── rules/         # Abstract ruleset SPI / anti-corruption layer
│   ├── i_ruleset_module.dart       # Extensible ruleset plug-in interface
│   ├── i_combat_resolver.dart      # Abstract combat resolution contract
│   └── ruleset_edition.dart        # Ruleset identification and versioning
├── storage/       # Durability and serialization ports
│   ├── engine_profile.dart         # Engine configuration & profiles
│   ├── storage_snapshot_bundle.dart# Complete snapshot bundles & checksum verification
│   └── ports/                      # Abstract storage & physical snapshot ports
└── ports/         # P2P and networking transport contracts
```

---

## Installation

Add `vtt_engine_core` to your `pubspec.yaml`:

```yaml
dependencies:
  vtt_engine_core:
    git:
      url: https://github.com/kevinburkeland/vtt-engine-core.git
```

---

## Architectural Principles

1. **Pure Dart (Zero UI Coupling):**
   * Enforced via automated compliance testing (`test/compliance/domain_purity_test.dart`). No Flutter packages or UI elements exist in the domain layer.
2. **Ruleset Neutrality:**
   * Enforced via automated leakage auditing (`test/compliance/ruleset_leakage_test.dart`). The engine primitives are system-agnostic; concrete rulesets implement abstract ports.
3. **Deterministic State Synchronization:**
   * Distributed multi-peer synchronization is mathematically sound, upholding commutativity, associativity, and idempotence across out-of-order networks.

---

## Testing & Quality Assurance

Run the test suite and static analysis:

```bash
dart analyze
dart test
```

---

## Licensing & Retroactive Copyright Notice

`vtt_engine_core` is free and open-source software licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

### Retroactive Protection
This license grant is issued by the author and sole copyright holder, **Kevin Burkeland**, and applies **retroactively** to all versions, commits, branches, and tags starting from the initial creation and publication of this repository on September 26, 2026 (commit `e5ecce3`).

Prior to the addition of the license file, all rights were reserved under international copyright law; no permissive or proprietary license was ever granted. Any use, distribution, or creation of derivative works from this repository is strictly conditioned upon compliance with the copyleft provisions of the GNU AGPLv3.

See the [LICENSE](LICENSE) file for the complete license terms and conditions.

---

## Contributing & Developer Certificate of Origin (DCO)

We welcome community contributions under a decentralized copyright model:
* **No Contributor License Agreement (CLA):** You retain 100% ownership of your code.
* **Developer Certificate of Origin (DCO v1.1):** All contributions are certified via `git commit -s`.
* **Inbound = Outbound:** All contributions are licensed under GNU AGPLv3.

Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting pull requests.
