---
name: vaultify-test-target
description: Vaultify NOW has a VaultifyTests unit-test target (added with Spaces/Tags). Pattern = in-memory VaultStore + adoptUnlocked fixed key.
metadata:
  type: project
---

`Project.swift` defines a `VaultifyTests` target (`product: .unitTests`, bundleId `com.bervion.vaultify.tests`, sources `VaultifyTests/**`, depends on `Vaultify`, iOS 17.6). Added during the Spaces/Tags feature (was absent before ~2026-06-14). Existing suites: `VaultRepositoryFolderTests`, `VaultBackupFolderTagsTests`, `OrganizationCodecTests`.

**Test pattern (verified):** pure-logic XCTest against a real in-memory store — `VaultStore(inMemory: true)` + `VaultSession(settings:)` with `session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))` then `repo.reload()`. No Argon2/keychain needed. `@MainActor final class … : XCTestCase`, `@testable import Vaultify`.

**Run:** `make test DEST='platform=iOS Simulator,id=<UDID>'` (scheme `Vaultify`). Mind the `build`-token hook: `make test` uses `xcodebuild test` with `build` kept out of `-derivedDataPath`/log names.

**How to apply:** Add new repo/codec unit tests to `VaultifyTests/**`, run `tuist generate` so globbed sources pick them up, then `make test`. The DEBUG file-based self-test (write to Documents, read back via `xcrun simctl get_app_container <id> data`) remains the path for persistence/crypto runtime verification where console capture is unreliable. Related: [[vaultify-ios-build-setup]].
