# Memory Index

- [Vaultify test target](vaultify-test-target.md) — VaultifyTests unit-test target exists; pattern = in-memory VaultStore + adoptUnlocked fixed key; run via `make test`
- [P2 Persona+AutoFill plan](vaultify-p2-persona-autofill-plan.md) — INV-R03 isolation; extension can't see active persona (App Group mirror); seedScope allSpaces leak; 4 phases
- [P3 Alias Model plan](vaultify-p3-alias-model-plan.md) — local-only EmailAlias mirroring Persona; RelayFeature flag OFF gates .active; AliasAddress hides @domain pre-relay; phase 4 deferred
- [Persona↔Space partition plan](vaultify-persona-space-partition-plan.md) — Folder.personaId = partition key; active persona filters whole app; backfill→default; fail-closed INV-R03; 4 phases; primarySpaceID leak reconcile
- [Relay Destination + Alias Mgmt plan](vaultify-relay-destination-alias-mgmt-plan.md) — per-alias real email via rotateDestination(kind=3); activate=createAlias→rotate; backendMinted resumable; "Private email" write-back; AliasDetailScreen; 5 phases
