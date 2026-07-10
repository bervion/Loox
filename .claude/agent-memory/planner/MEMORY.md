# Memory Index

- [Vaultify test target](vaultify-test-target.md) — VaultifyTests unit-test target exists; pattern = in-memory VaultStore + adoptUnlocked fixed key; run via `make test`
- [P2 Persona+AutoFill plan](vaultify-p2-persona-autofill-plan.md) — INV-R03 isolation; extension can't see active persona (App Group mirror); seedScope allSpaces leak; 4 phases
- [P3 Alias Model plan](vaultify-p3-alias-model-plan.md) — local-only EmailAlias mirroring Persona; RelayFeature flag OFF gates .active; AliasAddress hides @domain pre-relay; phase 4 deferred
- [Persona↔Space partition plan](vaultify-persona-space-partition-plan.md) — Folder.personaId = partition key; active persona filters whole app; backfill→default; fail-closed INV-R03; 4 phases; primarySpaceID leak reconcile
- [Relay Destination + Alias Mgmt plan](vaultify-relay-destination-alias-mgmt-plan.md) — per-alias real email via rotateDestination(kind=3); activate=createAlias→rotate; backendMinted resumable; "Private email" write-back; AliasDetailScreen; 5 phases
- [Loox UI/UX redesign plan](vaultify-loox-ui-ux-redesign-plan.md) — 13-đợt design→flow polish; 7 phase (P0 primitives→P5 sharing→P6 defer); giữ tab bar+header; plans/260710-2135-loox-ui-ux-redesign/
- [Loox Design DNA Controlled Reveal plan](vaultify-loox-design-dna-controlled-reveal-plan.md) — 10-DNA audit exec T1+T2+T3; 7 phase; ∞ gate NOT blocked (logo.svg:12 vector); P2/P3/P4/P5 parallel disjoint files; plans/260710-2304-...
