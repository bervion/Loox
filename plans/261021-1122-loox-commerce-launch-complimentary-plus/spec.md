# Final implementation spec: commerce launch, 750-day complimentary Loox+, and a 1-year free trial on Loox Max

Base is `main` @ v1.57.2. This review was read-only. I re-checked the critiques against the source: `KeychainStore.swift:16-39`, `LooxFeatureTile.swift:148`, `LooxHubScreen.swift:175-185`, `LooxTier.swift:30-50`, `LooxAcquisitionPaywallView.swift:329-345` and `:405-420`, `LooxPaywallScreen.swift:109-125`, `AppEnvironment.swift:388-402`, `VaultifyApp.swift:170-173`, the `Localizable.xcstrings` key `%lld days` (JA `%lld 日`, a rotation label), and `PrivacyInfo.xcprivacy` (no PurchaseHistory today). Product choices are marked **[decision]**.

**Why Loox+ cannot use an Apple trial.** Apple's longest free trial is 1 year. So the 750 days for Loox+ has to be a grant inside the app. Only the 365 days for Max can be an Apple introductory offer.

## 0. Core model

| Concept | Source | Who reads it |
|---|---|---|
| `storeTier` | Verified StoreKit only. The Apple Max trial counts as `.max`. | Analytics `subscription_tier` |
| `paidTier` (new) | DEBUG override, otherwise `storeTier` | `isSubscriber`, the "Your plan" label |
| `isSubscriber` (new) | `paidTier > .free` | Paywall routing, Restore success, hub plan state, member seal |
| `complimentaryActive` (new, cached) | Grant resolved and `isActive(now)` at the last resolve | `tier`, analytics `complimentary_plus` |
| `tier` (changed, effective) | DEBUG override, otherwise `max(storeTier, complimentaryActive ? .plus : .free)` | Every quota, gate and title read |
| `complimentaryEndsAt` (new) | The grant's end date, but only while the grant is what gives the user Loox+ | "Free until" text in the paywall and hub; the Loox+ billing note |

The complimentary tier never goes to the backend. Attach and payload only run when there is a verified transaction (`LooxEntitlementCoordinator.swift:111-121`, `:148`, `:231-243`). **Do not add the grant to attach or to the payload.**

### Call sites that switch to `isSubscriber` / `paidTier`
- `LooxPaywallScreen.swift:51`: use `isSubscriber`.
- `LooxPaywallScreen.swift:82`: `LooxTierLabel(tier: env.entitlements.paidTier, …)`.
- `LooxAcquisitionPaywallView.swift:497`: `if env.entitlements.isSubscriber`. Without this, Restore reports success for every user during the 750 days.
- `LooxHubScreen.swift:72`: the plan section gets three states (§2.6).
- `LooxHubScreen.swift:131`: `if env.entitlements.isSubscriber { LooxMemberSeal(tier: env.entitlements.paidTier) }`.
- Analytics: `VaultifyApp.swift:170-173` and `AppEnvironment.swift:398-401` both go through one helper (§2.3, §2.8).

### Call sites that keep the effective `tier` (no change)
- Gates: `QuickLinkView.swift:197-199`, `QuickViewApprovalSheet.swift:80-82`, `WatchtowerScreen.swift:296-297`, `PersonaSwitcherScreen.swift:63-65`, `PersonaAliasesScreen.swift:148-150`.
- Hub: `LooxHubScreen.swift:22-23`, `:117`, `:175-186`, `:289-295`, `:377-381`.
- `LooxQuotaScreen.swift:10-11`.
- `ProfileScreen.swift:22-24` and `:63`.

## 1. New files

