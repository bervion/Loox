# Security Model

This page describes how Loox protects a vault, with the exact algorithms and parameters used in the code. Paths refer to the [repository](https://github.com/bervion/Loox).

## Key hierarchy

```
master password ──Argon2id──▶ KEK ──AES-256-GCM──▶ wrapped Vault Key   (vault-keybundle.json)
recovery key    ──Argon2id──▶ KEK ──AES-256-GCM──▶ wrapped Vault Key   (vault-keybundle.json)
Face ID / Touch ID ──────────────────────────────▶ Vault Key in a biometry-bound Keychain item
                                                        │
                                                        ▼
                                                   Vault Key (256-bit, random)
                                                        │
                                   AES-256-GCM per item ─┴─ AES-256-GCM per Space name, avatar, passkey, attachment key
```

- **Vault Key.** 32 random bytes generated once when the vault is created (`VaultifyCore/Crypto/KeyHierarchy.swift`). It is the root secret and is never stored in plaintext.
- **Items.** Each item's contents (title, fields, tags, semantic metadata) are one AES-256-GCM sealed blob in the SwiftData store. Only low-sensitivity metadata is stored in the clear: timestamps, favorite, pinned, archived and trashed flags, rotation-reminder cadence, last-used date. Space names are sealed too; a Space's icon, color and sort order are plain so the list can render before unlock.
- **Master password path.** A 16-byte random salt and Argon2id produce a 32-byte key-encryption key (KEK) that wraps the Vault Key with AES-256-GCM. A wrong password fails GCM authentication; there is no separate password hash.
- **Recovery path.** The Emergency Kit's recovery key (160 random bits, Crockford base32) is normalized and fed to Argon2id with its own salt, and that KEK wraps the same Vault Key. The parameters used for the recovery wrap are recorded in the bundle (`recoveryKdf`) so that later changes to the password profile cannot break an already printed kit.
- **Biometric path.** When biometric unlock is on, the Vault Key is stored in a Keychain generic-password item created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and the `.biometryCurrentSet` access-control flag (`VaultifyCore/Keychain/BiometricKeyStore.swift`). The item can only be read after a successful Face ID or Touch ID evaluation, it never leaves the device, and the system invalidates it when the enrolled biometrics change. It lives in a keychain access group shared with the AutoFill and Safari extensions so they can unlock too. Disabling biometrics deletes it and also ends any Safari extension session minted from it.
- **Extra Protection (optional second password).** Individual fields can be sealed under a separate random Level-2 secret key, which is wrapped by an Argon2id key derived from an "Extra Password" (Settings → Security → Extra Protection). When biometric unlock is on, the Level-2 key is also stored behind `.biometryCurrentSet` so Face ID can open protected fields; the typed password always keeps working.

## Argon2id

Loox vendors the phc-winner-argon2 reference C implementation (`VaultifyCore/CArgon2/ref.c`, the portable `ref` variant rather than `opt.c`). Parameters live in `VaultifyCore/Crypto/KdfParams.swift`:

| Profile | Memory | Iterations (t) | Parallelism (p) | Used for |
|---|---|---|---|---|
| `constrained` | 32 MiB | 4 | 4 | The vault's master-password wrap and the recovery wrap. The AutoFill extension runs this derivation on its master-password fallback path, and app extensions have a tight memory budget where a 64 MiB pass risks being killed; 32 MiB stays above the OWASP 2023 floor and the extra iteration recovers part of the halved memory work. |
| `standard` | 64 MiB | 3 | 4 | OWASP 2023 baseline. Encrypted `.vaultify` backups and the Extra Protection wrap, which are only ever opened inside the full app. |

Vaults created before the `constrained` profile existed are re-wrapped to it on the next password unlock; the recovery wrap keeps its recorded parameters.

**Known-answer test.** The vendored implementation is checked against the published Argon2id v1.3 vector: `Argon2id(password="password", salt="somesalt", t=2, m=65536 KiB, p=1, length=32)` must equal `09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7`. The unit test is `testArgon2KnownAnswerVector` in `VaultifyTests/KdfMigrationTests.swift`, and DEBUG builds expose the same check as `Argon2.selfTestPasses()`.

**Parameter bounds on import.** Argon2 parameters are also read from files the app did not write (a backup envelope, the Extra Protection wrap inside it, per-field custom-code payloads). Because the memory and time costs are fed straight to Argon2, an unbounded value would let a crafted file exhaust memory or spin forever. The `Decodable` implementation therefore rejects anything outside this policy as a malformed file before it reaches Argon2:

- memory: at least 8 KiB and at least 8 KiB per lane, at most 128 MiB,
- iterations: 1 to 16,
- parallelism: 1 to 16,
- salt: at least 8 bytes (Loox itself always writes 16).

## Storage

- The encrypted SwiftData store (`Vault.store`) and the key bundle (`vault-keybundle.json`, written with complete file protection) live in the App Group container `group.com.bervion.vaultify`, so the AutoFill and Safari extensions can read ciphertext. Decryption happens only after an unlock, into an in-memory cache that is cleared on lock.
- Key material in memory is zeroed after use; sensitive buffers use `SecureBytes` (`mlock` + `memset_s`).
- Auto-lock, shake to lock, a privacy screen in the app switcher and an auto-clearing local clipboard reduce exposure while the vault is unlocked.
- Passkeys are stored as sealed payloads with the same Vault Key. Attachments use a per-file random key wrapped by the Vault Key, with every seal bound to the attachment id, owner and purpose.

## Sync and sharing cryptography

- **iCloud Sync** (off by default) uploads sealed item blobs to your private CloudKit database together with plain metadata (Space icons, colors, order, timestamps, device name). When sync is on, the recovery-wrapped Vault Key, its salt and its Argon2 parameters are mirrored to the private database as a "recovery envelope" so a new device can join with the Emergency Kit alone; it is useless without the recovery key.
- **Device pairing** seals the Vault Key with HPKE (Curve25519, SHA-256, ChaCha20-Poly1305) to an ephemeral key that exists only on the new device; the sealed envelope travels through the private database and is deleted on read.
- **Approval Mode sharing**, **Quick Link** and **Quick View** each encrypt on the device before anything is uploaded. See [[Sharing and Private Email]].

## Extensions

- Both extensions use a fail-closed capability model: an item kind or field role the resolver does not know gets no external capability, and key material (SSH keys, certificates, tokens stored as protected multiline fields) never enters AutoFill, Quick Link, Quick View, Approval Mode or plaintext export.
- The Safari extension exposes exactly one native command that returns field values (`getFillPayload`), limited to a single identity or card item after a user tap. This is enforced by router and fuzz tests in `VaultifyTests`.
- Extensions carry their own privacy manifests and no telemetry SDK.

## What Loox does not protect against

Loox is designed to keep the vault private at rest and in transit. It cannot help with:

- **A compromised or jailbroken device**, or a device that is already unlocked in an attacker's hands. Anything the unlocked app can read, a privileged attacker on the same device can read.
- **A weak master password.** The only enforced rule is a minimum of 8 characters. Argon2id slows down guessing; it does not make a short password safe.
- **Losing both the master password and the Emergency Kit.** There is no account and no server copy of your keys, so nobody, including the developers, can recover the vault.
- **Exposure of the recovery key.** With iCloud Sync on, the recovery key plus access to your iCloud account is enough to open the vault on a new device.
- **Values you hand over.** Fields marked "Shared" in Approval Mode, anything in a Quick Link, a Quick View payload, or a plain CSV export are outside the vault once delivered and cannot be taken back.
- **Metadata.** Timestamps, Space icons and colors, item counts and your device name are not encrypted and are visible to iCloud when sync is on.
- **Phishing of one-time codes or passkeys on the wrong site** beyond what the system's domain matching provides.

Found a problem? Please follow the [[Security Policy]].
