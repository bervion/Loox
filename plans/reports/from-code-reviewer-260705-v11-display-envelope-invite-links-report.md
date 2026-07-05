# Code Review — V1.1 slices: SharedDisplayEnvelope + Invite Deep Links

Branch `feat/sharing-v11-invite-deeplink`, commits fbe4b6f + daa9b90 (`git diff main...HEAD`).
Compile iOS+macOS green, 161/161 tests (per lead). Findings only, severity-ranked.

## Critical

None.

## High

**H1 — U9 (LOCKED) violated: LooxInvite records are never deleted — no GC path at all.**
U9 locks "delete after accept + after expiry". `acceptInvite` (`Vaultify/Services/Sharing/InviteLinkService.swift:89-124`) never deletes the record; no owner-side sweep exists anywhere. Expiry is enforced only client-side on read (`:107`) — CloudKit has no server TTL, so every invite record persists forever, and a link stays resolvable for the full 7 days even after acceptance. Structural note: public-DB records are deletable **only by their creator**, so the recipient *cannot* delete after accept — compliance requires owner-side deletion (on grant publish / revoke / periodic sweep of own invites). Confidentiality impact is bounded (ciphertext only), but this is a user-locked lifecycle decision left unimplemented and unflagged.

**H2 — Dead link = dead silence: `try?` swallows every acceptInvite failure.**
`Vaultify/App/VaultifyApp.swift:62` — `Task { try? await env.inviteLinks.acceptInvite(from: url) }`. Recipient taps an expired/withdrawn/malformed link → app foregrounds and *nothing happens*; they will retry, then blame the owner. All three `Failure` LocalizedError messages (with correct VI translations) are currently dead code — nothing ever surfaces them. This is the primary user flow of the feature shipping with zero failure feedback. Minimum fix: route the error to an alert/toast (pattern: `pendingTOTPImport`-style env field consumed by the shell). Success while locked is also silent (breadcrumb-only) — lesser, but worth a "invitation accepted" cue post-unlock.

## Medium

**M1 — U7 deviation (user-locked value): invite token is 160-bit, plan locks 192–256-bit.**
`InviteLinkService.swift:59` reuses `ApprovalConfig.opaqueName()` = 20 CSPRNG bytes hex (`VaultifyCore/Sharing/ApprovalConfig.swift:58-60`). 160 bits is not practically enumerable, but U7 explicitly says "random 192..256-bit token" and per review rules a user-locked numeric must not be silently narrowed. Fix is one line: mint `CryptoRandom.bytes(24...32)` hex for invites (do NOT widen `opaqueName()` itself — zone names elsewhere depend on its shape only loosely, but keep blast radius zero).

**M2 — `"Shared Item"` xcstrings key has NO Vietnamese value (and duplicates an existing key).**
`Vaultify/Features/Sharing/ShareAccessSheet.swift:224` uses `appString("Shared Item")`; the catalog entry for `"Shared Item"` is comment-only (no `vi`), while pre-existing key `"Shared item"` (lowercase i) already carries vi "Mục được chia sẻ". Missing VI = bug per project convention. Either reuse `"Shared item"` or add the vi value. Side note: this fallback title is sealed on the *owner's* device in the owner's locale — a VI owner sends "Mục được chia sẻ" to an EN recipient. Acceptable for V1.1; document it.

**M3 — U2's rename promise has no writer; `revision` is dead on both ends.**
The only publish site is `publishGrant` (`Vaultify/Services/Sharing/ApprovalShareService.swift:157-158`) with `revision: 1` hardcoded; there is no republish-on-rename path, and `fetchDisplayEnvelope` (`ApprovalRecipientService.swift:148-157`) never reads `revision` — the doc comment at `VaultifyCore/Sharing/SharedDisplayEnvelope.swift:13-15` describes out-of-order protection that no code implements (singleton record LWW is the only actual guard, which is fine *until* a cache exists). Renaming a shared item today changes nothing for the recipient. If rename plumbing is a planned later slice, downgrade to informational — flagging so it isn't forgotten; otherwise U2's core rationale ("rename = envelope update only") is structure without behavior.

## Low

**L1 — `expiresAtMs` at millisecond precision leaks exact mint time.** Plan A' says "expiresAt (coarse)". `InviteLinkService.swift:63` stores `nowMs + 7d` exactly → creation instant recoverable to the ms, correlatable with grant-zone activity. Round to the hour (or day).

**L2 — Public-DB metadata posture (accepted, note only).** Any authenticated user could write LooxInvite records (quota against the app) and — *if* a queryable index exists on the type, which JIT schema does not add by default — enumerate records and read system `creatorUserRecordID`, correlating invite volume per (opaque) creator. Record names `inv-` + 40 hex are not enumerable. All consistent with the plan's accepted A' posture and U9's evidence-driven relay stance.

