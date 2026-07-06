# G2 — ForwardingInbox model + 0..N reusable aliases

Priority: high (model foundation for G3/G4). Status: pending.

## Design

**ForwardingInbox** — new sealed record following the persona/alias pattern:

- `ForwardingInboxRecord` (SwiftData: id, sealed, sortIndex, deletedAt, createdAt, updatedAt,
  changeTag) + CK type `VaultForwardingInbox` in `CloudSyncService` (LWW by updatedAt; **add to
  prod-schema deploy checklist**).
- `ForwardingInboxSecret` (sealed, growable decode): `email`, `label?`, `source`
  (.personaProfile/.manual), `isDefault`, timestamps.
- Repo: `VaultRepository+ForwardingInboxes.swift` — load/seal, CRUD, `defaultInbox(for
  persona:)` resolution.
- Migration/derivation: on reload, if a persona has a profile email and no inbox referencing it,
  lazily create a `.personaProfile` inbox (idempotent). `destinationEmail(for:)` becomes
  inbox-backed but keeps profile-email fallback (fail-safe).

**EmailAlias changes** (growable decode, LWW-safe — bump updatedAt on change):

- `forwardingInboxID: String?` — which inbox this alias forwards to (nil → persona default).
  `forwardingTarget` stays as the last-rotated email cache (display + idempotent retry).
- `label: String?` — user label ("Clients", "GitHub Work").
- Drop the ≤1 persona-tier cap: `createPersonaAlias` → `createReusableAlias(label:)`, 0..N.
  Update `testCreatePersonaAliasIsCappedAtOne` → multiple-allowed test. `personaAlias(forPersona:)`
  callers move to list-based resolvers.

**RelayService**: `activate` resolves destination via alias's inbox (default fallback);
`updateDestination` rotates only aliases pointing at the changed inbox.

## Invariants

- INV-PE01/SEC-PE12: inbox resolvers persona-scoped where applicable; strictAnonymous persona
  never resolves another persona's inbox/email silently.
- SEC-PE01..04: inbox label/persona linkage never sent to relay — only the raw email in
  rotateDestination (unchanged contract).

## Success

- Round-trip + backward-decode tests (legacy alias blob without new keys → nil/defaults).
- Multiple reusable aliases per persona pass; sync LWW test for inbox record.
- `make check` + full suite green.