### 1.1 `VaultifyCore/Subscription/LooxComplimentaryGrant.swift` (~40 lines)
```swift
import Foundation

/// Complimentary Loox+ (owner decision 261021): every device gets Loox+ quotas
/// free for 750 days from the first launch of the version that ships it, so a
/// new user has long enough to learn the app. Granted IN-APP: no StoreKit, no
/// Apple trial, no card. Device-local and never sent to the backend. After it
/// ends the user falls back to Free quotas unless they subscribe; tier changes
/// never touch vault data.
///
/// Days are fixed 86_400-second spans (same rule as `RotationStatus`), so the end
/// instant does not move with time zone or DST. A start in the future is clamped
/// by `LooxComplimentaryGrantStore`, never here.
nonisolated struct LooxComplimentaryGrant: Equatable, Sendable {
    static let tier: LooxTier = .plus
    static let durationDays = 750                       // pinned by tests
    static let duration: TimeInterval = TimeInterval(durationDays) * 86_400
    /// A stored start more than this far ahead of `now` is clamped to `now`.
    static let futureStartTolerance: TimeInterval = 86_400

    let start: Date
    var endsAt: Date { start.addingTimeInterval(Self.duration) }
    func isActive(at now: Date) -> Bool { now < endsAt }

    static func effectiveTier(store: LooxTier, grant: Self?, now: Date) -> LooxTier {
        guard let grant, grant.isActive(at: now) else { return store }
        return Swift.max(store, tier)
    }
}
```

### 1.2 `Vaultify/Services/Subscription/LooxComplimentaryGrantStore.swift` (~90 lines, app target only)
```swift
import Foundation

/// Persists the grant start in the Keychain so a REINSTALL keeps it (Keychain
/// items outlive app deletion today; Apple does not guarantee this, accepted).
/// WhenUnlockedThisDeviceOnly (the `KeychainStore` default), not synchronizable:
/// a new device or Erase All Content gets a fresh 750 days.
///
/// Rules:
/// - A THROWING read (locked wake, errSecInteractionNotAllowed) never mints.
///   This is the same as `OwnerDeviceIdentity.current()`.
/// - Mint uses ADD-ONLY (`KeychainStore.add`). On a duplicate the store reads again,
///   so a racing scene or a wrong "absent" can never overwrite a start.
/// - The only rewrite allowed is the clamp: a start more than 1 day after `now`
///   (a clock was moved forward at mint) becomes `now`, through `KeychainStore.update`.
///   That can only shorten the grant.
/// - `eraseLocalState` never erases this item.
nonisolated struct LooxComplimentaryGrantStore: Sendable {
    nonisolated struct Backend: Sendable {
        var read: @Sendable () throws -> Data?        // nil = absent; throws = unknown
        var add: @Sendable (Data) throws -> Bool       // false = duplicate
        var update: @Sendable (Data) throws -> Bool    // false = absent
        var delete: @Sendable () -> Void
    }
    static let account = "loox-complimentary-start-v1"
    static let keychain: Self          // wires KeychainStore.get/add/update/delete, accessGroup nil
    #if DEBUG
    static func inMemory(start: Date?) -> Self   // UI-test isolation and unit tests
    func debugOverwrite(start: Date?)            // QA only (update, or add if absent; nil = delete)
    #endif
    let backend: Backend

    /// Read → clamp a future start → grant. Absent or malformed: add `now`. A duplicate
    /// means read again. A read or write that throws returns nil and writes nothing more.
    func resolve(now: Date) -> LooxComplimentaryGrant?
    static func encode(_ date: Date) -> Data     // UTF-8 decimal Int64 Unix seconds
    static func decode(_ data: Data) -> Date?
}
```
Malformed payload: overwrite with `update(now)`. This is the only non-clamp write, and it is safe because the old value cannot be parsed.

### 1.3 `Vaultify/Features/Subscription/LooxTrialCopy.swift` (~30 lines)
```swift
import StoreKit

/// Human length of an intro-offer period built from its UNIT ("1 year", not
/// "365 days"), localized EN/VI/JA. The day unit has its OWN key: "%lld days" is
/// the rotation label (JA 日, not 日間) and must not be reused.
enum LooxTrialCopy {
    static func length(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .week: appString("\(period.value) weeks")
        case .month: appString("\(period.value) months")
        case .year: appString("\(period.value) years")
        default: appString("\(period.value) days (trial)")   // .day (ASC offers 3 days) + @unknown
        }
    }
}
```

