# Private Email banner and creation UX review

User request: quieter colors, modest corners, appropriate icons, clearer short copy, no
banner disclosure arrow; label reusable addresses later in detail rather than during creation.

- Protagonist: the private addresses. The prerequisite is a soft warning with an explicit
  confirmation button; standing receive-only guidance is neutral and grouped directly below.
- Copy: short EN/VI/JA titles and bodies. Inbox is masked. No prohibited punctuation.
- Controls: confirmation is a 44pt button navigating to the same inbox detail. No enclosing
  NavigationLink means no disclosure arrow. Icons use Polaris alert/info with combined
  accessible copy. No new haptics. Creation retains quota/destination/capability checks.
- Shape: opt-in shared `VaultInfoBanner.subtle()`, Radius.sm, Space tokens, semantic opaque
  colors, contrast-adjusted text. Existing solid banners keep their default treatment.
- States: verification notice disappears for verified inboxes; neutral guidance remains.
  Reserved addresses retain status. Optional labels remain editable in AliasDetailScreen.
- Rendering: exported 24 simulator previews across 375/430pt, EN/VI, light/dark,
  default/XL/accessibility5; the accessibility cases also use increased contrast traits.
  Inspected representative narrow/wide and large-text cases. Fixed a title truncation found
  in the narrow accessibility render. The notices have no material or animation; Reduce
  Transparency/Motion behavior follows directly from their opaque static implementation.
- Preview fixture is intentionally offline, so a separate pre-existing blue offline banner
  appears above the two changed notices. This is fixture state, not a production probe result.
  Preview files: `/tmp/vaultify-private-email-previews/`.
- Validation: app/extension compilation and 25 existing alias/contrast tests passed. A
  temporary rendering exporter ran successfully and was removed after QA. EN/VI/JA catalog
  entries and whitespace checked. No production relay action or TestFlight release performed.
