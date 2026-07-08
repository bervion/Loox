# Schema-2 exposure app parity — implementation report

## Files changed
- `VaultifyCore/Models/CapabilityManifest.swift` — `Entry.exposure: String?` (+ memberwise init, default nil); transcript emits `string(exposure ?? "ga")` after optString(message_key) ONLY when `schemaVersion >= 2`; `CapabilityManifest.exposure(for:)`; verifier `supportedSchemaVersions = 1...2` (was `== 1`).
- `Vaultify/Features/Sharing/QuickView/QuickViewExposure.swift` — cases renamed `disabled/beta/public` → `hidden/beta/ga`; resolver: `ga` visible when `assertionRequired` OR `isBetaCohort` (owner-confirmed: beta cohort keeps seeing it under ga even in shadow).
- `Vaultify/Features/Sharing/QuickView/QuickViewExposureProvider.swift` — `currentExposure(manifestExposure:)` precedence: DEBUG override > manifestExposure > `.hidden` (no more default `.disabled`-as-`.hidden` w/o manifest path — nil manifest never becomes `.ga`). `entryVisible` threads `manifestExposure` through.
- `Vaultify/Services/Capabilities/CapabilityStore.swift` — `quickViewExposure: QuickViewExposure?` + `applyQuickViewExposure(_:)`.
- `Vaultify/Services/Capabilities/CapabilityManifestClient.swift` — `apply()` now also calls `store?.applyQuickViewExposure(manifest.exposure(for: .quickView).flatMap(QuickViewExposure.init(rawValue:)))`.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — `quickViewEntryVisible` passes `env.capabilities.quickViewExposure` into the provider.
- `VaultifyTests/Fixtures/cap-manifest-vectors-v1.json` — replaced w/ BE's updated array-format oracle (3 named vectors: baseline schema1, additive-quick_view schema1, schema2-exposure).
- `VaultifyTests/CapabilityManifestTests.swift` — `loadVector()` → `loadVectors()` (array); new `testSchema1VectorsTranscriptUnchanged`, `testSchema2ExposureVectorTranscriptMatchesFrozenByteForByte`, `testExposureNilWhenAbsentOrSchema1`.
- `VaultifyTests/QuickViewKernelTests.swift` — `testExposureMatrix` renamed cases, added ga+shadow+betaCohort=true (true) and ga+shadow+general (false).
- `VaultifyTests/QuickViewFlowTests.swift` — new `testCurrentExposurePrecedence` (no-manifest→hidden, manifest ga→ga, DEBUG override beats manifest).

## Parity results
- Schema-2 vector "schema2 exposure (quick_view=beta, others=ga)": transcript byte-for-byte match, `PASS`.
- Schema-1 vectors "baseline" + "additive quick_view": transcript byte-for-byte unchanged, `PASS` (additive guard confirmed — `if schemaVersion >= 2` never fires for these).
- Enum rename call-site count: 2 non-QuickViewExposure `.disabled` sites found (`QuickViewEnterCodeSheet.swift:47` SwiftUI modifier, `QuickViewClientTests.swift:72` `CapabilityAvailability.disabled`) — correctly left untouched, confirmed by grep.
- Provider precedence: verified via new test — no manifest+no override→hidden; manifest ga+no override→ga (entryVisible true w/ betaCohort); DEBUG override beta wins over manifest ga.

## Compile + test
- `tuist generate --no-open` clean. `xcodebuild` compile (app+extension, Debug, generic iOS Simulator): `BUILD SUCCEEDED`.
- `xcodebuild test` (sim id 44580B6F...): 407/407 passed, 0 failures, including all CapabilityManifestTests + QuickView*Tests.

## Unresolved questions
None — spec fully matched the BE oracle; no ambiguity hit during implementation.

**Status:** DONE
