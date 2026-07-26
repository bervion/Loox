# Phase 04 — CI simulator janitor (separate PR)

Root causes (verified): name-vs-state `simctl list devices Shutdown` bug (sweep never worked), UDID exported to GITHUB_ENV only after boot (cancel window leaves Booted orphans), worker deaths skip always().

## Changes
- `scripts/ci/create-simulator.sh`
  - Sweep first: `simctl list devices --json` → delete every device named `Vaultify Quality *` in ANY state (`shutdown || true` then `delete || true`).
  - Export `SIMULATOR_UDID`/`SIMULATOR_NAME` to `GITHUB_ENV` immediately after `simctl create`, before boot.
  - `trap` on ERR after create: delete the just-created sim on script failure.
- `.github/workflows/ci.yml`
  - Delete step: if `$SIMULATOR_UDID` empty → fall back to the same JSON all-state name sweep; fix the stale comment.
- One-time manual hygiene (owner, optional): `xcrun simctl delete unavailable` reclaims 11 dead iOS-26.2 devices (~part of 13G).

## Validation
- Shellcheck-clean; dry-run the sweep locally against a dummy "Vaultify Quality test" sim in Booted and Shutdown states.
