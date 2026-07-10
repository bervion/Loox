# Phase 11 — Sharing: owner flow + approval + recipient

**Status**: pending · **Wave**: W2 · **Owns**: `Sharing/*` EXCEPT `QuickView/*`, `QuickLink*`,
`SharedWithMeScreen.swift` (16 surfaces). Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
ShareAccessSheet = "grant exactly what I mean, to exactly this person". Approval = "confirm it's really them".
Notifications = "what needs my attention".

## Cluster hotspots (many-sheet cluster — walk EVERY state)
- **ShareAccessSheet + ShareStepperModel (9-step machine)**: Choose / Checking / Blocked / Config / Creating /
  Waiting / Fingerprint / Done / Failed. EACH step is a screen — verify none exposes scaffolding; blocked
  (fail-closed) copy honest (2 distinct messages: no-iCloud vs no-notifications) + Check-Again.
- **FieldCapabilityRow / PasskeyCapabilityRow**: per-field permission rows — toggle / menu (Off / Ask each time
  / Hand over…); non-shareable fields at 50% opacity via role, not raw gray. "Hand over" dialog red button
  "Hand Over — Can't Be Taken Back" honest about forward-secrecy (no `!`, no `—` — use two clauses/lines).
- **TrustFingerprintView**: safety-code mono block large + legible at SE; "Activate Sharing" ≥44.
- **ApprovalRequestSheet**: 5-digit match card ("It should match the code on their screen."); Approve-with-
  Face-ID; states idle/authenticating/waiting-fresh-window/issuing/finished/failed — sheet not dismissible
  while processing; auth-fail → `Haptics.error` (single, from auth path).
- **RequestCodeView**: idle→requesting→waiting("Match code: NNNNN")→approved/rejected/interrupted/expired/
  failed; every terminal state offers Request-Again (no dead end); approved code tap-to-copy single haptic.
- **NotificationsScreen / InviteInboxBehaviors / ShareInviteSentSheet / ShareRecipientDetailSheet /
  ShareResumeStepperSheet**: empty "No notifications" intentional; sections (invitations/approvals/sent/recent);
  revoke dialog honest ("giá trị đã giao không rút lại được"); swipe-to-revoke reachable.
- Interpunct sweep: any "Shared · {date}" style → real layout, not `·`.

## Deliverables / Todo
`reports/findings-phase-11.md` · `strings-manifest-phase-11.md` · fixes.
- [ ] Protocol answers (16). [ ] 6 greps. [ ] Walk ALL 9 share steps + all RequestCode terminal states.
- [ ] Hand-over/revoke copy honesty (no `!`/`—`/`·`). [ ] Non-shareable dim via role. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; every state-machine step intentional (no dead ends); destructive/hand-over copy
honest about irreversibility; auth/copy haptics single-fire; EN+VI. Risk: sharing state machines are
security-critical (High×High) — presentational fixes ONLY; never alter grant/verify/publish logic or the
fail-closed gates. This is the largest cluster — if a single agent nears 200K tokens, split owner-flow vs
notifications/approval into 11a/11b (still disjoint files).
</content>
