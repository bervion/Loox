# Phase 10 — Personas + Profile

**Status**: pending · **Wave**: W2 · **Owns**: `Personas/*`, `Profile/*` (14 surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Profile = "who am I in this app right now". Personas = "manage my identities and their private emails".

## Cluster hotspots
- **ProfileScreen / ProfileSectionCard / ProfileAvatarView**: avatar (image/letter, camera badge → PhotosPicker);
  Persona switch menu (check active); Identity + Payment cards share structure — protected values show
  "••••••••" but copy the real value; empty states ("No identity yet") intentional; tap-to-copy single haptic.
- **PersonaSwitcherScreen / PersonaAliasesScreen / AliasEditorSheet**: persona rows (icon+name+policy caption+
  check), swipe Edit/Delete; delete-block alerts honest ("You need at least one identity."). Editor: Type +
  Privacy (Standard/Isolated/Strictly-anonymous) with dynamic footer.
- **AliasDetailScreen / AliasDomainPicker / ForwardingInboxScreen / AffectedAccountsScreen**: alias status
  labels (Forwarding active / Tap to activate / Paused / Draft) via roles; forwarding verify chips (Verified/
  Awaiting/Not verified) semantic; rotation progress "x of y"; relay error alert "Couldn't reach the relay."
  (honest, no `!`). `CapabilityBannerView` reused (Phase 1, read-only) for offline/maintenance — accent-soft,
  never red.
- Address rows: masked `@domain` handling per relay flag; long alias addresses wrap/truncate gracefully at SE;
  "Forwarding to {masked email}" fits VI.

## Deliverables / Todo
`reports/findings-phase-10.md` · `strings-manifest-phase-10.md` · fixes.
- [ ] Protocol answers (14). [ ] 6 greps. [ ] Alias/forwarding status colors semantic.
- [ ] Delete-block alert honesty. [ ] Long-alias SE clip test. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; protected values masked but copy real; status labels role-colored; capability banner
accent-soft not red; EN+VI. Risk: alias screens gate on online-feature flags — presentational fixes only,
don't touch relay/capability logic (Med×Med).
</content>
