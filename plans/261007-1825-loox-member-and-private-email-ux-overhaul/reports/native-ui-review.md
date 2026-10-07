# Native Private Email and Member UI review

Date: 2026-10-07. Independent review; source owned by implementation agents. All actionable findings below are repaired in source. Final representative captures close the two observed accessibility truncations. This report records visual evidence and the five adversarial DNA questions per screen; it does not approve production infrastructure or external account behavior.

## Evidence and limits

- Contract read: `docs/design-guidelines.md`, `docs/design-dna-standard.md`, `Design System/tokens/`, grouped-row spec, iOS kit components. `docs/development-rules.md` absent.
- Required design intelligence searches run: password manager product; native minimal accessible style; readable Vietnamese typography; security palette. Existing native SF, Polaris and theme contract remains authoritative.
- [Native capture manifest](../assets/native/capture-manifest.json): 40 final render receipts, ten roots, 375pt EN light, 375pt VI light, 430pt VI dark, 375pt VI accessibility3 dark/high contrast (`/tmp/vaultify-ux-snapshots-latest.xcresult`; 12/12 snapshot cases passed). Final direct review covered 26 representative PNGs: every root at 375pt VI light and VI AX3 dark, EN overview/composer, and 430pt VI dark composer/member/alias/family. Images inspected without editing; these receipts are not automatically approved pixel baselines.
- [Mounted-app manifest](../assets/native-ui/capture-manifest.json): six final actual simulator screenshots for Inbox, Member destinations, native Unlink confirmation and preserved other Login. All six inspected directly; three UI cases passed on a fresh simulator (`/tmp/vaultify-ux-ui-clean.xcresult`). These include OS bars, navigation controls and safe areas.
- Static light receipts show white inline navigation titles. Actual mounted Inbox, Share Links, Browser and Family receipts show black readable titles. Treat static title color as a hosting limitation, not a shipping regression.
- The preserved-other-Login screenshot is functional evidence for unlink scope. Its existing generic Item Detail collapsed field rows are outside this feature-root layout review; that receipt does not certify those existing ellipsis behaviors.
- Source also reviewed for the domain picker, per-alias service list, legacy review, Login picker, record management, verification and privacy transitions. Full domain picker, those secondary sheets, below-fold content and every error/loading variant lack direct visual receipts in this matrix.
- No physical device, TestFlight, real recipient verification, CloudKit recipient pair, VoiceOver traversal, live theme switching, all seven accents rendered, iPad, XL or accessibility XXL review claimed. Reduce Motion/Transparency runtime settings are not enabled by these captures.
- Body-role numeric acceptance passed: one test, 504 combinations, four builtin themes × seven accents × three body roles × six content surfaces, all ratios ≥4.5 (`/tmp/vaultify-ux-unit-clean.xcresult`). This numeric coverage does not substitute for rendering every accent or checking live theme switching.

## Findings and repair status

