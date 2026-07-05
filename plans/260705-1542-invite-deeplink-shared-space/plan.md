---
title: "Sharing V1.1 — opaque invite rendezvous, universal link, Shared-with-Me space"
description: "Recipient UX overhaul per user architecture review 2026-07-05: A' opaque public rendezvous (NO email hash, NO plaintext share URL), encrypted DisplayEnvelope (NO grant v2 title), universal link invite.looxpassword.com, system Shared-with-Me space. Push = hint, inbox = truth."
status: pending
priority: P2
branch: "(new branch AFTER PR #27 merges + baseline tag)"
tags: [sharing, cloudkit, public-db, universal-links, cloudflare, ux]
blockedBy: ["PR #27 two-device QA", "PR #27 merge", "baseline tag"]
created: "2026-07-05T15:42:00+07:00"
updated: "2026-07-05T15:50:00+07:00 — user verdict applied (see USER-LOCKED DECISIONS)"
---

# Sharing V1.1 — opaque rendezvous, universal link, Shared-with-Me

## USER-LOCKED DECISIONS (2026-07-05 — do NOT reverse)

| # | Decision | Verdict |
|---|----------|---------|
| U1 | Shared-with-Me = system aggregate space (non-deletable, projection over shared DB + grants; NO ownership mutation; separate detail route) | GO |
| U2 | **NO Grant wire v2 for itemTitle** — authorization grant and presentation metadata have different lifecycles. Display data lives in a separate **encrypted `SharedDisplayEnvelope`** bound to grantID | LOCKED |
| U3 | **NO SHA256(email) routing key** — low-entropy dictionary-enumerable PII fingerprint in public DB + normalization/identity ambiguity | NO-GO |
| U4 | **NO plaintext CKShare URL in public DB** — "only B can accept" ≠ harmless; URL is an invitation capability/relationship artifact → always inside the encrypted envelope | NO-GO plaintext |
| U5 | D1 = **A' Opaque Public Rendezvous**: random 256-bit inboxID + recipient-sealed, sender-signed, expiring invite envelope over CloudKit public DB + CKQuerySubscription | GO |
| U6 | **Push = wake-up hint; public-DB inbox = source of truth.** Name the thing Invite Inbox SYNC (reconcile on launch/foreground/push/account-change; dedup by inviteID) — never treat missed push as lost invite | LOCKED |
| U7 | Universal link `invite.looxpassword.com/i/<random-192..256-bit-token>` (never sequential, never email-derived). Resolve MUST follow the CloudKit contract: token → rendezvous record → original CKShare URL → `CKFetchShareMetadataOperation` → validate expected participant/Loox binding → accept. Never fabricate metadata | GO strong |
| U8 | Order: two-device QA → fix release blockers only → merge PR #27 → **tag baseline** → NEW branch for V1.1. No invite architecture inside the V1 PR | GO strong |
| U9 | Invite lifetime 24h–7d (bootstrap artifact, not a grant); delete after accept + after expiry; dedup; blocked-sender ignore; local rate-anomaly awareness. If real-world public-DB abuse appears → THEN evaluate Cloudflare relay (evidence-driven, not now) | LOCKED |
| U10 | INVITE_DISCOVERED ≠ IDENTITY_VERIFIED ≠ GRANT_ACTIVE — auto-invite must NOT shortcut the C4/C5 trust ceremony (fingerprint/TOFU stays) | LOCKED |

## Architecture (A' — Opaque Public Rendezvous)

**B side (existing Loox user):** on Approval-Mode enable, generate `inviteInboxID = random 256-bit`
(NOT derived from PII). Publish an `InviteInboxDescriptor { participant CK-identity binding, inboxID,
recipientEncryptionPublicKey, protocolVersion, keyGeneration, signature }` so an inviter who ALREADY
resolved B as a CKShare participant can discover the inbox. Subscribe
`CKQuerySubscription(recordType == LooxInvite && recipientInboxID == myInboxID)`.