### 1.4 `Vaultify/Features/Profile/LooxHubPlanSection.swift` (~90 lines)
This is the plan section moved out of `LooxHubScreen.swift:65-108`, which is 457 lines today. It has three states:
- **Subscriber:** Your plan `paidTier` + Manage plan.
- **Complimentary:** Your plan Loox+, "Free until \<date\>", and Upgrade to Loox Max.
- **Free:** Upgrade to Loox Max.

`upgradeRow` is shared between the complimentary and Free states. Every action opens `LooxPaywallScreen`. Dates use `Date.FormatStyle(date: .abbreviated, time: .omitted).locale(appResourceLocale)`, as `ShareLinksScreen.swift:136` does.

### 1.5 `Vaultify/Features/Settings/LooxComplimentaryDebugMenu.swift` (~50 lines, whole file `#if DEBUG`)
- A read-only row showing start, end and Active/Expired/None, all with `Text(verbatim:)`.
- A Menu: "Start now", "10 days left" (start = now − 740 d), "Expired" (now − 751 d), "Future start" (now + 30 d, to check the clamp), "Delete item".
- Every action calls `env.entitlements.debugSetComplimentaryStart(_:)`.
- A footnote: "Tier Override wins; set it to StoreKit to see the grant."
- These controls write the real Keychain on purpose, so QA can check reinstall survival.

## 2. Modified files

