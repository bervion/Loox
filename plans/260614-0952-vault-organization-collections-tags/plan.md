---
title: "Vault Organization — Folders (Spaces) & Tags"
description: "Folders (one per item, sealed entity) + lightweight encrypted tags + Home dashboard, reusing existing folderId plumbing."
status: done
priority: P2
effort: ~26h
branch: main
tags: [feature, swiftui, vaultifycore, swiftdata, organization]
created: 2026-06-14
---

# Vault Organization — Folders ("Spaces") & Tags

## Summary
Add two organizing primitives to the offline vault, shipped together:
- **Folders ("Spaces")** — primary container, ONE per item. Real entity (name sealed, Polaris icon, color, sortIndex). Reuses the latent `folderId: String?` already sealed/round-tripped end-to-end (`VaultItem`/`ItemSecret`/`VaultRepository`/`VaultReader`). No Folder model/UI exists today — ~70% of item↔folder wiring is already present.
- **Tags** — cross-cutting, MANY per item. Stored lightweight as `tags: [String]` INSIDE `ItemSecret` (encrypted with the item; no Tag record in v1). Rendered as `#` chips (`ic_hashtag`), neutral.

Landing screen becomes a **Home dashboard** (rebuild `VaultListScreen`): Quick Access (Favorites + Recently used) → Spaces grid → Tags row. Tapping a Space opens a folder-color-tinted filtered list.

Security model preserved: folder name + tags live in the AES-256-GCM sealed payload; only low-sensitivity metadata stays plaintext. New `lastUsedAt` plaintext column (timing only, not content) powers Recents without re-sealing on every use.

## Locked Decisions (A–I)
| # | Decision |
|---|----------|
| A | Both primitives ship together: Folders = 1/item (reuse `folderId`, real entity); Tags = many/item, lightweight `[String]` inside `ItemSecret`. |
| B | Code names: `Folder` / `FolderRecord` / `FolderSecret` (avoid `Collection`/`Group` collisions). Display label "Spaces" (EN) / "Nhóm" (VI) via string catalog — 1-line change. |
| C | Landing = Home dashboard: Quick Access → Spaces grid (icon+color+count) → Tags row. Space tap → folder-tinted filtered list. |
| D | Folder visual = curated ~24-icon Polaris picker + fixed ~10-color palette (`nonisolated enum FolderColor`, light/dark-aware, consistent with `VaultColors`). |
| E | Recents = `lastUsedAt: Date?` PLAINTEXT column on `ItemRecord` (like `favorite`). Tracked on copy/reveal IN-APP only (AutoFill out of scope). |
| F | Folder delete → reassign member items to Unfiled (`folderId = nil`); never delete items. |
| G | `FolderRecord` carries sync fields (`dirty`, `ckRecordName`, `ckChangeTag`, `deletedAt` tombstone), wired into `CloudSyncService` (compile-gated, off by default). Tags ride in item payload → sync free. |
| H | Import/Export CSV: add folder-name column + tags column; on import recreate/match folders by name. (Encrypted backup `PortableItem` also extended.) |
| I | No AutoFill matching changes (domain-based; folders/tags = in-app browsing). No data migration (existing items `folderId == nil` → naturally "Unfiled"). |

## Phases
| # | Phase | Status | Depends on | Effort |
|---|-------|--------|-----------|--------|
| 01 | [Data model & persistence](phase-01-data-model-and-persistence.md) | ✅ done | — | 5h |
| 02 | [Repository: folder CRUD, counts, recents, tag aggregation](phase-02-repository-folders-recents-tags.md) | ✅ done | 01 | 5h |
| 03 | [Editor & folder management UI](phase-03-editor-and-folder-management.md) | ✅ done | 02 | 6h |
| 04 | [Home dashboard & folder-filtered list](phase-04-home-dashboard-and-filtered-list.md) | ✅ done | 02, 03 | 6h |
| 05 | [Cross-cutting: i18n, import/export, CloudKit, docs](phase-05-crosscutting-i18n-importexport-cloudkit-docs.md) | ✅ done (CloudKit compile-only) | 01–04 | 3h |
| 06 | [Tests & verification](phase-06-tests-and-verification.md) | ✅ done (14 tests pass; legacy-decode verified) | 01–05 | 3h |

## Key Dependencies & Cross-Cutting Rules
- **Tuist**: any NEW `.swift` file under `Vaultify/**` or `VaultifyCore/**` requires `tuist generate --no-open` before it compiles. Never edit the xcodeproj. Verify each phase with `make check` (app + embedded extension).
- **SwiftData registration**: `FolderRecord` MUST be added to `ModelContainer(for: ...)` in `VaultStore.swift:15` or it won't persist (currently `ItemRecord.self, PasskeyRecord.self`).
- **`ItemSecret` Codable change is the linchpin**: adding `tags` changes the sealed JSON shape. `tags` MUST be optional-decoded (default `[]`) so existing sealed blobs still decode. Both decode sites must pass it through: `VaultRepository.decrypt` (Vaultify/Data/Repositories/VaultRepository.swift:109-121) AND `VaultReader.decrypt` (VaultifyCore/VaultReader.swift:37-45, in the extension target).
- **Localization (MANDATORY EN+VI)**: every new string → `Vaultify/Localizable.xcstrings` with en source + vi `translated`. New `LocalizedStringResource` titles use `.inAppLocalized`; runtime strings use `appString()`. `TextField` titles must be `LocalizedStringKey` (iOS-26 trap).
- **Icons**: Polaris SVG only (`PolarisIcon("ic_…")`), assets in `Vaultify/Assets.xcassets/PolarisIcons/`. Add name constants to `enum Icons` (Vaultify/DesignSystem/PolarisIcon.swift). Required icons verified present: `ic_hashtag`, `ic_folder`, `ic_work`, `ic_organization`, `ic_bank`, `ic_home`, etc.
- **Concurrency**: `Folder`/`FolderSecret`/`FolderColor` are `nonisolated`; `FolderRecord` is `@Model` (MainActor via SwiftData); repository/views `@MainActor`.
- **No test target exists** in `Project.swift` — Phase 06 decides: add a Tuist `.unitTests` target vs. DEBUG file-based self-test (CLAUDE.md "Verifying runtime behavior").

## References
- Research findings: in-line throughout phases (verified by reading code 2026-06-14).
- Codebase summary: `docs/codebase-summary.md` (update in Phase 05).
