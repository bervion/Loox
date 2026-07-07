# App → BE — Phase C V2 Parity GREEN + 429/503 Handler Wired

**From:** Vaultify app team · **To:** Loox backend · **Date:** 2026-07-07
**Re:** "Abuse Hardening Shipped" handoff. Both app-side asks are implemented, tested, merged to `develop` (PR #61, suite **325/325**).

## Ask 1 — Loox V2 parity: ✅ DONE, 7/7

`LooxLinkCanonical` moved to `LOOX-APP-ATTEST-CREATE-SHARE-V2` (V1 layout + `byte(one_time)` final field). All **7 frozen V2 vectors** reproduce `canonical_bytes_hex` + `request_hash_hex` byte-for-byte from your fixture (copied verbatim into the test bundle — no retyping). Mutation pair asserted (hashes differ) + an encoder-level one_time-flip test.

- Client is now **V2-only** — your shadow logs will show `ok:v2` from the next app build; no V1 traffic from us after fleet migration.
- `one_time` now **always explicit** in the wire body (your absent=false rule noted; we never rely on it).
- V1 fixture removed client-side.

**→ From our side, link `required` + token cutover Stage B can be scheduled.** Gate remaining: fleet on the V2 build (watch `ok:v1` fade in shadow logs) + owner nod.

## Ask 2 — 429/503 handler: ✅ CONFIRMED per §4

- **429** (`rate_limited` / `destination_rate_limited`): user-attributable — `noteServiceResponded`, never operator state, never maintenance; honored as "don't auto-retry, try again later" (localized copy). `X-Loox-Service-State: active` on 429 never touches operator mode (429 path doesn't consult it).
- **503 `*_capacity_reached`**: new `Failure.capacityReached(retryAfter:)`, classified **before** the operator/infrastructure split → can never trip the breaker or masquerade as maintenance/outage. Same gentle try-again-later copy (innocent-user framing).
- Plain 503 (no problem+json code) remains infrastructure (breaker input) — unchanged, per INV-CAP-07.
- SMTP-side 451 = no app surface, agreed.

## Ask 3 — Real-device QA window

Owner schedules (needs a physical device; simulator has no App Attest). We'll ping right before starting so you can watch `[relay-assertion-shadow]`. Note assertion headers already ride on **every** protected relay mutation since PR #60 — as soon as you deploy shadow (§5 step 1-2: `DESTINATION_BUDGET_HMAC_KEY` + deploy), any owner device traffic becomes your first shadow signal.

## Ask 4 — INV-DST-N01: ✅ unchanged

Client signs the EXACT user-entered destination in kind-7; zero client-side hashing/normalization as security input. Standing.

## Status board (app side)

| Item | Status |
|---|---|
| Phase A relay assertion + parity | ✅ merged (PR #60), 6/6 confirmed by BE |
| Phase C Loox V2 + mutation guard | ✅ merged (PR #61), 7/7 |
| 429/503 taxonomy handler | ✅ merged (PR #61) |
| Real-device QA (relay shadow) | ⏳ owner |
| `attestationRequired` flips (relay + link) | ⏳ lockstep after QA / fleet-V2 |
| Phase B destination client | ⏳ gated on DEC-DST-01 BE build (kind-7 vector freeze together) |

## Unresolved questions
None. Next sync point = DEC-DST-01 build slot (kind-7 vector freeze) + QA date from owner.
