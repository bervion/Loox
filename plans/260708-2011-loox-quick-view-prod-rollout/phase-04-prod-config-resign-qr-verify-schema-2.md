---
phase: 4
title: "Prod Config (resign + QR verify + schema-2)"
status: pending
priority: P1
effort: "owner/BE ops"
dependencies: [3]
---

# Phase 4: Prod Config — resign + QR verify + schema-2 publish

## Overview

Owner/BE ops: make prod config verifiable by the shipped app (`cap-2026-02`), confirm the QR fix is on
prod, and publish the schema-2 exposure manifest — but only AFTER Phase 3 puts the schema-2 verifier on
devices. BE handoff: `plans/reports/to-backend-260708-2011-quick-view-prod-finalization-handoff.md`.

## Requirements

1. **Re-sign prod config to `cap-2026-02`** (owner, root key): `resign-config.sh production`
   (schema-1 first). The app retired `cap-2026-01`, so until this runs the app rejects the live prod
   manifest + domain registry and falls back to bundled defaults. Verify: GET manifest + registry →
   `key_id=cap-2026-02`, signature valid.
2. **Confirm QR fix on prod** (BE): the `/open` worker on prod serves decodable QR (fix was verified on
   staging). Sanity: encode any string on prod `/open`, scan with the iPhone Camera app.
3. **Publish schema-2 exposure manifest** (owner) — ONLY after Phase 3 (schema-2 app on devices):
   `SCHEMA_VERSION=2 QUICK_VIEW_EXPOSURE=beta resign-config.sh production` (and staging). Keep `beta`
   (cohort) until Phase 5 gates clear. Never publish `exposure=disabled` for quick_view.
4. **Vector regen (non-blocking, BE):** regenerate SESSION/PAYLOAD/SAS vectors in base64url to match
   the live wire (app already decodes base64url; hex vectors are a test-representation legacy).

## Implementation Steps

1. Owner: `resign-config.sh production` (schema-1) → GET-verify both manifest + registry.
2. BE: confirm prod `/open` QR decodable; confirm prod `/open` hardened headers match staging.
3. After Phase 3 build is on devices: owner publishes schema-2 `exposure=beta` (staging then prod dark).
4. Verify a schema-2 device honors the published exposure (entry gated by manifest, not just the DEBUG
   override).

## Success Criteria

- [ ] Prod manifest + registry re-signed `cap-2026-02`, GET-verified
- [ ] Prod `/open` QR decodable + headers hardened
- [ ] Schema-2 `exposure=beta` published AFTER app-on-devices; schema-1 apps unaffected
- [ ] (Nice-to-have) vectors regenerated base64url

## Risk Assessment

- Publishing schema-2 before Phase 3 → schema-1 apps can't verify it (fall back to bundled). Strict
  ordering is the mitigation — do not publish schema-2 early.
