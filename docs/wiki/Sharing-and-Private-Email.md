# Sharing and Private Email

The vault, AutoFill, passkeys and one-time codes work with no network at all. The four features on this page are optional and do use the network. Each one encrypts on the device before anything is uploaded, and each is described below with exactly what is sent where.

<p>
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/iphone-share.png" width="180" alt="Share sheet">&nbsp;
<img src="https://raw.githubusercontent.com/bervion/Loox/main/App%20Store%20Screenshots/shots/ipad-share.png" width="360" alt="Share sheet on iPad">
</p>

## Approval Mode (share with another Loox user)

Turn it on with **Settings → Approval Mode**. In the app's words: "Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above." Enabling it never uploads your vault items, and you need to be signed in to iCloud ("Sharing uses an encrypted approval transport; it does not turn on vault sync").

From an item's share button, choose a Loox user ("Access is tied to this iCloud account. Only they can accept, and no link works for anyone else.") and decide per field what they can use:

| Field | Options | Meaning |
|---|---|---|
| Username, password and other values | Off / Shared | A shared value is visible to them and "can't be taken back later." |
| One-time code | Off / Ask each time / Always show code / Hand over secret | "Ask each time" sends a single current code only after you approve the request with Face ID; the TOTP secret never leaves your vault. "Always show code" lets them see the current code at any time without asking you: the secret is delivered encrypted so their device makes the codes itself (shown, like every shared value, only after Loox checks online that the share is still live), but Loox never shows, copies, exports or autofills it, and removes it from their device on its next sync after you change the option or stop sharing. A modified or compromised device could still extract it, so for high-value accounts treat it like a hand-over. They need the latest Loox. "Hand over secret" delivers the seed itself, after an irreversibility warning. |
| Passkey | Off / Ask each time / Shared | "Ask each time" signs the exact challenge on your device after approval. |

Other controls: **Allow use on multiple devices** (off means everything is encrypted for the first device they enrolled; their other devices see a locked placeholder), **Revoke** ("stops all future requests immediately. Values you marked Shared were already delivered and stay with them."), an invite link and a Messages nudge for first-time recipients, and a safety code both sides can compare.

How it works underneath: the share is a CloudKit share in your account. Grants, requests and responses are sealed with HPKE to the recipient's device keys and signed with a P-256 device identity that each side pins on first contact. Approval requests arrive as push notifications; approving requires Face ID in the foreground. On the recipient side, shared items appear read-only in a "Shared with Me" Space, and their values are shown only after the grant has been verified live, so they are hidden while offline. Receiving a share is always free.

## Quick Link

A Quick Link is "a one-time snapshot of the fields you pick" that opens in any browser.

- You choose the fields and an expiry between 5 minutes and 30 days, and can make the link one-time ("This link disappears after it's opened once."). "One-time codes and extra-protected values can never be shared in a link." Developer key material is excluded as well.
- The snapshot is encrypted on the device with AES-256-GCM using a fresh key and nonce. Only the ciphertext is uploaded to the Loox Link service; the key is appended to the URL after `#`, which browsers do not send to servers.
- "Anyone with this link can view the shared fields until it expires or you revoke it. Send it over a channel you trust."
- Active links are listed with a swipe-to-revoke action. "This link can only be revoked from this device." An optional shorter URL can be requested right after creation when the service offers it.
- Creating a link needs a network connection and, on a real device, Apple App Attest to prove the request comes from a genuine Loox install.

## Quick View (Send to Browser)

Quick View sends chosen fields of one item to a browser session once, without a link that could be forwarded. "Open the Loox viewer in your browser, then scan its QR code or enter its code. You choose which fields to send."

1. The browser page on looxpassword.com creates a one-time key pair and shows a QR code, a short code and a few safety words.
2. In Loox (Profile → Send to Browser, or the share menu of an item) scan the QR code or type the code, pick the fields, compare the safety words and **Approve with Face ID**.
3. Loox re-reads the item, encrypts exactly those fields to the browser's one-time key (P-256 ECDH, HKDF-SHA256, AES-256-GCM) and uploads the ciphertext. A current one-time code can be included with its validity window. The browser decrypts once and only renders the values.

The service is a blind mailbox: it never sees plaintext and has no read API over your vault. The approval upload requires App Attest. History is stored on the device and "does not show browser activity or retain the fields, codes, or session keys you sent." The feature is switched on per app version by a signed configuration document; when it is off, the screen says "Send to Browser is not available for this app version yet."

## Private Email

"Give a site its own address instead of your real one. Mail still reaches your inbox, and the site never learns where."

- Addresses belong to a profile. Before creating any, you confirm the inbox they forward to by opening a verification link that Loox emails you; once verified, "Private addresses can forward to it now."
- Each address can carry a label, a website and a linked login, can be paused and resumed, and can serve several logins. Deleting a profile permanently deletes its addresses.
- Private Email requires an iCloud sign-in even with iCloud Sync off: your relay identity (the key that signs alias commands) is stored encrypted under the Vault Key in your private iCloud database so your other devices can use the same addresses. If you reinstall without restoring the vault, that identity cannot be opened and Loox offers "Reset Private Email".
- Commands to the relay service are signed by that identity and bound with App Attest; the service stores the alias, its state and the verified destination so it can forward mail.

## What each feature sends where

| Feature | Leaves the device | Encrypted before upload | Destination |
|---|---|---|---|
| Approval Mode | Grants, requests and responses for the fields you chose | Yes (HPKE to recipient device keys) | Your iCloud private database and a CloudKit share |
| Quick Link | The fields you picked | Yes (AES-256-GCM, key stays in the URL fragment) | Loox Link service |
| Quick View | The fields you approved, optionally a current one-time code | Yes (sealed to the browser's one-time key) | Loox service, then your browser |
| Private Email | Alias commands, labels, the verified destination inbox; relay identity escrow | Commands are signed; the identity escrow is sealed under the Vault Key | Loox relay service; iCloud private database |

## Membership

Loox has three membership tiers, shown as **Loox**, **Loox+** and **Loox Max**. The free tier covers the vault, AutoFill, passkeys and codes, and a basic allowance of the network features. Paid tiers raise the limits on the number of profiles, retained Private Email addresses, Quick Links created and Quick View approvals in a rolling 30-day window and outgoing Approval Mode recipients, and unlock the full Security (Watchtower) report and the full theme set. Receiving shares is always free, and the Critical and High findings in Security are never gated.

Limits and purchase screens are consulted only while purchases are enabled for the build; the paywall links to the Terms and Privacy pages on looxpassword.com. Prices and exact quotas are shown in the app.
