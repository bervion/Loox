# Phase 1A + 1B — frontend implementation report

- Date: 2026-08-04
- Repo: `/Users/bervion/Developer/Projects/frontend/looxpassword`
- Branch: `fix/legal-routes-and-privacy-claims` → **merged to `main`** via
  [PR #5](https://github.com/bervion/looxpassword-web/pull/5) at 2026-08-04T04:15:46Z
  (`a5d7965`, 17 files, +888/-176)
- Status: **DONE_WITH_CONCERNS** — merged, but **not deployed**, and the policy pages still
  carry six legal placeholders (OPEN-3).

The work was cut onto a fresh branch off `origin/main` rather than the checked-out
`feat/quick-view-open-redesign`, which carries two unrelated, unpushed Quick View commits.
Zero file overlap: that WIP is entirely inside `workers/loox-quick-view/`.

## Scope item missed

**Phase 1A.4, the contact-form honesty fix, was not implemented and this report did not
say so.** `src/components/contact-form.tsx:29` still calls `setSent(true)` unconditionally
after attempting the `mailto:` navigation, so the form claims success even when nothing was
sent. Caught by the second reviewer, not by this report. It remains open in `phase-01`.

## Known gap introduced by this change

`claims-gate.sh` forbids the literal string `starter template`, but **not** the placeholder
tokens this PR introduced. Deploying today would publish `[LEGAL ENTITY NAME]`,
`[GOVERNING LAW]` and friends to the live policy pages with both gates reporting green.
Add the six tokens to `FORBIDDEN` before the next deploy.

## 1A — routing

`src/middleware.ts` now permanently redirects the short legal URLs to their canonical
`/policies/*` pages, following the existing `/open` and `/o` vanity-path pattern rather
than `next.config.ts` redirects, because that pattern is already proven on the
OpenNext/Cloudflare deployment.

The alias map is generated from `routing.locales`, so adding a locale cannot silently
drop an alias. `localePrefix: 'as-needed'` is handled: the default locale is unprefixed,
others carry `/<locale>`.

Verified against a local dev server:

```
/terms        308 -> /policies/terms          /vi/terms     308 -> /vi/policies/terms
/privacy      308 -> /policies/privacy        /vi/privacy   308 -> /vi/policies/privacy
/security     308 -> /policies/security       /vi/security  308 -> /vi/policies/security
/policies/terms 200   /policies/privacy 200   /vi/policies/privacy 200
/open         302 -> https://open.looxpassword.com/   (unchanged)
```

**308 is deliberate.** Builds already in users' hands hardcode
`https://looxpassword.com/terms`, and an app binary cannot be edited after shipping. The
alias has to keep resolving for every version of the app that has ever pointed at it.

`src/app/sitemap.ts` needed no change — it already emits only the canonical
`/policies/<slug>` URLs, so the aliases will not compete for indexing.

**Side effect worth noting:** deploying this alone fixes the P0-02 / 3.1.2 blocker for the
*existing* build too. Repointing `LooxMembership.termsURL` at the canonical path (Phase 1C)
is still worth doing to avoid a redirect hop, but it is no longer the thing standing
between the app and a working legal link.

## 1A — claims

| File | Change |
|---|---|
| `src/messages/{en,vi}.json` | `metaTitle`, `metaDescription`, `hero.sub` — "No servers" / "zero backend" replaced with "No vault on our servers" |
| | `trust.t2/d2` — "No tracking / Zero analytics, zero third-party SDKs" → "No ad tracking / No ad identifiers. Analytics stay off unless you turn them on." |
| | `trust.t3/d3` — "Zero-backend / No servers worth hacking" → "No user database / Nothing to breach: we hold no accounts and no readable vaults." |
| | `trust.d4`, `faq.items[1].a`, `download.requirements` — "ciphertext only" corrected; iCloud sync also carries plaintext folder icon/colour/sort and device name/model |
| | `why.c1d` — "There is no home to phone" → "The key never leaves your device" |
| | `why.c2t/c2d` — "No one to hack / The safest server is the one that does not exist" → "Nothing to steal / No accounts and no user database. What syncs is ciphertext we have no key for." |
| | `about.stats` — "0 trackers or analytics" → "0 ad identifiers"; "100% stays on your device" → "100% of your vault, encrypted on device" |
| `src/components/home-compare.tsx` | Removed the "No analytics or tracking SDKs" row and its `CMP` entry |
| `content/blog/{en,vi}/share-access-not-secrets.mdx` | Removed "no password rotation required"; corrected "the credential never leaves the encrypted vault" to "stays end-to-end encrypted and is never shown to them" |

### The comparison row was removed, not reworded

`home-compare.tsx` rendered a ✓ for "No analytics or tracking SDKs" against six **named**
competitors while the app ships Firebase Analytics and Crashlytics. That is comparative
advertising, and any honest rewording would still be an unsupported claim about six other
products. Removing the row eliminates both problems. If a defensible replacement row is
wanted later, it needs evidence for every column, not just ours.

### A bug introduced and caught

Removing the row exposed `const vals = ri === 9 ? priceRow : CMP[ri]` — a hardcoded index
that silently blanks the price row once `rows.length` changes. Now derived from
`rows.length - 1`. Verified: `$19.99 / $35.88 / $59.88` and `199.000₫` still render.

## 1A — gates

`scripts/claims-gate.sh` previously checked only `/` and `/vi`, which is how
"no password rotation required" stayed live on the blog while the gate reported success.
It now sweeps 18 pages (home, about, faq, download, all three policies, both blog posts,
each in both locales), collapses whitespace so a phrase split across source lines is still
caught, matches case-insensitively, and covers 21 phrases including the Vietnamese
equivalents and the literal string `starter template`.

New `scripts/routes-gate.sh` asserts 200 on 9 canonical pages and a permanent redirect
with the right `Location` on 6 aliases. Both are wired into `scripts/deploy-marketing.sh`
before the existing purge step's verification, and exposed as `pnpm routes:gate`.

A bug in the first draft of the routes gate is worth recording: `read -r code location <
<(curl … -w '%{http_code} %{redirect_url}')` returns non-zero because curl's `-w` output
has no trailing newline, and under `set -euo pipefail` that killed the whole script
silently — it printed nothing and exited 0-looking. Now parsed with string expansion.

### Gate results

Against **production** (pre-deploy, correctly failing):

```
routes-gate: 6 aliases 404      → FAILED
claims-gate: violations on /, /vi, /about, /vi/about … → FAILED
```

Against the **local dev server** with these changes:

```
✅ claims gate passed (21 forbidden phrases absent on 18 pages)
✅ routes gate passed (9 canonical pages, 6 aliases)
```

## 1B — policy content

All six MDX files rewritten from the verified data inventory, not from the product pitch.
Every "starter template" blockquote deleted; `lastUpdated` moved to 2026-08-04.

**Privacy** now states plainly, per surface: what stays on device; what iCloud sync writes
and which fields are *not* encrypted (folder icon, colour, sort order, timestamps, and the
device name, marketing model and app version from `DeviceRegistryService.publish()`);
analytics off by default with the exact event contents; Crashlytics on by default;
**the Google favicon lookup and what it reveals over time**; Quick Link's 30-day maximum
and the fragment-held key; the relay's verified destination inbox as the one directly
identifying record; breach-check k-anonymity; subscription state keyed to a random
`appAccountToken`; a named processor table (Apple, Google ×2, Cloudflare); GDPR legal
bases; per-category retention; rights; children; transfers.

Note the policy correctly says folder **names** are encrypted. The source audit claimed
they were plaintext; verification showed they live inside `FolderRecord.sealed`.

**Terms** now cover the App Store EULA relationship, the no-recovery reality, acceptable
use, and full auto-renewing subscription clauses: plans, payment, renewal timing, trial
forfeiture, cancellation through Apple, refunds handled by Apple, price changes, and the
billing grace period. It states explicitly that lapsing never locks, deletes or withholds
data you already created — which matches the verified gate behavior and pre-empts the
"data hostage" rejection.

**Security** documents the real key hierarchy (Argon2id → vault key → AES-256-GCM,
Extra Password as an independent second layer, recovery key), and names the fields that
are deliberately *not* encrypted rather than implying everything is sealed.

## Blocked / not done

- **OPEN-3.** Six placeholders remain and must be filled before this is publishable:
  `[LEGAL ENTITY NAME]`, `[REGISTERED ADDRESS]`, `[GOVERNING LAW]`, `[JURISDICTION]`,
  `[LIABILITY FLOOR]`, `[RETENTION PERIOD]`.
- **Counsel sign-off.** The content is accurate to the code; it has not been legally
  reviewed.
- **OPEN-5.** The Quick Link retention sentence says "deleted after expiry". Confirm the
  cleanup cron is actually live in production, or soften it.
- **hreflang cross-linking** between the `en` and `vi` policy pages was not added — it is
  SEO polish, not a blocker.
- **Nothing is deployed.** These changes are in the working tree only.
- **Not committed** — the repo is on `feat/quick-view-open-redesign` and the project's
  git workflow is PR-based.

## Verification run

```
pnpm typecheck                      clean
pnpm exec eslint <touched files>    clean
JSON validity, en + vi              valid
compare.rows 9 / CMP 8 + price row  consistent
```

`pnpm lint` reports 3 errors and 12 warnings, all pre-existing in `workers/loox-relay`
and `workers/loox-quick-view`, none in any file touched here.
