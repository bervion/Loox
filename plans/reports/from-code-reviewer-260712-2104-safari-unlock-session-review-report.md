# Safari Unlock/Session Security Review — feat/safari-unlock-and-item-list

Scope: `git diff main...HEAD` (commits `8012e7b`, `a034e06`). READ-ONLY review, no code changed.
Focus: `ExtensionSessionStore` lifecycle/invalidation, native→JS boundary, keychain hardening,
piggyback seeding, origin binding, concurrency/CI risk.

## Verdict

**Session lifecycle is fundamentally sound.** No Critical findings. Every invalidation path the
design requires is wired and verified (matrix below). Two issues need fixing: a TOCTOU where the
sliding rewrite can resurrect a just-cleared session (High), and missing sender gating in
`background.js` that must land before content.js gains real logic (Medium, trust-boundary).

## Invalidation matrix (all verified against code)

| Path | Wired at | Verified |
|---|---|---|
| TTL expiry, read-enforced + self-delete | `ExtensionSessionStore.retrieve` — `VaultifyCore/Keychain/ExtensionSessionStore.swift:80-83` | YES |
| 15-min cap enforced on WRITE | `save` clamps `min(ttl, maxTTL)` — `ExtensionSessionStore.swift:65` | YES |
| 15-min cap enforced on READ (tamper defense) | `window = min(payload.ttl, maxTTL)` — `ExtensionSessionStore.swift:79`; test `testOversizedStoredTTLIsClampedOnRead` | YES |
| Malformed payload self-deletes | `decode` nil → `backend.delete()` — `ExtensionSessionStore.swift:75-78`; bounds-safe (`count > headerLength` before any `readUInt64`) | YES |
| App `lock()` | `VaultSession.lock` — `Vaultify/Security/VaultSession.swift:157` | YES |
| App `lockToOnboarding()` | `VaultSession.swift:165` | YES |
| Vault erase | `AppEnvironment.eraseEverything → session.resetVault → BiometricKeyStore.delete()` (clears session, `BiometricKeyStore.swift:90`) AND `lockToOnboarding()` — double-covered | YES |
| Biometric disable / invalidation / re-provision | `BiometricKeyStore.delete()` leading `ExtensionSessionStore.clear()` — `VaultifyCore/Keychain/BiometricKeyStore.swift:86-93`; `store()` calls `delete()` first (`:35`) | YES |
| autoLock → `.immediate` switch | `SettingsStore.mirrorAutoLock` clears — `Vaultify/App/SettingsStore.swift` (didSet + init) | YES |
| `.immediate` never writes a session | `save(ttl <= 0)` deletes — `ExtensionSessionStore.swift:61-64`; `AutoLockTimeout.immediate.rawValue == 0` | YES |
| Device lock | Exactly `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — `KeychainStore.set`, `KeychainStore.swift:33`; not synchronizable (attr never set), `kSecUseDataProtectionKeychain` on every query | YES |

Key-to-JS boundary re-verified: `listItems` returns id/title/username + card brand/last4 only
(`WebExtensionRouter.listsData:163-174`); `copyValue` whitelist (`username/email/text`) gated
natively BEFORE any unlock (`WebExtensionRouter.swift:111-115`), double-checked in
`WebExtensionReader.copyableValue:81` (`!kind.isSecret`, `releasable` rejects
protected/guard2/SecretGuard); `status` always answers `locked: true` (no session-existence
oracle); key bytes never serialized into any response; no logging of key material anywhere
(handler logs `cmd` only). Level-2 key is never in the session — protected fields stay sealed.

---

## High

### H1. TOCTOU: sliding rewrite can resurrect a session after `clear()`
`retrieve()` reads, checks expiry, then **rewrites** the slide via `backend.write`
(`ExtensionSessionStore.swift:84-86`). The write path is `KeychainStore.set`
(`KeychainStore.swift:24-35`), which falls back to `SecItemAdd` when the item is absent.
Sequence, two processes:

1. Appex handler `retrieve()` reads a valid payload (T0).
2. App calls `lock()` / `BiometricKeyStore.delete()` / immediate-switch → `clear()` deletes the item (T1).
3. Appex slide-write executes (T2) → `SecItemAdd` **re-creates** the session with `lastActivity = now`.

Result: an explicit revocation (app lock, biometric invalidation, policy tightening, vault erase)
is silently undone; the no-biometric key stays readable for a full window (up to 15 min) after the
user locked. Window is milliseconds, but popup use is exactly when locks happen, and this is the
one class the design cannot tolerate (missed invalidation).

**Fix:** make the slide update-only. Add a `Backend.update` op implemented with `SecItemUpdate`
only (treat `errSecItemNotFound` as "session revoked" — do NOT add). `save()` keeps add-or-update
semantics; `retrieve()` uses update-only for the slide. Optionally: if the update reports
not-found, still return nil rather than the already-read key for strictness (the key was readable
at T0 anyway, so returning it is defensible; not re-creating the item is the mandatory part).

---

## Medium

### M1. `background.js` message hub has no sender gating
`browser.runtime.onMessage.addListener((message) => …)` (`VaultifySafari/Resources/background.js:39`)
accepts `listItems`/`copyValue` from ANY extension context — including `content.js`, which is
injected into every https page (`manifest.json` content_scripts). Today `content.js` is an inert
placeholder, and page JS cannot call the extension's `runtime.sendMessage`, so exploitation needs
a compromised content-script context (renderer bug). But once fill logic lands there (Phase 3),
a hijacked content script — with a live session — gets **silent, no-Face-ID** access to: all
matched logins' usernames for the page's own origin, ALL identity titles + copyable
username/email/text fields, and all card brand+last4. The security comment ("popup and content
scripts talk to it") documents the over-broad surface.

**Fix now (cheap):** gate vault commands on the sender being the popup:
`addListener((message, sender) => { if (sender.tab || !sender.url?.startsWith(browser.runtime.getURL(""))) return reject("forbidden"); … })`
and later carve explicit, origin-bound commands for the content script.

### M2. Tightening auto-lock (non-immediate) never shrinks a live session
`mirrorAutoLock` clears only for `.immediate` (`SettingsStore.swift`). A live session created at
15 min keeps `ttl = 900` in its payload; `retrieve` slides with the STORED ttl
(`ExtensionSessionStore.swift:79,84`), so changing 15 min → 1 min leaves a 15-min sliding window
alive indefinitely (until an app lock). The stricter policy the comment promises ("the stricter
policy applies at once") only holds for immediate.

**Fix:** clamp the read window to the live policy — `min(payload.ttl, configuredTTL(), maxTTL)` in
`retrieve` — or clear/rewrite the session on ANY `mirrorAutoLock` change, not just immediate.

### M3. Popup item matching inherits the over-broad AutoFill heuristic
`WebExtensionReader.itemsMatching` uses `item.matchesAutoFill(serviceIdentifiers: [host])`
(`WebExtensionReader.swift:63`), whose last clause is `other.contains(host)`
(`VaultifyCore/VaultReader.swift:141`). A phishing host `evilgoogle.com` contains `google.com`, so
the victim's Google login (title + username) is listed in the popup on the phishing page — a
phishing-legitimizer plus username disclosure into extension JS. Acceptable in the OS AutoFill
QuickType context; riskier in a popup listing. Pre-existing matcher, NEW exposure surface in this
diff.

**Fix:** for the web-extension path, match exact-host or true-subdomain only (the conservative
`matchesRelyingParty` shape at `VaultReader.swift:148-154`), leaving OS AutoFill behavior untouched.

---

## Low

- **L1. Fail-open default TTL when mirror absent.** `configuredTTL` returns 300 s when
  `auto_lock_seconds_mirror` was never written (`ExtensionSessionStore.swift:99-101`). A user on
  `.immediate` who hasn't launched the updated app gets a 5-min session minted after an extension
  Face ID. Presence WAS proven (Face ID), so impact is policy drift, not key exposure. Prefer
  `return 0` (fail-closed) for a missing mirror.
- **L2. `copyValue` is not origin-bound.** Any itemId × whitelisted kind releases a value
  (`WebExtensionRouter.copyValue`). IDs are UUIDs learned only from origin-scoped `listItems`, and
  identities/cards are global by design, so practical exposure is what listItems already granted.
  Consider restricting `copyValue` to identity-category items (the only popup flow using it).
- **L3. No key-length validation in `decode`.** A tampered 31-byte key round-trips and fails later
  in `AESGCM.open` (throws, items skipped — graceful). Add `key.count == 32` to `decode`'s guard so
  malformed items self-delete instead of surfacing as an empty popup.
- **L4. `enableBiometricUnlock` mid-session strands the session.** `store()` → `delete()` →
  `clear()`, and nothing re-seeds; next popup use costs one extra Face ID. Fail-closed, acceptable.
  Optional polish: re-seed after `store` succeeds (key is in hand).
- **L5. Future `lastActivity` accepted.** A payload with `lastActivity` in the future yields a
  negative interval and passes the window check. Writers are same-access-group, team-signed
  binaries that already hold the key, so no privilege gain. Optional: also reject
  `lastActivity > now + skew`.

## Informational / design confirmations

- **Sliding = unbounded absolute lifetime.** With use every <15 min the session never dies
  (test `testSlidingRefreshExtendsTheWindowOnEachHit` pins this). This matches the app's own
  sliding `lastActivity` model and the approved "SLIDING, hard-capped 15 min" (cap = per-window
  inactivity). If an ABSOLUTE 15-min cap was ever intended, the payload needs a `mintedAt` field —
  confirm intent; current behavior looks deliberate.
- **App force-quit doesn't clear the session** (no hook can run); it dies by TTL (≤15 min) or
  policy. Inherent to the design's "bounded session" trade-off.
- Piggyback ordering verified for ALL five unlock funnels — `unlock(password)` (:105),
  `unlockWithBiometrics` (:117), `createVault` (:80), recovery (`+Recovery.swift:46`), join
  (`+Join.swift:39`) — all route through `adoptUnlocked`, which seeds AFTER
  `migrateBiometricKeyToSharedGroupIfNeeded` (:181 → :186), so `store()`'s leading
  `delete()`→`clear()` cannot wipe the fresh seed. Ordering claim in the comment holds.
- Appex entitlements carry the shared keychain group (`VaultifySafari.entitlements:13`); origin is
  sourced exclusively from `browser.tabs.query` in the background page (`background.js:15-25`),
  never sender-supplied, https-only in JS AND re-validated natively (`httpsHost`,
  `WebExtensionRouter.swift:154-161`); native requests rebuilt from whitelisted keys only.
- Zeroization: `save` scrubs the encoded blob; `retrieve` scrubs read data + refreshed blob;
  `unlockedKey` secure-zeros the raw array after wrapping in `SecureBytes`
  (`WebExtensionRouter.swift:139-143`). Popup renders via `textContent` only; nothing persisted to
  `browser.storage`.
- Concurrency/CI: `nonisolated` annotations correct under `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`; keychain retrieve hops to a global queue via continuation; `beginRequest`'s
  `Task { @MainActor … }` keeps `NSExtensionContext` alive until `completeRequest`. No over-long
  expressions that threaten stable-Xcode type-check; explicit `import Security`/`Foundation`
  present. EN + VI `_locales/messages.json` both updated.

## Recommended actions (priority order)

1. **H1** — update-only slide write in `retrieve` (`SecItemUpdate`, never add).
2. **M1** — sender gate in `background.js` (popup-only for vault commands) before Phase 3.
3. **M2** — clamp read window to `configuredTTL()` (one-line in `retrieve`).
4. **M3** — conservative host matching for the popup list path.
5. L1/L3 — fail-closed default TTL; 32-byte key check in `decode`.

## Unresolved questions

1. Is the 15-min cap intended as per-window inactivity (current, sliding-forever) or absolute
   session lifetime? Current code + tests pin the former.
2. Should extension Face ID mint a session at all before the app has mirrored a policy (L1), or
   only ever piggyback on app-written policy?