### 2.0 `VaultifyCore/Keychain/KeychainStore.swift`
Add `static func add(_ data: Data, account: String, accessGroup: String? = nil) throws -> Bool`. It does `SecItemAdd` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecUseDataProtectionKeychain`. It returns `false` on `errSecDuplicateItem` and throws on any other status. Today `set` (`:16-39`) is copy-then-update, which can overwrite the start, so `set` must not be used for the grant.

### 2.1 `VaultifyCore/Subscription/LooxMembership.swift`
- `:29` becomes `static let launchEnabled = true`.
- Rewrite the docs at `:3-7` and `:17-28`: commerce is live (owner 261021), and the effective tier includes complimentary Loox+. Drop "stays false for the submission".
- `:36-41`: the beta switch now only matters for TestFlight and App Review. Remove the `debugPurchasesEnabled` reference (see §2.2).

### 2.2 `Vaultify/Services/Subscription/LooxEntitlementStore.swift`
- **Header `:9-20`.** The tier has two inputs: verified StoreKit, and the local complimentary floor. `storeTier` is still the only answer to "is paying". Remove the stale "backend hand-off later" sentence.
- **New stored properties:**
  - `@ObservationIgnored private let complimentaryStore: LooxComplimentaryGrantStore?` (nil means never touch the Keychain).
  - `private(set) var complimentaryGrant: LooxComplimentaryGrant?`
  - `private(set) var complimentaryActive = false` (cached; getters never read `Date.now`).
  - `@ObservationIgnored var onTierInputsChanged: (() -> Void)?`
- **`tier`, `paidTier`, `isSubscriber`, `complimentaryEndsAt`:** as in the draft. `complimentaryEndsAt` requires `complimentaryActive`, `!isSubscriber`, and `tier == .plus`.
- **`resolveComplimentary(now: Date = .now)`:**
  - If `store.resolve` returns a grant, cache it.
  - If it returns nil (locked device), keep the cached grant and only recompute `isActive(now)`. This covers day 750 passing while the device is locked.
  - Set `complimentaryActive`. Call `onTierInputsChanged` only when the value changed.
- **`refresh()`:** call `onTierInputsChanged` when `storeTier` changed, and once after the first refresh completes. This fixes the cold-launch race where subscribers report `free` (`:122-123`).
- **`:100` init** becomes `init(defaults: UserDefaults = .standard, complimentaryStore: LooxComplimentaryGrantStore? = .keychain)`.
- **`:112` `start()`:** make `resolveComplimentary()` the first line, before the `updatesTask` guard.
- **Remove `debugPurchasesEnabled`** (`:47-50`, `:73-74`, `:106`, its defaults key). After the flip it is dead, so `purchasesEnabled` simply returns `LooxMembership.launchEnabled`. Optionally keep the `betaPreviewEnabled` path only where `launchEnabled` is false.
- **`:143-147`:** fix the "App Store installs stay dark" comment.
- **Add the DEBUG hook** `debugSetComplimentaryStart(_:)`: it calls `complimentaryStore?.debugOverwrite(start:)` and then `resolveComplimentary()`.

### 2.3 `Vaultify/App/AppEnvironment.swift`
- `:354` becomes `LooxEntitlementStore(defaults: settingsDefaults, complimentaryStore: testIsolationEnabled ? .inMemory(start: UITestFixtures.complimentaryStart) : .keychain)`.
  - `UITestFixtures.complimentaryStart` is a fixed constant, `Date(timeIntervalSince1970: 1_790_000_000)`, active until about 2028-10.
  - Snapshots then show the complimentary Loox+ state that real users see first, and the date is deterministic.
- **Add `func refreshAnalyticsUserProperties()`** (the single source). It passes `tier: entitlements.storeTier`, `complimentaryPlus: entitlements.complimentaryEndsAt != nil`, language and iCloud.
  - Wire `entitlements.onTierInputsChanged = { [weak self] in self?.refreshAnalyticsUserProperties() }`.
  - Replace the inline call at `:396-401` with it.
- `eraseLocalState` (`:580-625`): no change. Add a one-line comment saying the complimentary start is deliberately kept.

### 2.4 `Vaultify/App/RootView.swift:188`
In `case .active:`, add `env.entitlements.resolveComplimentary()` after `obscured = false`. It must sit outside the `session.state == .unlocked` block at `:199`.

### 2.5 Paywall
**`LooxPaywallScreen.swift`**
- `:51` uses `isSubscriber`; `:82` uses `paidTier`; update the `:42-44` doc.
- Add `@State private var periodEndIsTrial = false`.
- `loadPeriodEnd` (`:160-171`): for the transaction with the latest expiry, set `periodEndIsTrial = offer?.type == .introductory && offer?.paymentMode == .freeTrial`. This needs iOS 17.2, so it is fine at the 17.3 floor.
- `:90`: show "Free trial ends %@" when `periodEndIsTrial`.

**`LooxAcquisitionPaywallView.swift`** (612 lines; keep the net change small)
- `:24`: replace `trialDays` with `@State private var trialPeriods: [String: Product.SubscriptionPeriod] = [:]`.
- `load()` (`:412-416`):
  - Build a **local** dict from every product whose intro offer is a `.freeTrial`, then assign `trialPeriods` once.
  - `trialEligible = await first(trial product)?.subscription?.isEligibleForIntroOffer ?? false`. Set it to **`false` when no product has a trial.** `load()` runs again on `Storefront.updates` (`:66-70`), so stale state must be cleared.
  - Read eligibility from a product, never from `LooxProductID.subscriptionGroupID` (`LooxTier.swift:85`, which is the local .storekit group ID).
  - `comparison` is unchanged.
- Add `trialPeriod(for:)` and `selectedTrial`, as in the draft.
- `:247-249`: `if let period = trialPeriod(for: product) { trialPill(period) }`. This drops the Max-annual-only condition, so Max Monthly shows the pill too.
- `:292-293`: the pill reads `appString("\(LooxTrialCopy.length(period)) free")`. It must not be bigger than the `.body` price (3.1.2).
- `:352-353` and `:368-369`: the CTA reads "Try free for %@". Delete `isTrialSelection` (`:374`) and `days(of:)` (`:428-436`).
- `disclosureText` (`:392-399`): use the "Free for %@, then %@ each year/month…" strings when `selectedTrial != nil`.
- **New `ctaNote` in `bottomBar` (`:329-345`), a `.footnote` `.secondary` line between the CTA and Restore.** The two cases cannot both apply, because Plus has no trial.
  - `selectedTrial != nil`: "Then %@ each year." or "Then %@ each month.", using `product.displayPrice`. This puts the billed amount next to the trial CTA (3.1.2).
  - `selectedTier == .plus`, `complimentaryEndsAt != nil`: "You already have Loox+ free until %@. Subscribing starts billing today." This prevents buying something the user already has, and the refund requests that follow.
- Header `:92-95`: show "You have Loox+ free until %@" when `complimentaryEndsAt` is set.
  - **[decision]** All four cards stay purchasable and Max stays preselected, so App Review can find the IAPs (2.1).
  - No "free until" on the Loox+ card (3.1.2).
- `:497` uses `isSubscriber`. `:465-466`: drop "dormant plumbing".

### 2.6 Hub and quotas
- **`LooxHubScreen.swift`**
  - `:65-108` is replaced by `LooxHubPlanSection` at `:29`.
  - `:129-133`: the seal shows for `isSubscriber` only (decision 260716, "paid tiers only").
  - Update the `:8-12` doc.
  - `maxQuotaFraction` (`:175-185`): remove `add(outgoingRecipientCount, …)`, because no sharing gate exists (`LooxGate.swift:44` has no call site).
- **`LooxQuotaScreen.swift:30-33`:** remove the Sharing row until a gate exists. Add a comment pointing to the §5.1 waiver.
- **`LooxFeatureTile.swift:148-149`:** destructive when `fraction > 1`, warning when `fraction >= 0.9` (this includes exactly at the cap). "At cap" is not an error.
- `LooxMemberSeal.swift:6-7`: note that the caller gates on `isSubscriber`.

### 2.7 `Vaultify/Features/Settings/SettingsScreen.swift`
- Delete the Purchases toggle at `:243-247`.
- Insert `LooxComplimentaryDebugMenu()` after the Tier Override picker (`~:263`) inside the existing `#if DEBUG`.

