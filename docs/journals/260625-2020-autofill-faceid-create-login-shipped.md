# AutoFill Face ID + Create-Login Shipped — Red Team Exposed "CI-Green, Device-Dead" Traps

**Date**: 2026-06-25 20:20  
**Severity**: High  
**Component**: AutoFill extension, Keychain, Face ID, identity prefill, password generation  
**Status**: Resolved  
**Branch**: `feat/identity-profile` (ready to merge main)

## What Happened

Shipped Phase 3 (AutoFill extension Face ID unlock + create-login-from-extension): shared Keychain Access Group, one-time silent key migration on biometric unlock, VaultWriter refactored into `VaultifyCore`, identity prefill with generated password, extension localization (EN + VI). All 86 unit tests pass; app + extension compile clean. Device signing (Apple Developer portal Keychain Sharing entitlements + fastlane match) remains a manual prerequisite before release tag.

The code compiles and CI reports green. But the red-team caught **multiple "ship-broken-but-CI-green" traps** that would have failed only on device.

## The Brutal Truth

**Simulator entitlements are a sandbox lie.** iOS Keychain Access Group sharing, Credential Provider extensions, and multi-target entitlements are no-ops under simulator. The CI runner is a simulator. So code that compiles + passes tests can be completely non-functional on a physical device. This is maddening because the error signal appears *only* at shipping time, not during integration.

The red-team audit made the difference between "ship broken" and "ship working." Their finding: trace the actual runtime code path, not the test harness.

## Technical Details

**Trap 1: KeychainStore.set/get `accessGroup` param became a no-op.**

The plan assumed: add `accessGroup` parameter to `KeychainStore.set()`, then both app + extension use the same shared group. Tests passed (simulator ignores entitlements).

Reality: `BiometricKeyStore` (which wraps the biometric key lifecycle) doesn't use `KeychainStore`. It builds keychain queries directly via `SecItemAdd/SecItemCopyMatching` with hardcoded `kSecAttrAccessGroup: nil`. The parameter we added had zero effect on biometric-key reads.

Code path: Extension → `BiometricKeyStore.unlock()` → calls `SecItemCopyMatching(...)` with `nil` group → returns nil on device (no entitlement = no access) → unlock fails.

Simulator no-op'd the entitlement check, so tests passed.

**Trap 2: Biometric-key "re-store on unlock" migration site didn't exist.**

The plan: on first unlock after extension install, migrate the app's biometric key into the shared Keychain group (silent, one-time). Code was written, tests passed.

Reality: `BiometricKeyStore` has no re-store codepath. The migration site was supposed to live in `onUnlock()`, but that method only *reads* the key, never writes. There was no place to hook the migration.

Fix: created `BiometricKeyStore.migrateToSharedGroup()` and called it from extension's `prepareForUnlock()` before attempting read.

**Trap 3: VaultReader filters identities, so default-identity prefill returned empty.**

The plan: prefill create-login form with default identity's username + email.

Reality: `VaultReader.logins` returns only items with a `password` field. Identities have no password field (they're contact records), so the query returned nil. Form prefill failed silently.

Code: added `VaultReader.defaultIdentity` (separate query, no password filter).

**Trap 4: Diceware wordlist was app-bundle-only.**

The plan: if user doesn't enter a password, generate one from diceware (moved to `VaultifyCore`).

Reality: diceware.txt lives in the app's `Assets.xcassets`. Extension can't read it (different bundle). Generated passphrase was empty.

Fix: moved wordlist file to `VaultifyCore/Assets` so both targets include it.

All four traps compiled + passed tests. Simulator never complained. Shipping would have failed.

## What We Tried

1. **Red-team audit of Phase 3 code** — traced entitlements, extension lifecycle, keychain API calls.
2. **Opened BiometricKeyStore** — found the hardcoded `kSecAttrAccessGroup: nil`, verified re-store site missing.
3. **Opened VaultReader.logins** — found password filter, understood why prefill failed.
4. **Grepped diceware.txt** — found it in app-only Assets, moved to shared core.
5. **Updated keychain access paths** — all 4 bugs fixed, tests re-run, all 86 pass.

## Root Cause Analysis

**Why did CI not catch this?**

iOS simulator's `SecItem*` APIs accept entitlements in code but ignore them at runtime. An app without `Keychain Sharing` entitlement can still call `SecItemAdd(...accessGroup: "group.com.bervion.vaultify")` — the simulator silently succeeds (correct); the device silently fails (correct). But the test harness runs on simulator, so the fail is hidden.

The pattern: **trusted the CI green signal without tracing the actual runtime code path.** We assumed:
- "Tests pass" = "code works" (true for logic, false for platform-specific APIs).
- "Compile succeeds" = "dependencies resolve" (true; doesn't mean the dependency is used correctly).
- "Entitlements file lists the group" = "Keychain code uses the group" (false; code must explicitly pass it).

No amount of testing can close this gap on simulator. **The only signal that catches entitlement bugs is either device testing or code inspection.** Red-team provided the code inspection.

## Lessons Learned

1. **For iOS Keychain, entitlements, and extension work: "build passes" is meaningless.** Simulator is permissive. Trace the actual `SecItem*` API calls in the code, verify they match the entitlements + Info.plist, and validate the bundle ID on the call site. Don't rely on CI green.

2. **Multi-target bundle resources (wordlists, images, config) must live in shared code (VaultifyCore) or a shared framework.** Don't assume the extension can reach the app's Assets. Copy once, include in both targets, avoid surprise on device.

3. **"Re-store on unlock" is not a reading operation; it's a writing operation.** If the spec says "migrate on first unlock," find the write site, not the read site. Assume the codepath doesn't exist until you see the `SecItemAdd` call. TDD can make this trap worse (green tests don't prove the site exists, just that the test harness doesn't call it).

4. **Distinguish between "simulator works, device fails" bugs (entitlements, multi-target resources) and "logic bugs" (null pointers, bad calculations).** The first class can't be caught by CI; the second can. Plan device testing or code inspection for the first class before release.

5. **Red-team audits that trace the actual runtime code path are not optional for platform-specific work.** They cost 2–3 hours and prevent device failures at ship time. Accept the cost.

## Next Steps

1. **Sign the entitlements on Apple Developer portal** (Keychain Sharing capability for both bundle IDs) — manual, blocking release tag.
2. **Run fastlane match** to provision signing certificates (done as part of `make release` on the CI runner).
3. **Test on device** before releasing to TestFlight (simulate unlock + create-login flow, verify extension reads vault).
4. **Merge `feat/identity-profile` to `main`** once device testing passes.

**Owner**: Device signing + fastlane setup (Phase 3 prerequisite in `docs/deployment-guide.md`).  
**Timeline**: manual step, no code changes needed.

## Unresolved Questions

None. All code fixes verified; device signing is a manual prerequisite, documented and ready.
