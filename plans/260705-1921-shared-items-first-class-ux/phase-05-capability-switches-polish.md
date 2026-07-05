# Phase 05 — Capability switches + share sheet polish (V6)

## Overview
Priority P2 · Status: pending · Independent. Both capability kinds are binary today →
switches, not pickers. Popup reserved for genuinely >2-option controls (none exist yet).

## Related code
- Modify: `Vaultify/Features/Sharing/FieldCapabilityRow.swift`
- Reference: `.toggleStyle(.themed)` (applied globally at app root — plain `Toggle` inherits it)

## Implementation steps
1. `FieldCapabilityRow`:
   - value field → `Toggle("Share", isOn:)` mapping `.value(.none) ↔ .value(.shared)`.
   - totp field → `Toggle("Ask each time", isOn:)` mapping `.totp(.none) ↔ .totp(.askEachTime)`.
   - Row layout: field label + kind caption left, Toggle right; extra-protected fields stay
     excluded (current behavior — verify the sheet's existing guard).
2. Footer copy already explains semantics — re-check it still reads correctly under switches.
3. Keep the enum-based `FieldCapability` untouched (wire format is kernel territory — UI-only change).
4. Localization EN+VI for new short labels.

## Success criteria
- Config step shows switches; toggling maps to identical capability dictionaries as before
  (unit-test the binding mapping).
- No popup/Menu remains in the capability list.
