# ADR-001: Reject Fastbot_iOS from the production quality gate

- Status: Rejected
- Date: 2026-07-20
- Decision owner: bervion

## Context

The proposed production test stack included a monkey-style exploratory runner for broad
UI discovery. `bytedance/Fastbot_iOS` was evaluated for that role. Its upstream GitHub
repository is archived and read-only, publishes no supported release line, and its setup
depends on invasive instrumentation and an older CocoaPods-oriented integration. The
project also contains network/analytics behavior that is disproportionate for an offline
password manager test dependency.

Those properties create supply-chain, Xcode compatibility, privacy and maintenance risks.
Monkey exploration is also nondeterministic, so a green run cannot prove a critical user
journey and a red run is difficult to reproduce without stronger recording infrastructure.

## Decision

Fastbot_iOS is not linked, vendored, installed on release runners or used as a required
quality gate.

The supported stack is:

1. Swift Testing/XCTest for deterministic domain and integration contracts.
2. XCUITest for security-sensitive native journeys and system boundaries.
3. Snapshot tests for declared visual states and accessibility matrices.
4. Maestro for a small number of readable, cross-surface smoke journeys where it adds
   signal without bypassing native authorization.
5. A bounded, non-release-blocking exploratory lane using deterministic synthetic data,
   a fixed runtime/seed where the tool supports it, WIP limits and preserved failure
   artifacts.

Exploratory failures create a deduplicated task for reproduction. They do not overwrite a
deterministic oracle, silently retry until green or promote ledger rows to `verified`.

## Consequences

- Release evidence remains reproducible and attributable to maintained Apple-native or
  deliberately bounded tools.
- Broad random exploration is less extensive initially, but does not add an archived
  privileged dependency to a security product.
- The team must invest in test seams, stable accessibility identifiers and synthetic
  fixtures rather than relying on random tap coverage.

## Reconsideration criteria

Reconsider only a maintained tool with current Xcode/iOS support, documented privacy and
network behavior, reproducible seeds and traces, active vulnerability response, a bounded
installation surface and successful evaluation in an isolated non-release runner. Owner
approval and a superseding ADR are required.

## References

- <https://github.com/bytedance/Fastbot_iOS>
- <https://developer.apple.com/documentation/xctest/user-interface-tests>
- <https://github.com/mobile-dev-inc/Maestro>
