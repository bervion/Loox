# Getting Started

This page walks through a first install: creating the vault, saving the Emergency Kit, turning on biometric unlock, and the basics of Spaces and Profiles.

## Install

- **iPhone and iPad:** iOS / iPadOS 17.3 or later, from the [App Store](https://apps.apple.com/us/app/loox-password-manager/id6779973474).
- **Mac:** macOS 15 or later. The Mac app is a native build of the same codebase with its own AutoFill provider.
- **From source:** see [[Building from Source]].

No account is created at any point. Everything below happens on the device.

## Create the vault

On first launch Loox walks you through these steps, in this order:

1. **Welcome.** Start a new vault, or choose **Restore data** to move the vault from another device (scan a setup code) or reopen it from a saved Emergency Kit PDF. Both restore routes turn on iCloud Sync, because that is where the vault is downloaded from (see "Joining from another device" below).
2. **Loox Password.** This is the master password. It must be at least 8 characters and you confirm it once. Loox derives a key from it with Argon2id; the password itself is never stored anywhere. Choose something long that you can remember: there is no "forgot password" link, only the Emergency Kit.
3. **Your name.** Creates your default identity (name and email). The AutoFill extension uses it to prefill the username when you create a new login from a sign-up form.
4. **Emergency Kit.** Explained in the next section. You cannot continue until the kit is saved.
5. **Appearance.** Day or Night and an accent color. You can change this later in Settings → Appearance.
6. **Face ID / Touch ID.** Optional biometric unlock, see below.

Behind the scenes, step 2 generates a random 256-bit Vault Key and wraps it with the key derived from your master password. Every item is encrypted with that Vault Key. Details are in [[Security Model]].

## Emergency Kit and recovery key

The Emergency Kit is a PDF that contains your **recovery key**: a random 160-bit code written in Crockford base32 and grouped in blocks of four characters (for example `A1B2-C3D4-…`). It is a second, independent way to unwrap the Vault Key, so it lets you reset the master password if you forget it.

- Loox requires you to actually save or share the PDF before it lets you continue. A checkbox is not enough; the save has to succeed.
- When you type the key back in later, separators and spaces are ignored and the confusable letters `I`, `L` and `O` are read as `1`, `1` and `0`, so a key copied from paper still works.
- Keep the kit somewhere private. Anyone who has the recovery key and your device (or your synced iCloud vault, see below) can open the vault.

During this step Loox also asks **"Do you want iCloud Sync?"**, because that single choice decides what the kit can do:

| Choice | What the kit can do |
|---|---|
| **Turn on iCloud Sync** | Your items upload end-to-end encrypted, and the kit can restore the vault on a new device signed in to the same iCloud account. Folder icons, colors, order, timestamps and your device name travel as ordinary iCloud data. |
| **Keep this device only** | Nothing leaves the device. The kit can reset the master password on this device, but it is not a backup: after device loss, deleting the app or setting up a new device, the kit cannot bring the vault back. |

You can regenerate the kit at any time from **Settings → Security → Emergency Kit**. With iCloud Sync on, the most recently generated kit is the one a new device can join with, so save the new PDF and discard the old one.

If you want an actual backup file you control, export an encrypted `.vaultify` backup, see [[Import and Export]].

## Face ID and Touch ID

Turn biometric unlock on during onboarding or later in **Settings → Security → Unlock with Face ID** (or Touch ID, depending on the device).

- Loox stores the Vault Key in a Keychain item that can only be read after a successful Face ID or Touch ID check and that is bound to the biometrics enrolled at the time. If the enrolled biometrics change, that item is invalidated and Loox asks for the master password again.
- The master password always keeps working; biometrics are a shortcut, never the only way in.
- The same biometric key is shared with the AutoFill extension and the Safari extension, so they can unlock with one tap too.

Other lock settings in **Settings → Security**:

- **Auto-Lock:** Immediately, after 1, 5 or 15 minutes, or after 1 hour (default 5 minutes). "Immediately" locks the moment the app leaves the screen.
- **Shake to lock** (off by default) and **Lock Now** on the Settings screen.

And in **Settings → General**:

- **Hide contents in App Switcher** (on by default) covers the app with a privacy screen in the app switcher.
- **Clear clipboard** after 15 seconds, 30 seconds, 1 minute, or never (default 30 seconds).

## Adding items

Loox stores logins, passkeys, two-factor (TOTP) codes, cards, identities, notes, recovery codes, security questions and developer secrets (SSH keys, API secrets, App Store Connect and APNs keys, signing identities, certificates).

- **Two-factor codes:** scan the site's QR code with the camera, or open an `otpauth://` setup link; Loox registers for that scheme, so "Set up in app" buttons can hand the secret straight to Loox. Codes are shown live on Home and in the item.
- **Password generator:** random passwords with live strength feedback, or passphrases built from the EFF large word list.
- **Security (Watchtower):** the Security tab scores the vault and lists weak, reused and old passwords, missing two-factor opportunities and, if enabled, passwords found in known breaches. See [[Privacy and Data]] for what the breach check sends.

<p>
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-generator.png" width="180" alt="Password generator">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-detail.png" width="180" alt="Login detail">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-weak-item.png" width="180" alt="Weak password warning">
</p>

## Spaces and Profiles

**Spaces** are folders. Each has a name, an icon and a color, and an item belongs to at most one Space (otherwise it is Unfiled). The first launch creates a Space called "My Space" that you can rename. Manage them under **Settings → Spaces** or from the Items tab. Space names are encrypted like item contents; the icon, color and order are plain metadata. Items can also carry any number of tags, and favorites and pinned items surface on Home.

**Profiles** (called *Personas* on the management screen, reached from the profile button on Home) keep separate identities apart, for example work and personal:

- Every Space belongs to exactly one profile, and switching the active profile re-filters Home, Items and Search to that profile's Spaces and items.
- Each profile can have its own default identity (name, email) and its own Private Email addresses.
- Deleting a profile moves its Spaces and items to your default profile and permanently deletes its private email addresses.
- AutoFill is not partitioned by profile: a login is offered on its own site regardless of which profile owns it.

## Joining from another device

If the vault already exists on another device:

- **With iCloud Sync on** and the Emergency Kit at hand, a new device signed in to the same iCloud account can restore the vault from the recovery key alone: pick **Restore data → Import from PDF** on the welcome screen.
- **Pair New Device** (on the trusted device: Settings → iCloud Sync, visible while sync is on; on the new device: **Restore data → Scan Setup Code**): the new device shows a QR code, the trusted device scans it and hands over the Vault Key end-to-end encrypted through your private iCloud database. The key never appears in plaintext on either side of the transfer.
- **Without iCloud**, move the vault with an encrypted `.vaultify` backup, see [[Import and Export]].