### 2.8 Analytics
- **`AnalyticsEngine.swift`**
  - `:7-11`: add `case complimentaryPlus = "complimentary_plus"`.
  - `:100-109`: the signature becomes `refreshUserProperties(tier:complimentaryPlus:language:iCloudSyncEnabled:)`. Document that `tier` is the **paid** tier.
- **`VaultifyApp.swift:170-173`:** call `env.refreshAnalyticsUserProperties()`.
- **[decision]** `subscription_tier` reports the Apple Max trial as `max`.

### 2.9 `Loox.storekit`
- `:40-44` max.annual: `P1W` becomes `P1Y`.
- `:79` max.monthly: `introductoryOffer` `{ internalID "6746100012", paymentMode "free", subscriptionPeriod "P1Y" }`.
- Plus products (`:114`, `:149`) stay `null`.

## 3. Localizable.xcstrings (EN / VI / JA)
Copy rules hold: no "!", no em dash, no middle dot.

| Key | EN | VI | JA |
|---|---|---|---|
| `%@ free` | %@ free | Miễn phí %@ | %@無料 |
| `Try free for %@` | (same) | Dùng thử miễn phí %@ | %@無料で試す |
| `Free for %@, then %@ each year. Auto-renews until canceled. Cancel anytime in Settings.` | (same) | Miễn phí %@ đầu, sau đó %@ mỗi năm. Tự động gia hạn cho đến khi hủy. Bạn có thể hủy bất cứ lúc nào trong Cài đặt. | 最初の %@は無料、その後は年額 %@ です。解約するまで自動更新されます。設定からいつでも解約できます。 |
| `…each month…` twin | (same) | …mỗi tháng… | …月額… |
| `Then %@ each year.` | (same) | Sau đó %@ mỗi năm. | その後は年額 %@ です。 |
| `Then %@ each month.` | (same) | Sau đó %@ mỗi tháng. | その後は月額 %@ です。 |
| `You already have Loox+ free until %@. Subscribing starts billing today.` | (same) | Bạn đã có Loox+ miễn phí đến %@. Nếu đăng ký, bạn sẽ bị tính phí từ hôm nay. | Loox+ は %@ まで無料でご利用いただけます。登録すると本日から課金が始まります。 |
| `%lld weeks` | plural one `%lld week` / other `%lld weeks` | %lld tuần | %lld 週間 |
| `%lld months` | plural one/other | %lld tháng | %lld か月間 |
| `%lld years` | plural one/other | %lld năm | %lld 年間 |
| `%lld days (trial)` | EN localization: plural one `%lld day` / other `%lld days`; comment "Intro-offer length, not the rotation label" | %lld ngày | %lld 日間 |
| `You have Loox+ free until %@` | (same) | Bạn đang dùng Loox+ miễn phí đến %@ | Loox+ を %@ まで無料でご利用いただけます |
| `Free until %@` | (same) | Miễn phí đến %@ | %@ まで無料 |
| `Free trial ends %@` | (same) | Thời gian dùng thử miễn phí kết thúc %@ | 無料トライアルは %@ に終了 |

