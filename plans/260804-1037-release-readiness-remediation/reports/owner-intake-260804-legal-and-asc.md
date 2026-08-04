# Owner intake — legal values (OPEN-3) and App Store Connect state (Phase 5)

Two forms. Nothing in either may be inferred, assumed, or filled in by an implementer.
Phase 1B stays blocked until Form A comes back; Phase 5's submission half stays unverified
until Form B does.

---

## Form A — legal values for the policy pages

These map one-to-one onto the placeholders currently sitting in
`content/policies/{en,vi}/{privacy,terms}.mdx` on `looxpassword-web` `main`.

### A1. Controller identity

| Field | Placeholder in repo | Value |
|---|---|---|
| Legal entity / data controller name | `[LEGAL ENTITY NAME]` | |
| Registered / business address | `[REGISTERED ADDRESS]` | |
| Company or tax registration number, if it must appear | not yet placeheld | |
| Data-protection contact | currently `privacy@looxpassword.com` | confirm this mailbox is monitored, or replace |

### A2. Governing law

| Field | Placeholder | Value |
|---|---|---|
| Governing law | `[GOVERNING LAW]` | |
| Courts / jurisdiction | `[JURISDICTION]` | |
| Consumer-rights carve-out wording, if counsel wants specific language for EU/VN | inline in Terms | |

### A3. Liability

| Field | Placeholder | Value |
|---|---|---|
| Proposed liability clause / cap | `[LIABILITY FLOOR]` | |

Current draft reads: liability limited to the greater of what the user paid us in the
previous twelve months, or `[LIABILITY FLOOR]`, with the usual carve-outs for death,
personal injury, fraud, and anything not limitable by law. Counsel should confirm both the
shape and the number.

### A4. Retention matrix — per service, based on production behaviour

The draft currently has a single `[RETENTION PERIOD]` placeholder for Firebase and prose
elsewhere. That is not good enough. Each row needs a real answer, and "we do not know yet"
is an acceptable answer that changes the wording rather than being papered over.

| Service | What is retained | Retention | Source of truth |
|---|---|---|---|
| Quick Link / Quick View encrypted snapshot | ciphertext blob | **see note** | `loox-link` / `loox-quick-view` D1 + cleanup job |
| Relay alias record | alias, state, verified destination inbox | | `loox-relay` D1 |
| Relay mail in transit | forwarded message | | relay worker |
| Entitlement record | subscription state keyed to a random token | | `loox-entitlement` D1 |
| Firebase Analytics events | product-interaction events | | GA4 property setting |
| Firebase Crashlytics | crash reports | | Crashlytics setting |
| Cloudflare request logs | edge logs incl. IP | | Cloudflare zone config |
| CloudKit private database | user's own encrypted vault | user-controlled | n/a, Apple-hosted |

**Quick Link note — blocking constraint.** The merged policy currently says a link
"is deleted after expiry". `docs/fe-cloudflare-spec.md:42` marks the cleanup job
maintenance-only, so that claim is **not verified**. Until someone confirms the cron runs in
production on a known schedule, the policy must say only that the link **stops being
served** after it expires or is revoked, and must not assert deletion. A fix for this
wording is queued as its own change; see the reply that accompanied this form.

Two ways to close it:
- Verify the cron, record the schedule, and write the real retention period; or
- State honestly that expired snapshots stop being served immediately and are purged on a
  periodic cleanup, without promising a deletion deadline.

### A5. Sign-off

| Field | Value |
|---|---|
| Counsel / reviewer name | |
| Date reviewed | |
| Any wording counsel changed from the draft | |

---

## Form B — App Store Connect state to verify (Phase 5)

Subscription group: **"Loox Membership", group id `22241495`**.
Source of truth for the identifiers is `VaultifyCore/Subscription/LooxTier.swift:85-90`.

### B1. The four product IDs

```
com.bervion.vaultify.subscription.max.annual      Loox Max Annual     P1Y
com.bervion.vaultify.subscription.max.monthly     Loox Max Monthly    P1M
com.bervion.vaultify.subscription.plus.annual     Loox Plus Annual    P1Y
com.bervion.vaultify.subscription.plus.monthly    Loox Plus Monthly   P1M
```

### B2. Per-product checklist

Fill one row per product. All four must be identical in shape.

| Check | max.annual | max.monthly | plus.annual | plus.monthly |
|---|---|---|---|---|
| Product state (Missing Metadata / Ready to Submit / Approved) | | | | |
| Review screenshot uploaded | | | | |
| EN display name + description | | | | |
| VI display name + description | | | | |
| Price tier set, per-territory availability correct | | | | |
| Attached to the app version being submitted | | | | |

VN prices the owner previously kept, for comparison against what is live now:
Max Annual **349k**, Max Monthly **49k**, Plus Annual **199k**, Plus Monthly **29k**.
The local `Loox.storekit` shows 34.99 / 4.99 / 19.99 / 2.99 USD, but that file is a **dev
fixture and not evidence about ASC**. Verify against the console.

### B3. Group-level checklist

| Check | Value |
|---|---|
| Subscription group id matches `22241495` | |
| Group display name and localizations (EN, VI) complete | |
| Upgrade/downgrade levels: Max = level 1, Plus = level 2 | |
| Family Sharing OFF on all four | |
| Intro offer: 7-day free trial, **Max Annual only**, 175 countries, no end date | |
| Billing grace period: 16 days, paid-to-paid, enabled in **both** production and sandbox | |
| App Store Server Notifications V2 URL points at the entitlement service | |
| Tax category set | |

### B4. Gate for flipping `launchEnabled`

Recorded so the flag is not flipped by habit. Per the revised decision, the submitted build
ships with `launchEnabled = false`.

| Gate | Done |
|---|---|
| Terms and Privacy live, no placeholders, counsel signed off | |
| All four products submittable, screenshots uploaded | |
| Purchase + restore E2E pass on a **signed TestFlight build**, backend in the loop, run recorded in `reports/` | |
| §8.2 attach E2E recorded | |
| Backend modes observed, not assumed | |
| Real-device matrix green | |

### B5. Non-subscription ASC items that also block submission

| Item | Done |
|---|---|
| App description, subtitle, keywords, promotional text (EN, VI) | |
| Support URL, marketing URL, copyright, categories, age rating | |
| App Review notes and contact (name, email, phone) | |
| iPhone 6.9" screenshots | |
| **iPad 13" screenshots** (Branch A confirmed, so these are mandatory) | |
| App Privacy questionnaire filed **after** the code defaults are frozen | |
| Apple Silicon Mac availability **turned off** | |
| `metadata/apple/ja` excluded from deliver automation | |
