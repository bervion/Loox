# Decisions — 260727

Answers to the open questions in `plan.md`. These are settled; phase files defer to this file.

---

## 1. Send the sharer's name — YES

Adds a third piece of metadata to the wire alongside `category` and `title` (phase-03).

**Source: `Persona.displayName`** (`VaultifyCore/Models/Persona.swift:24`). One human owns
several personas; the active persona's display name is the right answer to "who shared this",
and it is already the identity the owner picked for that context.

**Do NOT use** `SharedCredentialsCache.ownerName` — that is a CloudKit zone-owner record-ID
component for Approval Mode, not a human name. There is no separate profile-name setting; the
Localizable strings "Your name" / "Name" belong to the Identity *item*, which is vault data,
not a profile.

### One hard constraint

`Persona.displayName` is identity-bearing and sealed at rest (`PersonaSecret`). Two persona
configurations exist specifically to avoid being identified:

- `PersonaKind.pseudonymous` / `.anonymous`
- `PersonaIsolationPolicy.strictAnonymous`

Sending the display name from those personas defeats the reason they exist. **Rule:** send the
name only when the active persona is `.personal`, `.professional` or `.custom` AND its policy
is not `.strictAnonymous`. Otherwise omit the field and let the page fall back to a neutral
line. This is a correctness requirement, not a nicety — phase-03 must implement it and
phase-04 must design the fallback copy.

Exposure is otherwise unchanged: the value rides inside the E2E-encrypted payload and reaches
only the browser the owner deliberately approved.

---

## 2. `/open` is multilingual, with a language picker in the header

The design has no picker; add one in the page's own visual language (glass pill, matching the
back-to-Loox chrome at the top-left of the design).

### Approach

The page cannot use `next-intl` — it is a Worker-served static document, not the Next app. It
needs its own small string table in the page JS, keyed the same as the marketing site's
`src/messages/{en,vi}.json` so copy stays in sync by convention.

- Initial language: `navigator.language`, falling back to `Accept-Language`, defaulting to EN.
- Persist the choice in `localStorage` on `open.looxpassword.com`. A language preference is
  not session data and does not violate the page's no-persistence posture, but it must be the
  ONLY thing the page ever stores.
- Switching language must re-render text in place. It must NOT reset the session, restart a
  countdown, or re-request anything.

### The nuance that will look like a bug

Field **labels are not UI chrome** — they arrive inside the payload, already localized to the
*owner's* in-app language (`LooxLinkEnvelope.swift:53-55`: *"labels are localized to the
owner's in-app language so the recipient sees 'Mật khẩu'/'Password' as the owner does"*).

So a Vietnamese viewer of a share from an English-speaking owner sees Vietnamese chrome around
English labels. That is correct — the label is the owner's data and translating it would
misrepresent what they sent. Phase-04 should make the boundary read as intentional (the item
card is clearly "their content"), and phase-08 must not attempt to translate labels.

---

## 3. Import the app's Polaris icons

`ItemCategory.iconAsset` (`VaultifyCore/Models/ItemCategory.swift:47-58`) already maps every
category to an icon that exists in the app:

| Category | Asset |
|---|---|
| login | `ic_globe` |
| note | `ic_note` |
| card | `ic_credit_card` |
| identity | `ic_identity_card` |
| sshKey | `ic_key` |
| recoveryCodes | `ic_refresh` |
| securityQuestions | `ic_question_circle` |
| custom | `ic_metafields` |

Source files: `Vaultify/Assets.xcassets/PolarisIcons/ic_*.imageset/ic_*.svg`.

**Delivery:** the page CSP forbids external assets, so these must be same-origin. Build one
inline SVG `<symbol>` sprite in the page HTML and reference it with `<use href="#ic_...">`.
Do not fetch them, do not data-URI them individually, and do not add an `img-src` exemption.

Copy the eight files into the web repo rather than reaching across repos at build time — the
two projects deploy independently and a cross-repo path would break the Worker build. Keep a
note in the web copy pointing back at the app as the source of truth so a future icon change
is a deliberate re-sync, not a silent drift.

Check the Polaris licence before shipping to the public web; the app already ships these, but
a website is a different distribution surface.

---

## 4. Timers stay as they are

The design's 90-second figure is a mock, not a spec. **Do not change any timer.** The deployed
session TTL and render TTL stand.

Consequence for phase-04: the expired-state copy cannot say "90 seconds". Either drop the
number from `expB` or bind it to the real value at render time. Copy is not allowed to assert
a duration the code does not enforce.

The design remains a UI reference only. Anything in it that implies a behaviour change —
the QR regeneration action is the other one — is treated as a proposal needing its own
verification, not as an approved requirement.
