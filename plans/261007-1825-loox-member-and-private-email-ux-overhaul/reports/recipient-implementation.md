# Recipient state and verification implementation

Implemented native P2. No endpoint, principal, App Attest, deployment or release change.

- Sealed, backward-compatible identity generation changes on exact email or destination identity changes. Profile-email derivation invalidates old destination ID and verified status. Persistence CAS checks live inbox/email/destination/generation and refuses malformed or mismatched responses. Same-identity pending cannot downgrade verified; unchanged status never re-seals or bumps timestamps/dirty state.
- AppEnvironment owns the inbox service, verification coordinator and one shared send/check/cooldown controller. Visible scope registration, pending-record observation and foreground/unlock wake checks; background/lock/off/retired/offline/signed read disable cancel or prevent requests. No whole-vault background scan.
- Read-only status admission allows active/degraded/maintenance/disabled and retains local read in every state. GET success records reachability while preserving operator mode. Operation tokens release an admitted half-open probe on lifecycle cancellation exactly once; cancellation does not count as service success or outage.
- Status checks dedupe and serialize with begin/resend. An app-wide rolling 30 GET / 60 second limit applies to manual, foreground and loop triggers. Pending polls use 8 seconds; failures use 15/30/60 seconds with at most 20% jitter. Numeric and HTTP-date Retry-After, including error responses, override shorter backoff. Last known state remains visible on errors.
- Inbox list uses the shared coordinator and scopes derived inboxes to the active persona plus manual inboxes. Inbox detail deliberately reveals the local email on the initial unlocked detail visit; Hide/Show and guarded sensitive copy are explicit. Inactive, lock, email identity change or exit conceal instantly. Foreground and reappearance of an existing detail do not reveal again.
- Inbox detail separates actual forwarding checkpoints from desired destinations awaiting update. Management stays quiet in a menu. Intro sheet shares the same cooldown/controller and visible scope.
- Registry applied callback and unlock backfill are wired for root's signed domain-proof migration.

## Verification performed

Swift frontend parse succeeded for the changed coordinator/service/inbox UI/models/tests. A source harness compiled the actual coordinator, ForwardingInbox model, CapabilityCircuitBreaker and CapabilityStore with Swift 6 and MainActor default isolation. Only unrelated app infrastructure was stubbed. It passed rolling request budget, duplicate checks, Retry-After across foreground, preservation of maintenance mode and exactly-once cancellation of half-open admission. Harness is `/tmp/recipient-stubs.swift` and `/tmp/recipient-harness`; it is not a hosted app test.

Hosted tests added in `VaultifyTests/DestinationVerificationCoordinatorTests.swift`: 12 methods covering persistence email/destination ABA, deletion, no-op sealed bytes/timestamp, malformed/mismatched status, concurrent checks, new pending scope wake/verified stop, begin/GET ordering, rolling budget, Retry-After, lock cancellation and operator/circuit behavior. `ForwardingInboxTests` adds profile-email verification invalidation and legacy generation decode assertion. Actual hosted XCTest and the complete SwiftUI compile run centrally after all agents finish.

## Screen review

Inbox detail's one job is identify and verify the receiving inbox. Identity/status appear first, verification CTA only when needed; routing context follows, management in a menu. Inbox list's job is choose/manage receiving inboxes; masked identity and status reflow vertically. Text uses catalog keys/appString and EN/VI/JA translations in `recipient-localizations.json`. Button rows have 44pt minimums, native menu targets and one primary per verification state. Semantic colors, token spacing/radii and reduced-motion reveal are used. Verification errors retain records. Locked/inactive email display gates conceal independently of the reveal flag.

Remaining acceptance: real light/dark/375/430/large type/accessibility screenshots and physical Debug/TestFlight browser-confirm-return latency. HTML concept and isolated source tests do not establish native visual or production mail delivery acceptance.
