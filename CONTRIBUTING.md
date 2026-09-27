# Contributing to vtt_engine_core

Thank you for your interest in contributing to **vtt_engine_core**! We welcome contributions ranging from bug fixes, CRDT state synchronization primitives, and simulation strategies to documentation and performance optimizations.

---

## Code of Conduct

All contributors and maintainers are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please be respectful and collaborative in all discussions and pull requests.

---

## Development Setup

### Prerequisites
* [Dart SDK](https://dart.dev/get-started/sdk) (`>=3.3.0 <4.0.0`)

### Getting Started

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/vtt-engine-core.git
   cd vtt-engine-core
   ```

2. **Install dependencies:**
   ```bash
   dart pub get
   ```

3. **Verify tests and linter:**
   ```bash
   dart analyze
   dart test
   ```

---

## Architectural Guidelines

To maintain architectural purity, determinism, and performance:

1. **Domain Purity (Zero Flutter Coupling):**
   * `vtt_engine_core` is a pure Dart package.
   * Files in `lib/` **MUST NOT** import `package:flutter/...`.
   * Enforced automatically by `test/compliance/domain_purity_test.dart`.

2. **Ruleset Neutrality & Isolation:**
   * Core domain models, session graphs, CRDT primitives, and simulation strategies are ruleset-agnostic.
   * Files in `lib/` **MUST NOT** contain hardcoded system-specific concepts or terminology (e.g. 5e/D&D-specific identifiers).
   * Ruleset implementations plug into abstract interfaces (`IRulesetModule`, `ICombatResolver`).
   * Enforced automatically by `test/compliance/ruleset_leakage_test.dart`.

3. **CRDT Synchronization Invariants:**
   * All state models participating in distributed synchronization must maintain conflict-free convergence (commutativity, associativity, and idempotence).
   * Timestamps must use monotonic `HybridLogicalClock` with deterministic tie-breaking.
   * Deleted entities must record tombstones preventing out-of-order resurrection.

4. **Code Cleanliness & Quality:**
   * Zero warnings or diagnostics on `dart analyze`.
   * 100% pass rate on `dart test`.
   * Unit tests required for all new business logic, domain primitives, and CRDT structures.

---

## Developer Certificate of Origin (DCO) & Licensing

This project operates strictly under an **inbound = outbound** contribution model under the [GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE).

To decentralize copyright ownership and keep this project truly community-owned, **we deliberately do not use a Contributor License Agreement (CLA)**. You retain 100% copyright ownership of your contributions. In exchange, all contributions are made under the Developer Certificate of Origin (DCO) version 1.1.

By contributing to this repository, you certify that you have the right to submit your work under the AGPL-3.0 license according to the DCO:

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

### Retroactive Licensing Scope & Reservation of Rights

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** retroactive to its inception and initial publication on September 26, 2026 (commit `e5ecce3`).

Prior to the addition of the explicit license file, no open-source or permissive license was granted to the public, and all rights were reserved under international copyright law. Under GitHub Terms of Service, public repository hosting only granted permission to view and fork the code within GitHub. It did not grant rights to copy, distribute, modify, or embed the software into proprietary or closed-source products.

Any use, reproduction, distribution, or creation of derivative works based on any commit or release of this repository is conditioned upon compliance with the AGPL-3.0.

### Signing Off Commits (`git commit -s`)

Every commit submitted to this project must be signed off with a `Signed-off-by:` trailer matching your commit author name and email. Git provides the `-s` flag to automate this:

```bash
git commit -s -m "feat(crdt): add multi-value register primitive"
```

This sign-off confirms that you agree to the DCO and assert your right to submit your contribution under the AGPLv3 license without transferring your copyright.

---

## Submitting Pull Requests

1. **Create a descriptive feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Commit your changes with DCO sign-off:**
   * Write clear, concise commit messages following standard conventional commits (e.g., `feat(crdt): ...`, `fix(simulation): ...`).
   * Always include `-s` to sign off on the DCO:
     ```bash
     git commit -s -m "feat(domain): add session graph event serializer"
     ```
3. **Run validation checks:**
   * Ensure `dart analyze` passes with 0 diagnostics.
   * Ensure `dart test` passes 100% of test cases.
4. **Open a Pull Request:**
   * Fill out the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md).
   * Ensure the DCO checklist is verified.
