# Privacy and Data

Loox has no account and no vault server. The table below lists every flow in the app that can send data off the device, the setting that controls it, where that setting lives and its default. Settings paths are for iPhone and iPad; the Mac app has the same toggles in its Settings window (General and Security panes).

## What leaves your device

| Data | Where it goes | Controlled by | Default |
|---|---|---|---|
| Encrypted vault items (sealed blobs), plus plain metadata: Space icons, colors and order, timestamps, your device name, and a recovery envelope (the recovery-key-wrapped Vault Key with its salt and Argon2 parameters) | Your iCloud private database | **Settings → iCloud Sync → iCloud Sync**. Also asked during onboarding on the Emergency Kit step ("Turn on iCloud Sync" / "Keep this device only"). | Off |
| Shared items in Approval Mode: encrypted grants, requests and responses between you and the recipient | Your iCloud private database and a CloudKit share with the recipient | **Settings → Approval Mode**. Independent of iCloud Sync: turning one on never turns the other on. | Off |
| Fields you put in a Quick Link, encrypted on the device; the decryption key stays in the link's `#` fragment and is never sent | The Loox Link service | Only when you create a link from an item's share menu | Not applicable |
| Fields you approve for Quick View (Send to Browser), encrypted to the browser's one-time key | The Loox service that relays the session to your browser | Only when you approve a session with Face ID | Not applicable |
| Private Email addresses, their forwarding destination (your verified inbox) and alias commands; your relay identity is stored encrypted in your iCloud private database | The Loox relay service and your iCloud private database | Only if you set up Private Email (requires an iCloud sign-in, even with iCloud Sync off) | Not applicable |
| Website domain names of your logins, to fetch site icons | Google's favicon service | **Settings → General → Show website icons**. Turning it off also clears the icon cache. | On |
| The first five characters of each password's SHA-1 hash (k-anonymity), during a Security audit | Have I Been Pwned's Pwned Passwords range API | **Settings → Security → Check for known breaches** | On |
| Usage analytics: event names, item *types*, bucketed counts, product IDs and setting states, plus the user properties `subscription_tier`, `app_language` and `icloud_sync`. Never item names, values, websites or search terms. | Google Analytics for Firebase (`FirebaseAnalyticsCore`, no advertising identifier) | **Settings → General → Share anonymous usage statistics** | **Off** (opt-in). Firebase collection is disabled in the Info.plist until you turn it on. |
| Crash reports: stack traces, app and device state, and a fixed catalog of custom keys. No user ID is ever set. | Firebase Crashlytics | **Settings → General → Send crash diagnostics** | On (opt-out). Off in DEBUG builds. |
| Signed configuration documents (feature availability, the registry of Private Email domains, Quick View signing keys). A plain download; the request carries no vault data. | The Loox configuration service, with a read-only CloudKit public-database mirror as fallback | Runs after unlock when the cached copy is older than an hour and on foreground when older than six hours | Always on |

Things that stay on the device: the master password, the Vault Key, the recovery key (except as the wrapped recovery envelope above), every item value you do not explicitly share, the breach-check cache, Quick View history, rotation and audit reminders (local notifications), and tutorial progress.

## In-app wording

The toggles explain themselves in the app; the footers are quoted here so you know what to look for.

- **Show website icons:** "Uses Google to fetch site icons as login avatars. This reveals the sites you have logins for to Google; turn off to keep everything on-device."
- **Check for known breaches:** "Uses k-anonymity. Only the first five characters of each password's SHA-1 hash are sent. Passwords never leave your device."
- **Share anonymous usage statistics:** "Counts which features are used to help improve Loox. Never your vault contents, item names, websites, or search terms. Not linked to your identity."
- **Send crash diagnostics:** "Sends a diagnostic report when Loox crashes, so the fault can be found and fixed. Reports carry the state of the app and the device, never your vault contents. Not linked to your identity."
- **iCloud Sync:** "Your items are end-to-end encrypted before they sync. iCloud never sees titles, passwords, or notes. Organizational details like folder icons, colors, and timestamps sync as regular metadata."
- **Approval Mode:** "Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above."
- **About → Privacy:** "Analytics stay off unless you turn them on. Crash diagnostics are on so faults can be found and fixed, and you can turn them off in Settings. There are no accounts."

## The extensions

The AutoFill extension (iOS and macOS) and the Safari extension link no analytics or crash-reporting SDK. Each ships its own privacy manifest declaring no data collection. The Safari extension has no iCloud entitlement at all; the AutoFill extension uses CloudKit only for items shared with you in Approval Mode: to verify that the share is still live before filling, and to relay "ask each time" passkey approvals.

## Erasing

**Settings → Erase Vault** offers two scopes, in the app's words: "Erase everywhere also turns off your quick links and private email aliases, stops shared logins, and deletes the iCloud copy. Erase on this device removes Loox data from this device only and leaves all of that running." Turning off leftover links needs a network connection.

## Reporting a privacy problem

If you find data leaving the device in a way this page does not describe, that is in scope for the [[Security Policy]].
