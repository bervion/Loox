# Loox Password Manager

Loox is a private, offline password and passkey manager for iPhone, iPad and Mac. There is no Loox account and no server that holds your vault: items are encrypted on your device with a key derived from your master password (Argon2id, then AES-256-GCM per item) and leave the device only when you turn on iCloud sync or share something on purpose. Loox plugs into the system as an AutoFill provider for passwords, passkeys and one-time codes, ships a Safari extension for identities and cards, unlocks with Face ID or Touch ID, and is localized in English, Vietnamese and Japanese. The source is published under the GPL-3.0.

- **App Store:** https://apps.apple.com/us/app/loox-password-manager/id6779973474
- **Website:** https://looxpassword.com
- **Source code:** https://github.com/bervion/Loox

<p>
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-home.png" width="180" alt="Home screen with quick actions and one-time codes">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-vault.png" width="180" alt="Vault list">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-codes.png" width="180" alt="Two-factor codes">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-watchtower.png" width="180" alt="Security score">
</p>

## Using Loox

- [[Getting Started]] — install, create the vault and master password, save the Emergency Kit, turn on Face ID or Touch ID, organize with Spaces and Profiles.
- [[AutoFill and Passkeys]] — turn Loox on as the AutoFill provider on iOS and macOS, passkeys, one-time codes, saving logins, the Safari extension.
- [[Import and Export]] — CSV import from other managers, encrypted `.vaultify` backups, plain CSV export.
- [[Sharing and Private Email]] — Approval Mode over iCloud, Quick Link, Quick View (Send to Browser), Private Email, membership tiers.
- [[FAQ]] — short, honest answers to the questions people ask most.

## Security & privacy

- [[Security Model]] — the key hierarchy, Argon2id parameters, recovery key and biometric wrapping, storage, extensions, and what Loox does not protect against.
- [[Privacy and Data]] — exactly what can leave your device, the toggle that controls each flow, where it lives in Settings and its default.
- [[Security Policy]] — how to report a vulnerability privately.

## Developers

- [[Building from Source]] — toolchain, Tuist project generation, compile and test commands, running on your own device.
- [[Architecture]] — targets, the shared `VaultifyCore` module, data flow and the main directories.
- [[Contributing]] — the rules reviews enforce and how to submit a change.
