---
date: 2026-10-07
session: private-email-member-implementation
status: in-progress
---

# Private Email and Member native implementation

## Context

The user approved implementation after reviewing the UI overhaul and requested linked
services management. The earlier TestFlight 1.56.6 attestation release is separate from
this patch. [Plan](../../plans/261007-1825-loox-member-and-private-email-ux-overhaul/plan.md).

## What happened

The source now has optional address creation, a shared recipient-verification coordinator,
deliberate full-email disclosure, canonical one-address-to-many-Login lists and local unlink.
Member tiles open purpose-specific screens. Signed domain proof preserves issued suffixes;
normal Debug now reads the same production registry as the relay.

Independent review found real recovery bugs: resume could report active while the backend
stayed paused, cancellation could strand a breaker, optional enum inference rejected readable
fields, restored editors lost their original baseline, and atomic relation saves skipped
reminder effects. Mid-form domain/recipient changes and disabled recovery navigation also
needed fixes. Selecting a default from stale inbox metadata could also lose a newer verified
state. All nine source corrections are closed in the final passing code review. Native
review added opt-in body contrast roles without changing the stored palette or the
brand/control/icon pairing.

Final hosted tests: 1457 total, 1456 passed, 0 failed, one expected Simulator file-protection
skip. Snapshots passed 12/12 with 40 render receipts; the three new UI journeys passed
with six mounted captures. Native review inspected 26 representative renders and all six
mounted captures, closing the observed accessibility3 Composer/Inbox truncations. Numeric
body contrast passed 504 combinations. Final signed generic-device Debug, privacy,
149-key EN/VI/JA completeness and whitespace checks passed.

Two existing Tutorial snapshots required a narrowly scoped precision adjustment after a
retained-image audit showed 74/80 sparse text-edge pixel differences with unchanged geometry
and reference files. Their exact historical rendering cause is not established. This repair
is documented separately from feature approval; other snapshot references remain exact.

## Reflection

The difficult part was making success truthful across suspended work, local sealed records
and backend acknowledgment. A polished status label would have hidden several errors without
the review. Canonical fields and original baselines keep unlink meaningful after retry or
restore; they also prevent ordinary account email from being mistaken for an association.

## Decisions

Keep `loox.pw` disabled until actual delivery proof. Preserve the original alias namespace,
relay principal and vault. Family stays grounded in existing shares. Local atomicity is
documented separately from independent CloudKit record propagation. Synthetic native tests
are recorded as synthetic; physical Debug/TestFlight, mail and two-account QA remain separate.

## Next

Collect physical Debug/TestFlight, real mail, full runtime accessibility/theme and two-account
Family acceptance receipts before claiming those outcomes. No target physical device was
selected, so no installation occurred. No new candidate has been uploaded for this patch;
the source version remains 1.56.6 (95), with no commit, tag or deployment in this session.
[Implementation progress](../../plans/261007-1825-loox-member-and-private-email-ux-overhaul/reports/implementation-progress.md)
owns the current receipts and open gates. This journal stays local; publication was not requested.