| Finding | Evidence | Status |
|---|---|---|
| Paused alias labeled actively forwarding | `ForwardingInboxDetailScreen.routingSection` included paused aliases in the success label | Fixed in source; mounted Inbox shows GitHub Work as Forwarding paused |
| Member See all hit area below 44pt | Header button lacked minimum frame | Fixed in source with `Metric.hitMin` |
| Unlink exposed as management row, wrong confirmation haptic | Linked-service detail list and success haptic | Fixed in source: one overflow action, 44pt labeled menu, error haptic on destructive confirmation |
| Share Link overflow missing accessible purpose | Icon-only record toolbar | Fixed in source: Manage share link label, semantic glyph, 44pt frame |
| Meaningful Day copy below normal-text contrast | `0x949497`: 3.025:1 on white, 2.709:1 on grouped canvas, approximately 2.13:1 on Member tiles. Small success status 4.135:1 on white | Fixed with opt-in secondaryBody/successBody/warningBody roles, guarded to 4.5:1 on six content surfaces. Final supporting copy/status readable; 504 numeric combinations pass |
| Composer selected type truncated at accessibility3 | Earlier AX3 receipt showed selected value Dùng c…ịch vụ | Fixed: all three selected values use a stacked, wrapping Menu label. [Final AX3](../assets/native/composer-375-vi-dark-accessibility.png) shows full Dùng cho một dịch vụ on two lines |
| Inbox Hide email truncated beside Copy | Earlier AX3 receipt showed Ẩn em… | Fixed: explicit accessibility VStack and wrapping labels. [Final AX3](../assets/native/inbox-375-vi-dark-accessibility.png) shows full Ẩn email and Sao chép email |
| New footer and native value copy retained system gray | Section explanations; service Website/Forwards to; Member Profile | Fixed in source with semantic supporting text and primary values. Final mounted Links/Browser, Inbox and service detail confirm stronger hierarchy |
| Multiple notices in one screen state | Capability plus verification plus Receive-only in overview; capability plus Receive-only in alias/composer | Fixed in source: one actionable notice takes priority; standing Receive-only guidance becomes ordinary contextual footer while blocked. Final offline visible states show one capability notice. Pending/available notice ranking source-reviewed; standing footer below fold |
| Secondary Family/chooser variants retained older body roles and 2pt row gaps | Populated Family status; Family scope and item-chooser supporting footers; two child-stack spacings | Fixed in source with successBody/secondaryBody and Space.s1. These populated/secondary variants have no direct visual receipts |

## Per-screen adversarial answers

### Private Email overview

1. **Protagonist:** find the address and manage its use. Services first, reusable addresses second, then linked services and receiving settings. Offline banner explains unavailable actions; saved addresses stay useful.
2. **Copy:** EN/VI labels describe service versus reusable use correctly. Long addresses wrap at 375pt. Labels, statuses and explanatory copy are distinct; no prohibited punctuation in new fixed UI copy. Fixture names are user data.
3. **Controls:** address and linked-services rows have 44pt minimum targets. Recipient reveal has its own 44pt labeled control. One Create action when permitted; settings/navigation stay quiet.
4. **Layout:** native grouped List, semantic surfaces, token spacing/type. AX3 visible labels and addresses reflow; one long offline explanation consumes substantial vertical space but remains readable and scrollable.
5. **States:** captured populated/offline. Source includes empty groups, disabled creation, unavailable domains and verification prerequisite. Source now ranks one actionable notice, with ordinary Receive-only guidance while blocked. Standing guidance is below the capture fold.

### Composer

1. **Protagonist:** create one address with an understandable purpose and destination. Optional label/site/Login association are grouped; domain and recipient get separate contexts.
2. **Copy:** short native title resolves the user's original heading truncation. EN/VI fit at regular 375pt. Domain appears on a separate value line. Final AX3 selected type wraps completely on two lines, closing the former native selected-value truncation.
3. **Controls:** native menus/fields and one Create, Retry or Confirm action. Errors preserve reservation context. All three selected-value rows share wrapping value/type treatment; arbitrary longest selected Login/inbox names still need fixture-specific runtime coverage.
4. **Layout:** native scaffold and Form, no invented palette. Source disables immutable reservation choices while setup resumes. Placeholder labels are native TextField labels; persistent filled-field context merits a mounted input review.
5. **States:** captured optional-empty fields with verified recipient/offline. Reservation retry, invalid website, conflicting Login and verification gate checked in source, not each visually exercised here.

### Domain picker

1. **Protagonist:** choose the suffix for a new address.
2. **Copy:** unavailable signed domains explicitly explain readiness; existing-address domain preservation is stated. Hostname is separate from display name. No synthetic active loox.pw claim.
3. **Controls:** full 44pt domain rows; unavailable choices disabled; selected available domain gets check glyph. Selection persists explicitly.
4. **Layout:** semantic surfaces and vertically wrapping values. Invalid draft selection remains visible with a warning instead of silently changing the address suffix.
5. **States:** source covers one/many/no creatable domains and unavailable signed entries. Full picker has no direct screenshot; do not mark its visual matrix complete.

### Alias detail

