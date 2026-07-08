# To Backend — Quick View: make it live on prod (go)

**Date:** 2026-07-08 · **From:** iOS app team. Staging is validated (schema-2 `exposure=beta` published,
the "Open on Computer" entry shows for the beta cohort). App is **GA-ready on `main`**. Below is the
prod sequence — safe to start now.

## App status
- `main` has the GA build: schema-2 manifest verifier, `cap-2026-02` pin, and (just merged, PR #74)
  **`assertionRequired = true`** — matching prod's `ASSERTION_MODE=required`. This is what makes the
  entry visible to GENERAL (non-beta) users once `exposure=ga`. The current TestFlight build predates
  PR #74 (`false`); it works for the **beta cohort** (beta ignores the assertion flag), but the build
  that goes to **App Store GA must be cut from `main`** (with PR #74).
- Prod trust chain verified live by us: signer-keyset `qv-session-production-202607:active` (root
  `cap-2026-02`), `service-state=active`, `ASSERTION_MODE=required`, manifest v3.

## Prod sequence (safe to run now)
1. **Publish prod manifest schema-2 `exposure=beta`** — mirror staging:
   ```
   SCHEMA_VERSION=2 QUICK_VIEW_EXPOSURE=beta bash resign-config.sh production
   ```
   **Safe for current App Store users:** we checked the live prod manifest — `share_link`,
   `private_email`, `quick_view` are ALL `enabled` (= bundled defaults). A pre-quick-view (schema-1)
   app that can't parse schema-2 falls back to bundled defaults → **identical behavior, no regression**.
   (Caveat: while schema-2 is live, an old app won't honor a future manifest that DEGRADES a capability
   — fine as long as everything stays default-enabled; revisit before using the manifest to disable
   anything for the not-yet-updated population.)
2. **Beta cohort validates on prod** (TestFlight): scan/enter code → approve → browser renders; App
   Attest register/assert on real devices (now enforced server-side at `required`). Collect verdicts
   (invalidKey, re-registration, latency).
3. **App Store GA release** of the `main` build (assertionRequired=true) — owner cuts it.
4. **Flip `exposure=ga`** once verdicts are clean and the GA build is live:
   ```
   SCHEMA_VERSION=2 QUICK_VIEW_EXPOSURE=ga bash resign-config.sh production
   ```
   Assertion is already `required`, so `ga` is the only remaining flip; general users on the GA build
   then see "Open on Computer".

## No app change needed from BE
- Enforcement stays server-side (worker rejects an upload without a valid assertion at `required`); the
  client always sends the App Attest headers when it can.
- `ASSERTION_MODE` (not `QUICK_VIEW_ASSERTION_MODE`) — acknowledged, no app dependency.

## Open questions
1. Confirm you'll publish prod `exposure=beta` now (step 1) so the current TestFlight beta cohort can
   exercise it on prod before the App Store GA build lands.
2. Any objection to the schema-2-on-prod compat note (§1 caveat)? We're satisfied it's a no-op today.
