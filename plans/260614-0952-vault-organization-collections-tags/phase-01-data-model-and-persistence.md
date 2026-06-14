# Phase 01 — Data Model & Persistence

## Context Links
- Overview: [plan.md](plan.md)
- Sealed payload (linchpin): `VaultifyCore/Models/VaultItem.swift:62-73`
- Persistence record: `VaultifyCore/Store/ItemRecord.swift`
- Model registration: `VaultifyCore/Store/VaultStore.swift:15`
- Sibling `@Model` pattern: `VaultifyCore/Passkey/PasskeyModels.swift` (`PasskeyRecord`)
- Extension decode site: `VaultifyCore/VaultReader.swift:37-45`

## Overview
- **Priority**: P1 (blocks all later phases)
- **Status**: ✅ done (compiles app + extension via `make check`)
- Define the Folder domain types, the persistent `FolderRecord`, extend `ItemSecret`/`VaultItem` with `tags`, and add the plaintext `lastUsedAt` column. Pure model layer — no UI. Must compile in BOTH targets (files in `VaultifyCore/**` compile into app + AutoFill extension).

## Key Insights
- `folderId: String?` ALREADY exists on `VaultItem` (line 8) and `ItemSecret` (line 71), is sealed via `VaultItem.secret` (line 62-64), and round-trips through both decode sites. We are adding the missing Folder *entity* and *tags*, not re-plumbing folderId.
- **`ItemSecret` is `Codable` and is the AES-GCM-sealed JSON.** Adding a non-optional `tags` would break decoding of every existing sealed blob (they have no `tags` key). MUST decode as optional with default `[]`.
- `FolderRecord` must mirror `ItemRecord`'s sync columns exactly (`dirty`, `ckRecordName`, `ckChangeTag`, `deletedAt`) for Phase 05 CloudKit parity.
- `FolderSecret` (name) is sealed under the SAME Vault Key as items — folder names are user data and must not leak in plaintext columns. Only `sortIndex`, timestamps, and sync metadata are plaintext.
- `nonisolated` is required on `Folder`/`FolderSecret`/`FolderColor` so they match the crypto/data convention and stay off-main; `FolderRecord` is `@Model` (SwiftData → MainActor-bound, like `ItemRecord`).

## Requirements
**Functional**
- A folder has: stable `id`, sealed `name`, `iconAsset` (Polaris name), `color` (`FolderColor`), `sortIndex`, timestamps.
- An item can reference at most one folder via existing `folderId`; `nil` = Unfiled.
- An item can carry 0..n free-text `tags`.
- `lastUsedAt` records the last in-app copy/reveal time.

**Non-functional**
- Folder name + item tags encrypted at rest. `lastUsedAt`/`sortIndex` plaintext (timing/order only).
- Backward compatible: existing sealed `ItemSecret` blobs (no `tags`) decode to `tags == []`. Existing `ItemRecord` rows (no `lastUsedAt`) default to `nil`.

## Architecture
```
VaultifyCore/Models/
  Folder.swift          nonisolated struct Folder (decoded, in-memory) + FolderSecret (sealed payload)
  FolderColor.swift     nonisolated enum FolderColor -> light/dark UInt32 -> (resolved in app via VaultColors.dynamic)
VaultifyCore/Store/
  FolderRecord.swift    @Model final class FolderRecord (sealed: Data + plaintext sortIndex + sync cols)
Modified:
  VaultItem.swift       + tags:[String] on VaultItem & ItemSecret; thread tags through .secret + init; optional-decode
  ItemRecord.swift      + lastUsedAt: Date?
  VaultStore.swift      register FolderRecord in ModelContainer(for:)
```
Data flow (folder): UI `Folder` → `FolderSecret{name}` → JSONEncode → AESGCM.seal → `FolderRecord.sealed`; reverse on read. Mirror of the item path so Phase 02 reuses `seal`/`open`.

## Related Code Files
**Create**
- `VaultifyCore/Models/Folder.swift` — `nonisolated struct Folder: Identifiable, Equatable, Sendable` (id, name, iconAsset, color: FolderColor, sortIndex, createdAt, updatedAt) + `nonisolated struct FolderSecret: Codable, Sendable { var name: String }` + computed `var secret: FolderSecret`. Keep < 80 LOC.
- `VaultifyCore/Models/FolderColor.swift` — `nonisolated enum FolderColor: String, Codable, CaseIterable, Sendable` (~10 cases, e.g. blue/green/purple/orange/red/teal/pink/indigo/gray/amber). Expose `var light: UInt32` / `var dark: UInt32` (hex), and `static var palette: [FolderColor]`. NO SwiftUI import here (keep core UI-free); the `Color` resolution lives in the app layer (Phase 03/04) via `VaultColors.dynamic(light:dark:)`.

**Modify**
- `VaultifyCore/Models/VaultItem.swift` — add `var tags: [String]` to `VaultItem` (init param `tags: [String] = []`) and to `ItemSecret`; thread `tags` into `var secret` (line 62-64); add `tags` to the `ItemSecret` initializer usage. Add explicit `Codable` handling so a missing `tags` key decodes to `[]` (custom `init(from:)` OR keep auto-synth and rely on default — see Implementation Step 3 for the safe approach).
- `VaultifyCore/Store/ItemRecord.swift` — add `var lastUsedAt: Date?` (NOT in `init`; default `nil` in a post-init assignment or as a stored default). Mirror `deletedAt` pattern (assigned in init body to nil).
- `VaultifyCore/Store/VaultStore.swift:15` — `ModelContainer(for: ItemRecord.self, PasskeyRecord.self, FolderRecord.self, configurations:)`.
- `VaultifyCore/VaultReader.swift:41-44` — pass `tags: secret.tags` into the `VaultItem(...)` it builds (extension target must compile with the new field).

