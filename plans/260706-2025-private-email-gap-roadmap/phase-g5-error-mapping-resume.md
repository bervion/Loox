# G5 — Error mapping polish + Resume Forwarding

Priority: medium. Status: pending (Resume BLOCKED on BE contract freeze).

## Error mapping (proposal §26 — do now)

Replace the single generic relay error string with typed mapping in the UI layer:

| Backend | Behavior |
|---|---|
| 401 | "Couldn't verify this device. Unlock Loox and try again." (repair path if repeated) |
| 409 nonce_replay | silent: new nonce, retry once; then generic failure |
| 409 epoch_stale | silent: refresh principal, re-sign, retry once (spinner only) |
| 409 alias_exists | already handled (re-mint loop) — keep |
| 429 | "Too many requests…" + respect Retry-After, backoff+jitter, never tight-loop signed retries |
| offline | "You're offline. Connect to the internet to change this private address." — existing alias metadata stays visible offline |

Auto-retry lives in `RelayService.send` (bounded: once per failure class per command).

## Resume Forwarding (blocked)

BE must freeze: `createAlias(alias_id = existing DISABLED)` → response? status→ACTIVE? same
address/ownership? destination preserved or must re-rotate? Contract test vector required.
App-side plan (defensive, per proposal §17): resume = createAlias(same local-part) →
rotateDestination(current inbox) → status .active. UI label "Resume Forwarding" (VI: "Tiếp tục
chuyển tiếp") — never "Create".

## Success

- Unit tests for retry-once semantics (nonce/epoch) with a stubbed client; 429 backoff test.
- Resume ships only after BE vector lands; until then paused aliases show no resume affordance.
