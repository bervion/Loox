# G4 — Create Login integration (flagship)

Priority: highest UX value (proposal author's #1). Status: pending. Depends: G2.

## UX

In the login editor's email/username context, show a suggestion affordance:

```
✦ Create private email
  Unique for github.com · <Persona>
```

- Suggestion is display-only — INV-PE03: rendering it never allocates a backend alias.
- Explicit tap → provisioning coordinator: createAlias → rotateDestination (reuses
  RelayService.activate resumable path) → fill address into the field → on item save, bind
  `boundVaultItemID = item.id` (+ `boundDomain` = registrable domain hint).
- Returning login (item already has a bound alias): suggest reuse, never mint a new one.

## Reuse priority (proposal §10)

1. exact `boundItemId` match
2. same persona + registrable-domain match
3. persona reusable alias (explicit pick, not auto)
4. create fresh site alias
5. real email fallback — only if persona policy allows

## Persona policy (minimal V1)

`PersonaEmailPolicy` derived from persona kind (no new stored schema yet):
- standard personas: suggestions on, real-email fallback allowed.
- strictAnonymous: fresh alias default, **no real-email fallback, no cross-persona
  suggestions** (INV-PE01 — candidates excluded, not down-ranked).

## Domain matching

Registrable domain (eTLD+1) helper — reuse/extend existing AutoFill host-matching logic if
present; never naive last-two-labels. `boundDomain` remains a hint only.

## Crash safety

Alias provisioned but item save abandoned → alias stays valid & unbound (do NOT auto-delete);
it appears in the Private Email list and can be bound later or deleted manually.

## Success

- Editor suggestion appears only with network-independent rendering; provisioning only on tap.
- Bind-on-save test; reuse-priority unit tests; strictAnonymous exclusion test.
- Full suite + `make check` green; strings EN+VI.