## Implementation Steps
1. **`FolderColor.swift`**: define enum with ~10 cases; `light`/`dark` hex per case (reuse hues consistent with `VaultColors.category`); `static var palette`. `nonisolated`, no SwiftUI import.
2. **`Folder.swift`**: define `FolderSecret { var name: String }` (Codable) and `Folder` struct (id default `UUID().uuidString`, sortIndex default `0`, timestamps default `.now`); add `var secret: FolderSecret { FolderSecret(name: name) }`.
3. **Extend `ItemSecret` safely**: add `var tags: [String]` to `ItemSecret`. To guarantee old blobs decode, choose ONE:
   - (a) Implement `init(from decoder:)` decoding `tags` with `decodeIfPresent ?? []` (explicit, safe, ~12 LOC); or
   - (b) Verify Foundation's synthesized `Codable` treats a missing array key as a decode failure (it DOES → use option (a)). **Use (a).** Keep `Encodable` synthesized.
4. **Extend `VaultItem`**: add `var tags: [String]`, init param `tags: [String] = []`, assign in init, include in `var secret` construction: `ItemSecret(title:category:folderId:fields:tags:)`.
5. **`ItemRecord`**: add `var lastUsedAt: Date?`; set `self.lastUsedAt = nil` in init body (mirror `deletedAt`).
6. **`VaultStore`**: add `FolderRecord.self` to the container model list (line 15).
7. **`VaultReader.decrypt`**: add `tags: secret.tags` to the `VaultItem(...)` call (line 41-44).
8. **`tuist generate --no-open`** (3 new files: Folder, FolderColor, FolderRecord).
9. `make check` — confirm BOTH targets compile (extension includes `VaultifyCore/**`).

## Todo List
- [x] Create `FolderColor.swift` (10 cases, light/dark hex, palette)
- [x] Create `Folder.swift` (`Folder` + `FolderSecret` + `var secret`)
- [x] Create `FolderRecord.swift` (`@Model`, sealed + sortIndex + sync cols)
- [x] Add `tags` to `ItemSecret` with optional-decode `init(from:)`
- [x] Add `tags` + `lastUsedAt` to `VaultItem` (init + `var secret`)
- [x] Add `lastUsedAt: Date?` to `ItemRecord`
- [x] Register `FolderRecord.self` in `VaultStore` container (+ erase in `eraseAll`)
- [x] Thread `tags`/`lastUsedAt` into `VaultReader.decrypt` + `VaultRepository.decrypt`
- [x] `tuist generate --no-open`
- [x] `make check` passes (app + extension)

## FolderRecord shape (target)
```swift
// VaultifyCore/Store/FolderRecord.swift
import Foundation
import SwiftData

/// Persistent record for one folder ("Space"). The name lives only inside
/// `sealed` (AES-256-GCM under the Vault Key); order + sync metadata are
/// plaintext so the store can sort and sync can reconcile without unsealing.
@Model
final class FolderRecord {
    @Attribute(.unique) var id: String
    var sealed: Data            // sealed FolderSecret (nonce ‖ ciphertext ‖ tag)
    var iconAsset: String       // Polaris icon name (non-secret)
    var colorRaw: String        // FolderColor.rawValue (non-secret)
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?        // tombstone for sync
    // Sync metadata (CloudKit) — mirrors ItemRecord
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String, sealed: Data, iconAsset: String, colorRaw: String,
         sortIndex: Int = 0, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.sealed = sealed
        self.iconAsset = iconAsset; self.colorRaw = colorRaw
        self.sortIndex = sortIndex
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.deletedAt = nil; self.dirty = true
    }
}
```
> Note: `iconAsset`/`colorRaw` are non-secret presentation metadata (an icon/color reveals nothing about the folder's contents), kept plaintext so the Spaces grid renders without unsealing every folder. The *name* is sealed.

## Success Criteria
- All three new files exist and are picked up by Tuist (appear in generated project).
- `make check` green for app + extension with zero new warnings about Sendable/actor isolation.
- A unit/self-test (Phase 06) confirms: encode a `VaultItem` with `tags=["a","b"]`, seal, open, decode → tags preserved; decode a legacy `ItemSecret` JSON WITHOUT a `tags` key → `tags == []`.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Missing `tags` key breaks decode of existing vault (data-loss appearance) | Med | High | Explicit `decodeIfPresent ?? []` in `ItemSecret.init(from:)`; covered by Phase 06 legacy-blob test BEFORE shipping. |
| Forget to register `FolderRecord` in `ModelContainer` → silent no-persist | Med | High | Step 6 + Phase 06 round-trip test that inserts & refetches a `FolderRecord`. |
| New file not added to Tuist → "cannot find type" build break | Med | Med | Step 8 `tuist generate` mandated; `make check` gate. |
| SwiftData migration: adding `lastUsedAt`/new model triggers store migration | Low | Med | Additive optional column + new entity = lightweight automatic migration; verify app still opens an existing store in Phase 06 self-test. |

## Security Considerations
- Folder `name` sealed under Vault Key (AES-256-GCM), same as item content. Never store name plaintext.
- `tags` sealed inside `ItemSecret` — encrypted with the item.
- `lastUsedAt`, `sortIndex`, `iconAsset`, `colorRaw` are plaintext metadata by design (timing/order/presentation, not content) — consistent with existing `favorite`/timestamps trade-off. Document the WHY in code comments (no plan refs).

## Next Steps
- Phase 02 consumes these types: folder cache + CRUD (seal/open `FolderSecret`), `markUsed` writing `lastUsedAt`, tag aggregation over `items`.