- `%lld days` (rotation) is **unchanged**.
- **Removed** after a grep confirms no other users: `%lld days free`, `Try free for %lld days`, `First %lld days free, then %@ each year. …`, and the strings of the deleted Purchases debug toggle.

## 4. Tests

### New `VaultifyTests/LooxComplimentaryGrantTests.swift`
Anchor on `Date(timeIntervalSinceReferenceDate: 0)` with a `date(days:)` helper.

**Policy**
- `testDurationIsPinnedTo750DaysOfLooxPlus`.
- `testActiveThroughDay749AndEndsExactlyAtDay750`.
- `testEffectiveTierTakesMaxOfStoreAndGrant`.

**Grant store** (`.inMemory` backend)
- `testAbsentItemMintsOnceAndPersists`.
- `testExistingStartIsNeverRewritten`.
- `testDuplicateOnAddRereadsInsteadOfOverwriting`.
- `testFutureStartIsClampedToNow`: a start more than 1 day ahead becomes `now`; a start within 1 day is kept.
- `testThrowingReadWritesNothingAndReturnsNil`.
- `testFailedWriteDoesNotClaimTheGrant`.
- `testMalformedPayloadIsReminted`.
- `testPayloadRoundTripsUnixSeconds`.

**Entitlement store** (`@MainActor`)
- `testActiveGrantGivesPlusButNotSubscriber`.
- `testExpiredGrantFallsBackToFree`.
- `testUnavailableKeychainRechecksCachedGrantExpiry`: a cached grant whose time has passed plus a store that throws gives `complimentaryActive == false`.
- `testNilStoreNeverResolves`.
- `testTierInputsChangedFiresOnlyOnChange`.
- DEBUG: `testTierOverrideWinsAndHidesComplimentaryStatus`.
- `testUITestComplimentaryFixtureStillActive`. It fails loudly before the fixed start expires.

### Updated tests
- `LooxMembershipTests.swift:85-93`: rename to `testProductionPurchasesAreLive` and use `XCTAssertTrue`. Cite owner 261021 and the §5.6 evidence. Fix the `:96` comment.
- `AnalyticsEventTests.swift:61`: add `.complimentaryPlus`.
- Grep `UITestConfigurationTests` and the UI tests for the removed debug-purchases key and drop any references.
- Rerun `PrivateEmailMemberUXUITests` (`:57`) and the member snapshot. With the injected grant, the hub shows Loox+ with the plan card and "Plan limits". The fixture has 2 aliases, which is under Loox+ caps. Re-record the baselines.

## 5. Docs and comments
- **`docs/codebase-summary.md`**
  - `:81`: user properties are `subscription_tier` (paid) plus `complimentary_plus`.
  - `:117`: commerce is live; the grant model; both Max products carry a 1-year intro trial; the tier split; the add-only Keychain rule.
  - `:176`: remove the launch from "Deferred".