1. **Protagonist:** use this address. Address/status and one Copy, Activate, Finish or Resume action lead. Management is in overflow; linked services and receiving detail follow.
2. **Copy:** original address remains complete, wrapped, with short inline title. Last confirmed destination and selected inbox distinguish server acknowledgment from pending choice.
3. **Controls:** primary full-width action, 44pt overflow and linked-services row. Recipient reveal deliberate. Pause explains all services using this address; permanent delete confirms consequences.
4. **Layout:** semantic grouped content, reusable field/value and recipient components, token spacing/type. Dark card/canvas separation visible.
5. **States:** active/offline captured; AX3 top portion readable. Copy/retry, pending destination, unresolved domain, paused/delete reviewed in source. Below-fold controls and receive-only text need scroll receipts.

### Forwarding Inbox detail

1. **Protagonist:** identify the actual inbox and understand its verification/routing. Full locally stored recipient visible on deliberate unlocked entry solves the user's original ambiguity.
2. **Copy:** verified/pending/unverified states explicit. Mounted receipt distinguishes paused alias from active forwarding after repair.
3. **Controls:** Reveal/Hide and Copy are at least 44pt high; native overflow manages deletion. Copy requires revealed unlocked state. Final AX3 receipt confirms full adjacent-control labels after explicit vertical reflow.
4. **Layout:** identity/status/actions grouped. Default marker and related addresses separated. Value wraps fully at large text.
5. **States:** verified detail captured; source handles missing inbox, pending check/resend, throttling and deletion restrictions. Real email-link return behavior belongs to verification testing, not static visual approval.

### Linked services, global and per address

1. **Protagonist:** find saved Login records using an address. Global list contains three fixture services; per-address source filters by alias and adds explicit Link entry.
2. **Copy:** source says only vault-linked records appear. No account-discovery claim. Service/site/address are separate lines and wrap at 375pt/AX3.
3. **Controls:** full 44pt navigation rows; Link a login and Review saved logins are explicit actions. Legacy matches require confirmation before changing data.
4. **Layout:** native grouped service rows and semantic labels. Polaris globe is a functional icon, not an invented provider logo.
5. **States:** populated global list captured. Empty/global/per-alias, legacy candidates and local conflict repair checked in source. Per-alias list and legacy sheets still lack direct receipts.

### Linked-service detail

1. **Protagonist:** understand one saved association and choose its management destination. Service/site/address lead; Open Login and Manage Private Email supply context.
2. **Copy:** unlinking accurately says forwarding and external service account remain unchanged. Receiver masked here; full Inbox reachable through private-email detail.
3. **Controls:** Unlink lives in one labeled 44pt overflow menu. Final mounted receipt shows the native confirmation, with vault-only removal explained; cancel and confirm UI test passed.
4. **Layout:** full values wrap; native LabeledContent reflows vertically at AX3. No shrinking secret/address typography.
5. **States:** normal relation captured. Missing Login/alias disables mutation; stale relation produces an actionable local alert. Actual cancel/confirm behavior belongs to UI/regression tests.

### Loox Member

1. **Protagonist:** understand saved resources and reach the appropriate feature. Saved and included-feature sections remain clear; Share Links, Browser and Family now have their own destinations.
2. **Copy:** VI titles wrap instead of ellipsis at regular phone widths. Usage units and offline state named. Fixture Personal is a user-provided name.
3. **Controls:** feature tiles exceed 44pt. See all now has 44pt minimum. Tile accessibility supplies feature name, metric and service state; colored dot is not the only state signal.
4. **Layout:** two columns regular phone, one column AX3, adaptive regular-width source. Nested radius uses concentric relationship. Semantic fills follow theme; fixed settings-badge colors are documented exemptions.
5. **States:** local resource counts and offline feature metrics captured. Paid plan/header and long real persona names are source-reviewed only. Existing member-name two-line/0.7 shrink floor remains, needing longest-name runtime review.

### Share Links

