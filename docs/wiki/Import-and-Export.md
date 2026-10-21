# Import and Export

Both live under **Settings → Backup**: "Import from another password manager, or export your whole vault to a file you control."

## Import

Tap **Import → Choose File…**. Loox accepts two kinds of file: "Supports CSV exports and Loox encrypted backups (.vaultify)."

### CSV from another manager

Loox reads the CSV layouts produced by 1Password, Bitwarden and Chrome, and any CSV with similar column names. The header row is matched case-insensitively; the first matching column wins:

| Field | Accepted column names |
|---|---|
| Title | `name`, `title`, `account` |
| Username | `username`, `login_username`, `user`, `email` |
| Password | `password`, `login_password`, `pass` |
| Website | `url`, `login_uri`, `website`, `uri` |
| Notes | `notes`, `note` |
| One-time code secret | `otpauth`, `totp`, `one-time password` |
| Folder (Space) | `folder`, `collection`, `space`, `group`, `grouping` |
| Tags | `tags`, `tag` (separated by `;`) |

Rows with a password become logins; a row with only notes becomes a note. A missing title falls back to the website, then the username. Folder names are matched to existing Spaces or created. CSV never carries passkeys.

### Encrypted `.vaultify` backup

Pick the file, enter the backup password and tap **Decrypt**. Loox shows a preview with the item and passkey counts, then **Import N Records**. If the backup holds Extra Protection fields that this device will not be able to open (this vault already has its own Extra Password, the backup carries protected values but no key wrap, or the wrap was refused), Loox warns you before importing and offers **Import Anyway**; those fields are imported but stay sealed.

## Export

Tap **Export** and pick a format:

### Encrypted (recommended)

You choose a **backup password**; the screen says: "The backup is sealed with Argon2id + AES-256-GCM. You'll need this password to restore it." The file is named `loox-backup.vaultify`.

What the file contains (all inside the encrypted payload):

- every item with its fields, category, tags, Space name, archived state, favorite, pinned, icon override, rotation reminder, password-changed date, created and updated dates and a stable item id (so re-importing the same backup is idempotent and attachments re-attach to their owner),
- passkeys,
- the Extra Protection key wrap, still wrapped by your Extra Password, so protected fields can be opened again on another device,
- attachments, each sealed under its own random key with a SHA-256 of the plaintext; a restore verifies every attachment before writing anything and is all-or-nothing.

How it is encrypted (`Vaultify/Services/ImportExport/VaultBackup.swift`):

- Argon2id with the `standard` profile (64 MiB, t=3, p=4) and a fresh 16-byte salt derives a key from the backup password.
- Version 2 envelopes encrypt the payload with a random content key under AES-256-GCM and store that content key wrapped by the password-derived key. Version 1 files (payload sealed directly by the password key) still import.
- The envelope records its Argon2 parameters, and the importer rejects parameters outside the policy described in [[Security Model]] before deriving anything.

Exports include archived items; Recently Deleted is not included. The generated file is removed when you leave the screen, when the app is backgrounded and when the vault locks, so share or save it right away.

### CSV (plain)

"A CSV export is **not encrypted**. Anyone with the file can read every password. Passkeys are never included in CSV." You confirm with **Create Unencrypted Export**. The file is `loox-export.csv` with the columns `name,username,password,url,notes,folder,tags`. Values protected by Extra Protection are written as `[protected]` rather than as ciphertext.

## Moving to a new device

1. On the old device, create an encrypted export and save the file somewhere you control.
2. On the new device, create a vault (any master password), then **Settings → Backup → Import** the `.vaultify` file with its backup password.

With iCloud Sync on, you can instead restore from the Emergency Kit or pair the new device, see [[Getting Started]].