- **Comments to fix:** `LooxEntitlementCoordinator.swift:55-60`, `LooxEntitlementAttach.swift:4-7`, `ProfileScreen.swift:19-21` and `:54-57`, `LooxGate.swift:11-13`, `LooxTier.swift:26-29`, `RelayAPIClient.swift:20-22`.
- **`phase-05-membership-launch.md`**
  - §5.4 `:101-114`: update the offers and the grant.
  - §5.6 `:137-145`: tick with evidence.
  - `:166`: replace the exit criterion.
  - Record the §5.1/§5.2 waivers: sharing seats and themes are ungated, and the Sharing quota row is hidden.
- **`phase-07-signed-rc-submission.md:81-82`:** review notes (§6).
- **`owner-intake-260804-legal-and-asc.md:121`:** intro offer row.
- **`docs/deployment-guide.md`:** subscriptions and offers are configured in App Store Connect only; `deliver`/`make submit-ios` cannot attach IAPs.
- **Commit:** `feat(subscription): …`.

## 6. App Store Connect and release (browser agent; owner signs in)
0. **Precondition: ship blocker.** Confirm the production `ENTITLEMENT_MODE` is `off` or `shadow`.
   - If it enforces, every complimentary user, who sends no lease, is put in the Free bucket on day 1.
   - `quota_exceeded` is then a hard failure (`RelayAPIClient.swift:135`, `RelayRetryPolicy.swift:34`). Do not submit until this is confirmed.
1. **Group "Loox Membership", all four products.** Approved or Ready to Submit, Cleared for Sale, review screenshot present, en/vi/ja localizations.
2. **Max Annual.** End or remove the 1-week offer. Create Free trial, 1 year, all territories, starting today, no end date.
3. **Max Monthly.** Create the same 1-year free trial. Confirm the 1-year duration can be chosen.
4. **Loox+ Annual and Monthly.** No introductory offer.
5. **Billing grace period.** 16 days.
6. **Server Notifications V2.** Production URL `https://entitlement.looxpassword.com/v1/apple/notifications`. Sandbox goes to staging `/v1/apple/notifications`; confirm the host with backend.
7. **Submission.** Attach all four subscriptions to the version in the App Store Connect UI if any is not yet Approved. No `ja` metadata push until a ja listing exists.
8. **Review notes.** "Every install gets Loox+ features free for 750 days in-app (no purchase, no Apple trial). All four subscriptions are at Profile > Loox > Upgrade to Loox Max (Year/Month segment). Loox Max Annual and Monthly carry a 1-year free trial introductory offer, one per subscription group. Tier changes never touch user data."
9. **Terms link** in the Description or the License Agreement field. Confirm the Privacy URL.
10. **App Privacy (decided).**
    - Declare Purchases → Purchase History, not linked, not tracking, purpose App Functionality. Attach sends the transaction JWS to `entitlement.looxpassword.com` (`LooxEntitlementCoordinator.swift:111-121`).
    - Add Analytics as a purpose only if `purchase_completed` carries product IDs to GA4.
    - Mirror this in `Vaultify/Resources/PrivacyInfo.xcprivacy` (new `NSPrivacyCollectedDataTypePurchaseHistory` dict).
11. **Release notes and promo text (EN/VI).**
    - Mention "Loox+ free for 750 days", the 1-year Max trial, and "existing items are kept; new ones beyond Loox+ limits need Loox Max" (see Open question 2).
    - Put these claims **only** in promo text, release notes and description. Never in the name, subtitle, keywords or screenshots (2.3.7).
12. **TestFlight QA notes.**
    - Use a fresh Sandbox account: one intro offer per group, so testers who used the old 1-week offer will not see the pill.
    - Renewal timelines are compressed, so "Free trial ends" shows a near date. That is not a bug.
    - Testers with a lapsed sandbox subscription will see complimentary Loox+, and Restore will correctly report nothing.