1. **Protagonist:** create/manage an expiring field-sharing link. Purpose, current persona and local history are explicit; it does not route to notification inbox.
2. **Copy:** honest expiry-period/local-device wording avoids implying an opened or consumed link remains usable. History does not claim to retain its full URL/key.
3. **Controls:** one Create action when available; selection opens existing creation ceremony. Record revocation in labeled overflow with confirmation after root repair.
4. **Layout:** native List and safe-area primary action. Copy wraps at regular VI and AX3. Final mounted receipt confirms readable semantic explanatory/footer copy and primary Profile value.
5. **States:** empty/offline captured and actual mounted title readable. Populated/expired/one-time record/error/revoke variants require their specific runtime coverage.

### Send to Browser

1. **Protagonist:** start a browser transfer and understand recent local attempts. Real viewer destination is useful task context; it is not presented as a diagnostic API setting.
2. **Copy:** instructs browser page then QR/code then field choice. History avoids implying browser activity or retained fields/session keys. EN/VI wrap.
3. **Controls:** one Send action when exposure and capability permit. Hidden rollout has an explicit explanation; historical rows do not offer misleading replay.
4. **Layout:** grouped purpose/current-persona and recent-attempt sections. Actual mounted nav title readable. URL wraps rather than clipping.
5. **States:** rollout-unavailable empty history captured. Create, QR, typed code, approve/upload and cancellation reviewed elsewhere. Public-service operation not invoked for this review.

### Family

1. **Protagonist:** share with a person and manage existing relationships. Empty state states the relationship comes from item/Space sharing, avoiding a fictional billing-family roster.
2. **Copy:** share purpose and current persona explicit; one-time invitation versus active-use counts distinct in source. EN/VI longest primary wraps.
3. **Controls:** one full-width Share with family action in thumb zone. Item/Space selection routes through Approval Mode ceremony. Rows have full 44pt-plus hit areas.
4. **Layout:** semantic canvas, calm empty state, native safe-area action; no glass content cards. AX3 CTA wraps, content scrolls.
5. **States:** empty state captured/mounted. Populated people, waiting/active shares, one-person detail and real cross-account acceptance require their own receipts. No successful iCloud sharing inferred from the empty UI.

## Privacy, accessibility and motion source checks

- Recipient disclosure is ephemeral: inactive scene, lock, email mutation and exit conceal; foreground does not restore prior reveal. Inbox deliberately reveals once on an unlocked detail visit.
- Icon-only recipient/alias/inbox/record menus have meaningful localized labels after repairs. `VaultIcon` hides decorative glyphs; feature tiles combine name/metric/state. VoiceOver traversal still needs runtime testing.
- Reveal calls use `Motion.standard` through `.vault(...reduceMotion:)`; conceal has no delaying animation. Alias copy uses shipped `CopyMorphIcon` and clipboard service owns the copy haptic.
- New content cards are solid semantic fills. Native navigation/control material owns platform accessibility behavior. Reduce Transparency runtime acceptance remains open.
- EN/VI rendered in captures; JA is catalog work rather than this visual review. Automated translation completeness and placeholder parity belong to integration checks.
- Family child-stack spacing now uses Space.s1. Remaining preserved numeric debt: some old Hub optical metrics and Tile badge-offset literals. These are existing style debt, not demonstrated new interaction failures; strict all-touched token acceptance should track them separately.

## Remaining coverage and unresolved questions

1. Capture domain picker, per-alias list, legacy/Login sheets, long selected Login/inbox names and below-fold Receive-only guidance. Populated Family/person details, share records and dynamic/error/loading variants remain subset coverage. Available/pending notice hierarchy is source-verified, not visually exercised in this offline fixture.
2. Physical Debug/TestFlight mail, App Attest, CloudKit pair, accessibility XXL/XL, VoiceOver, live theme switching, all accents rendered, Reduce Motion/Transparency and larger platforms remain outside this independent native visual review.
3. No unresolved product-design question or active visible clipping finding in the reviewed final subset. Preserved older optical-token literals are tracked above; this report is not a claim that every pre-existing touched-screen literal satisfies the complete token contract.

Reference cross-check: [Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md) used only for applicable accessibility, state and interaction principles. Web/React implementation rules do not apply to this native SwiftUI app.