**A side:** after participant lookup (existing CKShare add-participant path — the SAME resolution),
resolve CK participant identity → B's descriptor → inboxID + encryption key. Write:
`LooxInviteRecord { recordID: random opaque, recipientInboxID, ciphertext, senderKeyID (opaque),
protocolVersion, expiresAt (coarse) }`. Ciphertext = `InviteEnvelopeV1 { inviteID, shareURL,
shareRecordBinding, ownerParticipantID, recipientParticipantID, senderSigningPublicKeyRef,
createdAtUnixMs, expiresAtUnixMs, nonce }` sealed to B's key, signature over canonical(envelope
context + ciphertext binding) by A's signing key. **Public DB sees: opaque IDs, ciphertext, timing,
version. NOT: email, share URL, item title, sender display name.**

**B not a Loox user:** no descriptor → fallback = external invite link (universal link / iMessage /
AirDrop / copy). Two tiers, one primitive each — don't force one mechanism to solve every recipient.

**Display metadata (U2):** `SharedDisplayEnvelope { grantID, title, subtitle?, iconHint?,
websiteHost?, updatedAt, revision }` — encrypted to recipient, authenticated, bound to grantID;
owner updates it independently of the authorization grant (rename ≠ capability mutation, no re-sign
of grant, no wire bump). Until it ships, rows display localized "Shared Item" fallback.

## Phases

| # | Nội dung | Ghi chú | Status |
|---|----------|---------|--------|
| 0 | **ADR set**: Public Rendezvous v1 · Opaque Inbox Identity · Encrypted Invite Envelope · Push-is-hint | chốt trước khi code | ✅ (U1-U10 table) |
| 1 | **Shared-with-Me space** (aggregate; "Shared Item" fallback title) + `SharedDisplayEnvelope` | KHÔNG grant v2 | ✅ envelope + Home row + system space in Items Spaces (cc8b9fb) |
| 2 | **Universal Link**: FE AASA + `/i/*` landing (runbook); app Associated Domains + NSUserActivity + PendingInviteRouter; QA theo Apple Universal-Links technote (developer mode), không chỉ curl | capability/profile regen CHỈ trên branch V1.1 | ✅ verified on-device (scene-delegate routing fix) |
| 3 | **Public Rendezvous SPIKE** (gating): B subscription → A write → B signal → fetch; locked-screen behavior; **Production/TestFlight environment SỚM** (forum-signal về query-subscription push khác biệt trên public DB production) | spike fail → dừng, escalate | 🔶 spike code shipped (f3602f4, DEBUG section in iCloud Sync settings) — AWAITING 2-device run + Production/TestFlight verdict |
| 4 | **Encrypted Invite Envelope**: recipient seal + sender signature + expiry + replay + dedup | sau khi transport chứng minh | ⏸ gated on Phase 3 verdict |
| 5 | **InviteInboxReconciler** — MỘT reconciler cho launch/foreground/push-hint/manual (H7, không fork sync stack) + inbox UI | | ⏸ |

### Mid-flight scope additions (user-driven, shipped)
- iMessage compose pre-filled recipient (3f2a020) · cold-launch approval-sheet fix (8b8a1f1)
- Owner alert = CKQuerySubscription on ApprovalRequest creation only — phantom-alert fix (563edfc)
- **Single-confirm pairing (USER-LOCKED, amends ADR-4/U10 ceremony UX):** B auto-TOFU-pins on first
  grant fetch; A one-tap "Activate Sharing" là enforcement point duy nhất; safety code hiển thị cả 2
  bên để đối chiếu tùy chọn; key CHANGE vẫn bị reject (d5fd430)

## Bootstrap spike questions (Phase 3 phải trả lời)
- Resolve CK participant identity → descriptor: record đặt ở đâu (public DB keyed theo gì — recordName
  từ CK userRecordID? — phải KHÔNG phải PII), collision/rotation (keyGeneration), multi-device B.
- CKQuerySubscription trên public DB production: fire-on-creation reliability, throttling, locked device.
- Quota/abuse posture thực tế của public DB với write từ mọi user.

## Prerequisites (user)
- Apple portal: Associated Domains capability (khi V1.1 branch bắt đầu) → match regen.
- Cloudflare DNS `invite.looxpassword.com` + AASA + landing theo `cloudflare-invite-domain-runbook.md`
  (FE làm trước được, độc lập app).

## Out of scope V1.1
Web approval / Loox Access / CLI-SSH grants (universal-link domain là nền cho tương lai đó — U7 note).