## 7. Backend and legal follow-ups
- **Before any enforcement canary (B5):** choose (a) a server-anchored complimentary rule (identity `created_at` + 750 d → Plus bucket; never trust a client claim) or (b) keep `ENTITLEMENT_MODE` off or shadow for the window.
- **Intro trial on the worker.** Confirm it grants Max for introductory free-trial transactions (`offerType=1`, `price=0`) and handles `DID_RENEW` / `EXPIRED` (subtype `VOLUNTARY`) at the trial boundary.
- **Relay limits.** Abuse cap of at least 10 aliases; rate limits allow 30 links and 30 Quick View approvals per 30 days.
- **Production secrets.** `IAP_KEY_P8`, `IAP_KEY_ID`, `IAP_ISSUER_ID`, `APP_APPLE_ID`; fix the production App Store Server API 401.
- **Terms (looxpassword-web).** Complimentary clause (750 days from first launch **on a device**, then Free, data kept) and the 1-year Max trial clause. Get counsel sign-off.

## 8. Out of scope (flag only)
- `canAddOutgoingRecipient` and `fullThemes` have no call sites, so sharing and themes stay ungated (§5.1 waiver; the Sharing row is hidden per §2.6).
- The ItemEditor inline alias create (`ItemEditorScreen.swift:727-760`) bypasses `LooxGate`.
- After day 750, Watchtower history goes behind the paywall. It is hidden, not deleted.
- There is no pre-expiry reminder copy (for example 30 days before day 750); that can come in a later release.
- Analytics does not separate the Apple trial from paid Max (for example an offer parameter on `purchase_completed`); that can come later.

## Rejected critiques
- **Review 2 #7 (`storeResolved` flag that skips gates until the first refresh):** rejected. `start()` runs in `AppEnvironment.init`, and `currentEntitlements` is local, so it resolves before the unlock UI completes. The race is not realistically reachable (YAGNI).
- **Review 2 #1, the "Change plan" cross-grade part:** rejected. That screen is Apple's `SubscriptionStoreView` (`LooxPaywallScreen.swift:118`), which shows prices and runs the cross-grade itself. A Max-trial user switching to Plus is a deliberate StoreKit action.
- **Review 1 #3, placing the Loox+ note in `disclosureText`:** superseded, not dropped. The note goes in the new under-CTA `ctaNote` (§2.5), merged with Review 2 #1, so it sits next to the action.
- **Review 2 #3 alternative (floor the grant at `.max` for users already over Loox+ caps):** not adopted by default. It is left to the owner (Open question 2).

## Open questions for owner (blocking)
1. **Device-local start.** A new device or Erase All Content gives a fresh 750 days, and a multi-device user sees different "Free until" dates. Is that acceptable (the Terms will then say "per device"), or must the start follow the user across devices (earliest date wins, which needs sync or backend work)?
2. **Existing heavy users.** Users above Loox+ caps (more than 3 profiles, more than 10 aliases, more than 30 links or approvals per 30 days) had no limits before and will hit a Max upsell on their next create. Data is kept. Accept this and announce it in the release notes (recommended default), or floor those users at Max?
3. **Production `ENTITLEMENT_MODE` and the server complimentary rule.** What is the current production value (it must be off or shadow to ship, §6 step 0), and who owns option (a) or (b) in §7 before B5?

**Status:** DONE_WITH_CONCERNS
**Summary:** This is the final spec with the valid critiques applied:
- the clock-forward clamp and add-only Keychain writes
- the billed amount under the trial CTA, and the Loox+ billing note for users who already have it free
- a trial state that resets on reload, and a dedicated trial-days string key
- analytics that refresh whenever the tier inputs change
- the quota bar turns red only over the cap, and the Sharing quota is hidden until it is enforced
- a deterministic grant in UI tests, the dead debug toggle removed, the entitlement-mode ship precondition, the backend handling the $0 trial, and the Purchase History privacy declaration

**Concerns/Blockers:**
- The production `ENTITLEMENT_MODE` could not be checked, because this review was read-only with no network.
- The phase-05 §5.6 gates are still unticked.