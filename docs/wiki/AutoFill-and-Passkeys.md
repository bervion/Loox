# AutoFill and Passkeys

Loox integrates with the system in three ways: an AutoFill Credential Provider extension on iOS and iPadOS, a separate AutoFill provider in the Mac app, and a Safari web extension on iPhone and iPad. None of them link analytics or crash reporting, and none of them fill anything without an unlock.

## What the AutoFill extension provides

| Capability | iOS / iPadOS | macOS |
|---|---|---|
| Passwords | Yes | Yes |
| Passkeys (sign in and create) | Yes | Yes |
| Conditional passkey registration (automatic upgrades) | Yes (iOS 18 and later) | Yes |
| One-time codes (TOTP) | Yes (iOS 18 and later) | Yes |
| Save a new password from the system save sheet | Yes (iOS 26.2 and later) | No |
| Generate a strong password from the system prompt | Yes (iOS 26.2 and later) | No |

On older iOS versions the saving and generating happen inside the Loox AutoFill sheet instead, see "Saving logins" below.

## Turn Loox on as the AutoFill provider

### iOS and iPadOS

1. Open Loox, go to **Settings** and tap **Set up password AutoFill**.
2. Loox shows a short guide and then opens the system settings for you. The guide follows the iOS 18 layout of the Settings app:
   - open **Settings → General → AutoFill & Passwords**,
   - turn on **AutoFill Passwords and Passcodes**,
   - tick **Loox** in the provider list. You can leave iCloud Passwords on if you still use it.
3. On iOS 18 and later Loox first asks the system to show its in-app "turn on" prompt; if that prompt is not available, or Loox is already enabled, the button opens the AutoFill provider settings directly. On iOS 17 the button always opens the provider settings directly.

Once enabled, iOS offers your saved logins above the keyboard in other apps and in Safari.

### One-time codes (iOS 18 and later)

Tap **Settings → Set up verification codes** to open the system settings for verification-code providers and select Loox. When a one-time-code field is focused, Loox computes the current code from the stored secret and offers it. On iOS 17, copy the code from the item or from the Home screen instead.

### macOS

The Mac app embeds its own AutoFill provider with the capabilities in the table above. Turn it on from macOS System Settings, in the same AutoFill area where other password managers are listed.

## Unlocking inside AutoFill

- The extension unlocks with Face ID or Touch ID in one tap, using the same biometric-protected key as the app, or with the master password as a fallback.
- The master-password path in the extension runs the same Argon2id derivation as the app. The vault profile is sized at 32 MiB so it fits an extension's memory budget, see [[Security Model]].
- Loox never fills silently. A request that arrives without user interaction is answered with "user interaction required" so the system shows the Loox sheet.
- Developer secrets (keys, tokens, certificates) never appear in AutoFill. Items shared with you by another Loox user are offered only while the share is verified live; they are hidden when offline.

## Passkeys

- Create and use passkeys through the AutoFill sheet like passwords. Loox stores each passkey encrypted under the Vault Key, deduplicates by site and user, and publishes the matching identities to the system so sites can offer them.
- **Settings → Passkeys** lists your passkeys grouped by site, with a detail sheet and delete. A login item also shows the passkeys that belong to its website.
- The detail sheet shows a backup-status badge (backed up, backup eligible, or this device only). It reads "this device only" while iCloud Sync is off.
- **Automatic passkey upgrades** (Settings → Security, iOS 18 and later): sites that support it can upgrade a password sign-in to a passkey in the background. Loox keeps a write-only public key readable while the vault is locked so the upgrade can be created; using the passkey still requires unlocking your vault.
- Passkeys sync through iCloud when iCloud Sync is on, and are included in encrypted `.vaultify` backups. They are never written to CSV. A few passkeys with very long credential IDs stay on the device because iCloud cannot store them; Loox says so in the iCloud Sync settings.
- Passkeys support the WebAuthn `largeBlob` extension on iOS 18 and later.

## Saving logins

- **iOS 26.2 and later:** when you sign up somewhere, the system "Save password" sheet and "Use Strong Password" generation can target Loox directly.
- **Earlier iOS versions:** the Loox AutoFill sheet has a **＋ Create new login** entry. It generates a password, prefills the site and the username or email from your default identity, and saves the item; the app picks it up the next time it comes to the foreground.

## Safari web extension (iPhone and iPad)

The Safari extension is bundled with the iOS app and does not exist on the Mac. It appears in Safari's extension settings under the name **Loox** with the description "Fill identities and cards from your Loox vault." Turn it on there and allow it on the sites where you want to use it; it requests access to `https` sites only, plus the active-tab, tabs and native-messaging permissions.

What it does:

- **Fills identities and payment cards.** An inline menu appears on identity and card fields; the popup lists matching identities, cards and logins for the current site. Logins can be copied from the popup, but the extension does not inject login passwords into pages at all.
- **Sign-up assist.** On a registration form it can suggest a generated password and offers to save the new login. On iOS 26.2 and later the system save sheet owns that flow instead.
- **Unlocks with Face ID** from the popup. A web page focusing a field can never trigger Face ID; only your tap on the popup can. A short-lived session (up to 15 minutes, mirrored to your auto-lock setting) avoids repeated prompts.
- **Per-site controls:** "Never for this site" switches off the save overlay, and "Hide on this site" turns the extension off for that site entirely.

Security properties that are enforced by tests in the repository:

- Exactly one native command (`getFillPayload`) can return vault field values, and it only serves one identity or card item at a time after a user tap.
- The Vault Key and bulk vault contents never cross from native code into JavaScript.
- The extension has the App Group and shared keychain entitlements only; it carries no CloudKit entitlement.
