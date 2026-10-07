# Member feature implementation

## Implemented

- `ShareLinksScreen` creates through the existing QuickLink flow and manages only device-local links within their expiry period. Detail opens the source item and offers one confirmed revoke action. Failed revoke preserves the credential and record for retry. No historical copy action, fragment-key persistence, opened/consumed claim, expired archive, or invented server state.
- `SendToBrowserScreen` explains the existing `/v1/quick-view/open` receiver, chooses a scoped item, and enters the existing QR/code and signed approval ceremony. History contains only local timestamp/item/result. The signed exposure/cohort, capability, App Attest, and purchase gates remain intact. Cancellation generation and live ownership are revalidated after asynchronous work and before upload.
- Family lists actual outgoing shares for the active profile. The root explains what makes a person appear. The CTA chooses one saved item or a Space; the item route uses an explicit approval-only ShareAccessSheet entry without a fake resume email or Quick Link detour. Existing active management and unfinished resume are preserved. Pull-to-refresh uses OwnerShareRefresher, independently of vault-item sync.
- A single MemberFeatureProjection scopes roots, chooser, tile counts, links/history/shares by current canonical item ownership. A missing non-nil folder is excluded. Orphan revoke credentials remain in their store for existing vault-wide safety cleanup. Quota presentation explicitly says it applies across profiles.
- Hub tiles now lead to the named feature root. Accessibility sizes use a single-column grid. Metric labels wrap and content tile fills use live semantic tokens.

## Design DNA review

| Surface | Protagonist and action | Copy and layout | States and disclosure |
|---|---|---|---|
| Links root | Create and manage outgoing links; one bottom Create Link action | Native List grouping, wrapping title/expiry copy, device-only and expiry scope explicit | Empty and unavailable retain records; detail has source item action and one destructive menu |
| Browser root | Send chosen fields to an existing browser session; one bottom action | QR/code purpose first, receiver address selectable, history result readable | Exposure/operator/user/offline reasons separate from commerce; history never replays fields |
| Family root/person | Manage real item/Space relationships; one bottom Share with family action | Recipient labels and lifecycle descriptions wrap, account and approval prerequisites reused | Empty explains how relationships form; active/pending entry differs and refresh observes the live store |
| Scope/item chooser | Choose what to share from this profile | Full-row 44pt controls with Polaris icons and native navigation | Snapshot chooser excludes guard2-only items; Approval chooser delegates permission setup to existing ceremony |
| Hub | Find included feature and its current profile usage | Semantic fills, wrapping metrics, one column at AX sizes | Local profile metrics separated from vault-wide plan limits; service state text accompanies dots |

All new copy is supplied in `member-localizations.json` as EN source keys with VI and JA translations for Integration to merge into the single catalog. No new decorative or timed animation is introduced; native navigation handles spatial motion. Nothing waits for animation to enforce scope or lock policy.

## Validation

- Swift syntax parse passed for all changed/new Member files and the new tests.
- Nine MemberFeatureProjection regression tests cover nil primary Space, unfiled default ownership, unknown folder fail-closed, moved/deleted/orphan records, expiry without credential mutation, protected/future schema eligibility, real Family lifecycle/shared zone scope, history codec without replay data, stale Browser approval after profile/item movement, and cancellation outcome deduplication.
- Centralized workspace compile and test execution belong to Integration. Physical-device light/dark/theme-switch/375/430/XL/AX/VO matrix and two-iCloud-account live transport acceptance remain required runtime checks. No live share or TestFlight release is claimed by this change.
