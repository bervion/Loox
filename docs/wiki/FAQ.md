# FAQ

### Is there a Loox server that stores my vault?

No. The vault is a local encrypted store on your device. There is no Loox account and no vault server. If you turn on iCloud Sync (off by default), the encrypted items go to your own iCloud private database, which Apple hosts under your Apple Account. The only Loox-operated services are the optional sharing and Private Email features, and they receive only what you explicitly share, encrypted on the device first. See [[Privacy and Data]].

### What happens if I forget my master password?

Use the recovery key from your Emergency Kit: it is an independent key that unwraps the same Vault Key and lets you set a new master password. If you have neither the master password nor the Emergency Kit, the vault cannot be opened by anyone, including the developers, because no copy of your keys exists anywhere. See [[Getting Started]].

### Does Loox (the company or the developers) see my passwords?

No. Items are encrypted on the device with a key derived from your master password, and the master password is never stored or transmitted. Analytics, when you turn them on, carry item types and counts, never names, values, websites or search terms, and crash reports never contain vault contents. The sharing features upload ciphertext that only the recipient (or the browser session you approved) can open.

### Is the Emergency Kit a backup?

Only when iCloud Sync is on. With sync on, the kit can restore the vault on a new device signed in to the same iCloud account. With "Keep this device only", the kit can reset the master password on that device but cannot bring the vault back after device loss or reinstall. For a backup file you control, export an encrypted `.vaultify` backup, see [[Import and Export]].

### Which data goes to Google or Firebase?

Three things, each with its own toggle in Settings → General: website domain names for the site-icon feature ("Show website icons", on by default); anonymous usage statistics to Google Analytics for Firebase ("Share anonymous usage statistics", off until you turn it on, no advertising identifier); and crash reports to Firebase Crashlytics ("Send crash diagnostics", on by default). The AutoFill and Safari extensions contain no Firebase code. See [[Privacy and Data]].

### Does the breach check send my passwords to Have I Been Pwned?

No. Loox uses the k-anonymity range API: only the first five characters of each password's SHA-1 hash are sent, and the comparison with the returned list happens on the device. You can turn it off with Settings → Security → "Check for known breaches".

### Why is Loox GPL-3.0 licensed?

So anyone can read, build and audit the code that holds their passwords, and so improvements stay open. The GPL covers the source code. The Loox name, logo and icon, the Font Awesome Pro icon assets and the Shopify Polaris icons are not part of the GPL grant, so a fork has to ship under its own branding. Contributions are accepted under GPL-3.0 with permission for the maintainer to distribute them through the App Store.

### Can I build and run it myself?

Yes. Clone the repository, install the pinned Tuist through mise, run `mise exec -- tuist generate` and run the `Vaultify` scheme on an iOS Simulator. A device run needs your own team and bundle identifiers because the App Group, AutoFill and iCloud capabilities are tied to them. See [[Building from Source]].

### Does it work on a Mac?

Yes. The Mac app is a native build of the same codebase (macOS 15 or later) with its own AutoFill provider for passwords, passkeys and one-time codes. The Safari web extension is iPhone and iPad only.

### Can I share a password with someone who does not use Loox?

Yes, with a Quick Link: an expiring, optionally one-time link that opens in any browser. The fields are encrypted on your device and the key travels only in the link itself. One-time code secrets and extra-protected values can never be put in a link. To share with another Loox user and keep control, use Approval Mode. See [[Sharing and Private Email]].

### Which cryptography does Loox use?

Argon2id (the reference implementation, known-answer tested) to derive a key from the master password, AES-256-GCM for every item and for wrapping the Vault Key, a Face ID or Touch ID protected Keychain item for biometric unlock, HPKE and P-256 for sharing and device pairing. The exact parameters are in [[Security Model]].

### How do I report a security problem?

Privately, by email to support@looxpassword.com with the subject "Security report". Please do not open a public issue. See [[Security Policy]].
