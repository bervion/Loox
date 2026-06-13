# Second-Layer Protection, Rich Field Types & Attachments

User-requested. Build in phases ("làm hết, nhiều lượt").

## Decisions (locked by user)
- **Scope:** all three (2nd-layer secret, new field types, file/text attachments).
- **2nd-layer granularity:** an **app-wide Level-2 password** PLUS a per-item choice:
  each protected item can use the app-wide Level-2 password OR its own **custom code**.
- **Mechanism:** **true encryption** — content is sealed under a key derived from the
  code; the unlocked vault alone cannot decrypt it. Forgetting the code = that field is
  lost permanently (the point).

## Crypto model (2nd layer, on top of the normal VaultKey sealing)
- **Level-2 Secret Key (L2SK):** random 32 bytes, generated once. Wrapped by
  `Argon2id(level2Password, l2Salt)` → stored in the key bundle (`wrappedL2SK`).
  Changing the Level-2 password only re-wraps L2SK (fields untouched).
- **Protected field value** = base64 JSON `Payload{ v, scheme, salt?, kdf?, ct }` where
  `ct = AES-256-GCM(plaintext, key)`:
  - scheme `level2` → key = L2SK (held in memory only after a Level-2 unlock this session).
  - scheme `custom` → key = `Argon2id(customCode, salt)` (salt+params stored in payload).
- The whole field (with this opaque payload string as its value) is still sealed by the
  VaultKey at rest — so it's **doubly encrypted**. Repository is unchanged (payload is just a string).
- `DynamicField.guard2: Bool?` (optional → backward-compatible with already-stored items).

## Phases
| # | Phase | Status |
|---|-------|--------|
| 1 | Crypto foundation (`SecretGuard`, bundle L2 fields, `VaultSession+Level2`, `DynamicField.guard2`) + Settings "Extra Protection" (set/change/unlock Level-2 password) | ⏳ this pass |
| 1b | Editor: mark a field protected (Level-2 or custom code); Detail: reveal protected field (prompt code / use session L2) | next |
| 2 | New field types: security question (Q&A), recovery codes (multi-code), richer notes | next |
| 3 | Attachments: file (image/PDF) + pasted text, encrypted blob storage + viewer/export | next |

## Notes
- Level-2 unlock holds L2SK in memory for the session; cleared on vault lock (extend `VaultSession.lock`).
- Biometric for Level-2 = future (reuse `BiometricKeyStore` pattern with a 2nd account).
- `Payload.kdf` stores Argon2 params so custom-code fields decrypt without external state.