**L3 — No AAD binding ciphertext↔token.** `AESGCM.seal` (`VaultifyCore/Crypto/AESGCM.swift:11`) has no AAD parameter; blob-swap across records would require creator write access, so not exploitable today — AAD = token would be free defense-in-depth if AESGCM grows an AAD overload later.

**L4 — `displayWebsiteHost` drops scheme-less URLs.** `ShareAccessSheet.swift:225-226`: `URL(string: "example.com")?.host` is nil, so most hand-typed website values silently produce no host in the envelope. Prefix `https://` when no scheme, or reuse whatever normalization AutoFill host-matching uses.

**L5 — Parser robustness (all fail-safe).** `token.count >= 32` guard vs actual 40-hex, no hex-charset check; `isInviteLink` host compare is case-sensitive (Safari normalizes, but `URL.host` preserves given case); `/i/<token>/extra` yields `lastPathComponent == "extra"` → record miss. Every path ends in `malformedLink`/`notFoundOrExpired`, so hardening only.

## Verified PASS (U-compliance + crypto)

- **U4** — public record = opaque `inv-<40hex>` name, fields `blob` (AES-256-GCM ciphertext of {shareURL, createdAt}) + `expiresAtMs`. No plaintext share URL, no PII, field names leak nothing. Comment at `InviteLinkService.swift:12-16` correctly frames the link as routing, not capability: share acceptance still gated by `publicPermission = .none` + email-looked-up participant (`ApprovalShareService.swift:78-85`).
- **U7 resolve contract** — token → public record → fragment-key decrypt → **real** CKShare URL → `CKFetchShareMetadataOperation` → `container.accept(metadata)`; never fabricates metadata; continuation fails closed (`shareUnavailable` when per-share result missing, `InviteLinkService.swift:136-140`). `alreadyShared` → success is correct idempotency.
- **U2 separation** — envelope is its own record type `ApprovalDisplayEnvelope`, singleton name `display-envelope`, carrying only ciphertext + opaque grantId; never inside the signed grant body.
- **Fragment delivery** — Universal Links hand the complete URL including the fragment via `NSUserActivity.webpageURL`; the fragment is never transmitted to the AASA host or landing page. Confirmed platform behavior; key stays client-side.
- **Crypto** — key = 32 CSPRNG bytes, `AESGCM.seal` enforces 32-byte length; base64url decode is padding/charset tolerant (`InviteLinkService.swift:150-157`); HPKE info `"Loox display envelope v1"` is distinct from all four existing domains and `CanonicalWriter` length-prefixes fields, so no cross-domain or concat-ambiguity collision (`ApprovalCrypto.swift:99-103`).
- **Fail-closed accept** — every error path throws before the breadcrumb/notification (`InviteLinkService.swift:122-123`); no partial state.
- **Display fetch is post-pin** — `fetchDisplayEnvelope` gates on `pinnedOwnerKey(zoneID:) == grant.ownerSigningPubKey` (`ApprovalRecipientService.swift:150`) and is only invoked in the fingerprint-confirmed `.ready` path; decrypt failure soft-fails to nil → neutral fallback.
- **iOS 17.6 floor** — async `modifyRecords`/`record(for:)`/`accept` (iOS 15+), `CKFetchShareMetadataOperation` (iOS 10+), `.onContinueUserActivity` (iOS 14+): all clear.
- **Offline fallback** — raw CKShare URL when minting fails (`ShareAccessSheet.swift:163-169`) matches the plan's two-tier posture: U4 forbids plaintext URL *in the public DB*, not handing the URL to the recipient directly.
- **Localization** — "This invite link isn't valid.", "This invitation has expired or was withdrawn." byte-match with vi values; "The owner stopped sharing this item." pre-existing with vi. (Exception: M2.)

## Recommended actions (priority order)

1. H2 — surface acceptInvite errors to the user (alert/toast via env), and a success cue.
2. H1 — owner-side invite GC: delete invite record on grant publish (accept implies grant flow) + sweep own expired invites on launch; or explicitly get user sign-off to defer U9 deletion.
3. M1 — 24–32-byte invite token (surface the U7 deviation to user either way).
4. M2 — fix "Shared Item" vi (or reuse "Shared item").
5. M3 — confirm rename-republish is a scheduled follow-up slice; otherwise wire it or trim the revision doc comment.

**Status:** DONE_WITH_CONCERNS
**Summary:** Crypto and resolve-contract are sound and U4/U2/U7-contract compliant, but two user-locked items are not honored (U9 delete-after-accept/expiry unimplemented; U7 token 160-bit vs locked 192–256) and dead links fail with zero user feedback.
