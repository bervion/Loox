---
phase: 2
title: "Browser Matrix QA (QV-A5)"
status: pending
priority: P1
effort: "0.5d + manual"
dependencies: [1]
---

# Phase 2: Browser Matrix QA (QV-A5)

## Overview

Manual, cross-team: end-to-end happy path + `/open` UX across the real browser matrix on live staging,
now that QR scanning works. Gate before TestFlight ship + prod flip.

## Requirements

- Browsers × OS: Chrome / Safari / Firefox / Edge × Windows / macOS / Linux (Safari macOS-only).
- Per cell: `/open` → QR scan (+ enter-code fallback) → SAS match → approve → browser renders fields →
  one-shot consume → `[Close & Clear]`.
- Signaling: SSE primary works; kill SSE → long-poll fallback still delivers "payload ready".
- Field-level TOTP: browser shows the current-code countdown and redacts at `valid_until`; other
  fields stay until the render TTL.
- Clipboard warning ("copied to THIS computer's clipboard"); render TTL 5 min; hidden auto-lock 2 min.
- QR scan reliability on the oldest supported iPhone + a low-brightness / glossy monitor.
- Confirm the `/open` hardened headers on staging (CSP `default-src 'none'`-style, COOP/COEP/CORP,
  `frame-ancestors 'none'`, `no-store`).

## Implementation Steps

1. Run the matrix on staging; record pass/fail + notes per cell.
2. UX findings → small app fixes directly (strings/spacing/countdown); protocol/render findings →
   escalate to BE before any prod flip.
3. Verify SSE + long-poll both deliver; verify TTL/auto-lock timings.
4. Produce a go/no-go verdict for TestFlight + prod.

## Success Criteria

- [ ] All matrix cells pass happy path + one-shot + clear
- [ ] SSE and long-poll fallback both verified
- [ ] Field-level TOTP countdown + redaction correct across browsers
- [ ] TTL / auto-lock timings match owner-locked values
- [ ] QR scan reliable on oldest device; go/no-go recorded

## Risk Assessment

- Browser quirks (Safari non-extractable WebCrypto keys, Firefox SSE buffering) are BE/web fixes —
  app team verifies + reports, does not patch web.
