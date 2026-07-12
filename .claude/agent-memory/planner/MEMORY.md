# Memory Index

- [Vaultify test target](vaultify-test-target.md) — VaultifyTests unit-test target exists; pattern = in-memory VaultStore + adoptUnlocked fixed key; run via `make test`
- [P2 Persona+AutoFill plan](vaultify-p2-persona-autofill-plan.md) — INV-R03 isolation; extension can't see active persona (App Group mirror); seedScope allSpaces leak; 4 phases
- [P3 Alias Model plan](vaultify-p3-alias-model-plan.md) — local-only EmailAlias mirroring Persona; RelayFeature flag OFF gates .active; AliasAddress hides @domain pre-relay; phase 4 deferred
- [Persona↔Space partition plan](vaultify-persona-space-partition-plan.md) — Folder.personaId = partition key; active persona filters whole app; backfill→default; fail-closed INV-R03; 4 phases; primarySpaceID leak reconcile
- [Relay Destination + Alias Mgmt plan](vaultify-relay-destination-alias-mgmt-plan.md) — per-alias real email via rotateDestination(kind=3); activate=createAlias→rotate; backendMinted resumable; "Private email" write-back; AliasDetailScreen; 5 phases
- [Loox UI/UX redesign plan](vaultify-loox-ui-ux-redesign-plan.md) — 13-đợt design→flow polish; 7 phase (P0 primitives→P5 sharing→P6 defer); giữ tab bar+header; plans/260710-2135-loox-ui-ux-redesign/
- [Loox Design DNA Controlled Reveal plan](vaultify-loox-design-dna-controlled-reveal-plan.md) — 10-DNA audit exec T1+T2+T3; 7 phase; ∞ gate NOT blocked (logo.svg:12 vector); P2/P3/P4/P5 parallel disjoint files; plans/260710-2304-...
- [Adversarial UI sweep all screens plan](vaultify-adversarial-ui-sweep-plan.md) — 187 View structs vs design-dna-standard; 16 phase (P0 registry→P1 primitives→P2-14 parallel disjoint→P15 verify); xcstrings orchestrator-owned; plans/260711-0024-...
- [Safari Web Extension plan](vaultify-safari-web-extension-plan.md) — 3rd appex MV3 background PAGE (not SW); G1 FaceID-headless + G2 Tuist folder-ref gates block all; only getFillPayload returns values; plans/260712-1500-...
- [AutoFill extension hardening plan](vaultify-autofill-extension-hardening-plan.md) — plan 260712-1500-autofill-extension-hardening, 7 phase; TRAPS: recoveryKdf lockout, reg flags replayed as assertion flags; KDF→constrained 32MiB + opportunistic migration
- [Ambient share status plan](vaultify-ambient-share-status-plan.md) — plan 260712-1500-icloud-invite-accept-ambient-status, 7 phase; silent accept push+local notif+verify gate (S1 LOCKED implement); dirty-flag over CKQuery; pin≠verified split
