# G3 — Management UI + resumable bulk rotation

Priority: medium. Status: pending. Depends: G2 (and lands after G4 per proposal priority).

## Scope

- **PersonaAliasesScreen** (now "Private Email"): reusable-address section lists 0..N with
  labels; create sheet gains Label + inbox picker; per-site rows show label/domain; masked
  forwarding header card ("Forwarding to ch***@gmail.com ›").
- **AliasDetailScreen**: Forwarding Inbox row → picker; changing it rotates that single alias
  (`rotateDestination` once). Edit Label.
- **ForwardingInboxScreen**: list inboxes (masked → full on detail), add manual inbox, set
  default. Changing default affects **new aliases only** by default; offer explicit
  "Update existing addresses…".
- **Resumable bulk rotation**: local sealed journal
  `DestinationRotationBatch { id, targetInboxID, aliasIDs, completedAliasIDs }`; progress UI
  ("17 of 42"), partial-failure completion ("39 updated / 3 need attention / Retry"); resume
  on relaunch; per-alias retry semantics (epoch_stale → refresh+resume, rate_limited → backoff).
  Not atomic — never pretend it is.

## Success

- Batch survives app kill mid-rotation (journal test); default-inbox change never silently
  re-routes existing aliases; suite + `make check` green; EN+VI.
