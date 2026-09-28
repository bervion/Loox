import ProjectDescription

// Single source of truth for the Xcode project. Run `tuist generate` to produce
// Vaultify.xcodeproj / Vaultify.xcworkspace — both are gitignored and generated
// per machine, so a beta-Xcode dev and a stable-Xcode CI runner each get a
// project file their Xcode can open. Version lives here (bumped by release.sh).

// Interim Loox Link create token (anti-abuse, rotatable — NOT a user secret).
// Injected into the app's Info.plist at generation time from the environment
// (TUIST_LOOX_LINK_PROD_TOKEN, set on the CI runner) so it never lives in git.
// Empty on dev machines: DEBUG builds supply it via UserDefaults instead.
// Retired once App Attest becomes the create auth (loox-link epic C7).
let looxLinkAppToken = Environment.looxLinkProdToken.getString(default: "")

let project = Project(
    name: "Vaultify",
    options: .options(
        // The app ships EN + VI + JA. String Catalogs ignore this list at
        // build time, but it is what Xcode seeds `knownRegions` from, so a
        // missing `ja` makes the generated project look like a two-language
        // app to anything that reads the project rather than the catalog.
        defaultKnownRegions: ["en", "vi", "ja"],
        developmentRegion: "en"
    ),
    // GA4 usage analytics. `FirebaseAnalyticsCore` measures WITHOUT AdSupport/IDFA
    // (GoogleAppMeasurementCore) — no ATT prompt, no ad identifiers, which is the
    // only Analytics flavor acceptable for a password manager. Linked into the APP
    // target only: the AutoFill/Safari extensions must never carry telemetry.
    packages: [
        .remote(url: "https://github.com/firebase/firebase-ios-sdk",
                requirement: .exact("12.16.0")),
        .remote(url: "https://github.com/pointfreeco/swift-snapshot-testing",
                requirement: .exact("1.19.2")),
    ],
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "WDNL2F75V7",
            "MARKETING_VERSION": "1.56.3",
            "CURRENT_PROJECT_VERSION": "92",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "SWIFT_VERSION": "5.0",
        ],
        // Push (aps-environment) is embedded from the entitlements file as-is under manual
        // signing (fastlane), so it must match the build: sandbox APNs for Debug, production
        // for Release/App Store. The entitlements use `$(APS_ENVIRONMENT)`; a hardcoded
        // "development" would make TestFlight register with sandbox APNs (no production pushes).
        // App Attest picks its environment the same way and for the same reason:
        // entitlements are embedded as-is under manual signing, and `attestKey`
        // fails when the app declares no environment at all. Debug builds attest
        // against Apple's development servers, Release/TestFlight against
        // production — a mismatch fails at `attestKey`, before any request is
        // sent, which reads on screen as a generic "couldn't prove it's genuine".
        configurations: [
            .debug(name: "Debug", settings: [
                "APS_ENVIRONMENT": "development",
                "APP_ATTEST_ENVIRONMENT": "development",
            ]),
            .release(name: "Release", settings: [
                "APS_ENVIRONMENT": "production",
                "APP_ATTEST_ENVIRONMENT": "production",
            ]),
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "Vaultify",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "com.bervion.vaultify",
            deploymentTargets: .multiplatform(iOS: "17.3", macOS: "15.0"),
            infoPlist: .extendingDefault(with: [
                // Brand: full name "Loox Password" (App Store listing), short display
                // name "Loox" under the icon. Bundle ids/groups keep the vaultify names.
                "CFBundleDisplayName": "Loox",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleLocalizations": ["en", "vi", "ja"],
                // Analytics is opt-IN. `SettingsStore.analyticsEnabled` defaults to
                // false, but that flag is read by `AnalyticsEngine` AFTER
                // `FirebaseApp.configure()` has already run — configure() is the
                // shared gate crash reporting also needs, so it cannot be skipped.
                // Without this key, GA4 would start collecting on first launch and
                // only be switched off a moment later, which is exactly the
                // "collects nothing until you say so" claim the privacy policy and
                // the About screen now make. The engine re-enables collection at
                // runtime once consent is given.
                "FIREBASE_ANALYTICS_COLLECTION_ENABLED": false,
                // Export compliance: app uses only exempt encryption (standard
                // algorithms protecting the user's own on-device data) → skips the
                // per-upload encryption questionnaire in App Store Connect.
                "ITSAppUsesNonExemptEncryption": false,
                "LSApplicationCategoryType": "public.app-category.utilities",
                // Loox Link interim create token (see `looxLinkAppToken` above).
                "LooxLinkAppToken": .string(looxLinkAppToken),
                // Exported document type for shareable `.vaultheme` custom themes.
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.bervion.vaultify.theme",
                        "UTTypeDescription": "Loox Theme",
                        "UTTypeConformsTo": ["public.json"],
                        "UTTypeTagSpecification": [
                            "public.filename-extension": ["vaultheme"],
                        ],
                    ],
                ],
                // Handle otpauth:// 2FA setup links/QR codes → import into the vault. Makes Vaultify
                // appear in Settings → "Set Up Verification Codes".
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "com.bervion.vaultify.otpauth",
                        "CFBundleURLSchemes": ["otpauth"],
                    ],
                    // AutoFill extension hand-off: it has no CloudKit entitlement, so a
                    // "Request code" tap on a shared TOTP capability opens the app here
                    // instead (see SharedItemDeepLink + VaultShellBehaviors).
                    [
                        "CFBundleURLName": "com.bervion.vaultify.deeplink",
                        "CFBundleURLSchemes": ["vaultify"],
                    ],
                ],
                // Wake on silent CloudKit pushes so cross-device changes pull promptly
                // even when backgrounded (near-real-time sync).
                "UIBackgroundModes": ["remote-notification"],
                // Accept CKShare invitations (Approval Mode: owner shares an
                // approval zone with a looked-up participant).
                "CKSharingSupported": true,
                "NSCameraUsageDescription": "Loox uses the camera to scan 2FA setup QR codes and payment cards.",
                "NSFaceIDUsageDescription": "Loox uses Face ID to unlock your vault.",
                "UIApplicationSupportsIndirectInputEvents": true,
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                ],
                // Background only — a static launch image can't be rounded and gets
                // cached by iOS (a square logo flashed before the rounded SplashView).
                // The logo is shown by SplashView instead. A storyboard (vs a color-only
                // UILaunchScreen) renders the LaunchBackground reliably from the very first
                // cold launch — color-only UILaunchScreen can flash white on first install.
                "UILaunchStoryboardName": "LaunchScreen",
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                // iPad ships as a first-class device, so it takes all four
                // orientations including upside-down (an iPad has no "wrong way
                // up"). Pinned here rather than left to Tuist's default: the
                // orientation set is a submission contract, and the app's own
                // three-orientation iPhone list above would otherwise apply to
                // iPad too the moment the default changes. Deliberately no
                // UIRequiresFullScreen — that key opts the app OUT of Split
                // View and Slide Over, which is the opposite of the decision.
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                // Firebase's automatic screen tracking swizzles UIKit view
                // controllers and reports hosting-controller noise under SwiftUI —
                // screens are logged manually via `.analyticsScreen(_:)` instead.
                "FirebaseAutomaticScreenReportingEnabled": false,
            ]),
            sources: ["Vaultify/**", "VaultifyCore/**"],
            resources: [
                "Vaultify/Assets.xcassets",
                "VaultifyCore/SharedAssets.xcassets",
                // A directory entry on purpose, not the `/**` glob Tuist's warning
                // suggests. Tuist and actool both resolve `.icon` through Launch
                // Services, so when Icon Composer is unregistered this entry drops
                // at generation, where prepare-project.sh names it, instead of
                // crashing actool later.
                "Vaultify/vaultify.icon",
                "Vaultify/Localizable.xcstrings",
                "Vaultify/LaunchScreen.storyboard",
                "Vaultify/Resources/**",
            ],
            dependencies: [
                // Embed the iOS AutoFill extension only on iOS destinations — a single
                // multiplatform target applies its dependency graph to the macOS slice
                // too, and macOS cannot link an iOS-only appExtension.
                .target(name: "VaultifyAutoFill", condition: .when([.ios])),
                // The macOS counterpart. Same sources, separate target: an
                // extension carries ONE Info.plist, and the capability set
                // differs (macOS has no save/generate request types), where a
                // wrong dictionary is a silent AutoFill failure at runtime
                // rather than a build error.
                .target(name: "VaultifyAutoFillMac", condition: .when([.macos])),
                // Safari web extension (identity/card fill) — iOS-only appex,
                // same reasoning as the AutoFill embed above.
                .target(name: "VaultifySafari", condition: .when([.ios])),
                // GA4 without ad identifiers (see `packages` above). App only.
                .package(product: "FirebaseAnalyticsCore"),
                // Crash diagnostics (see `CrashReporter`). App only, for the
                // same reason: an extension must never carry telemetry.
                // dSYMs are uploaded by fastlane after the archive, NOT by an
                // in-Xcode run script — the script's path is derived-data
                // dependent and would silently stop symbolicating on the runner.
                .package(product: "FirebaseCrashlytics"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "vaultify",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_PREVIEWS": "YES",
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
                "SWIFT_OBJC_BRIDGING_HEADER": "Vaultify/Vaultify-Bridging-Header.h",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                // iCloud sync gate: the CloudKit code paths compile only with this flag,
                // matching the iCloud entitlement (container provisioned in the portal).
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) VAULTIFY_ICLOUD",
                // iPhone + iPad (macOS ignores this key).
                "TARGETED_DEVICE_FAMILY": "1,2",
                // Per-SDK entitlements: iOS keeps its file; macOS gets the App-Sandbox
                // variant (Mac App Store requires the sandbox).
                "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Vaultify/Vaultify.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Vaultify/Vaultify.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Vaultify/Vaultify-macOS.entitlements",
                // Hardened runtime is required for Mac App Store distribution (no-op on iOS).
                "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
                // The iOS launch storyboard can't be compiled for macOS (and macOS ignores
                // UILaunchStoryboardName) — exclude it from the mac slice.
                "EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]": "LaunchScreen.storyboard",
            ])
        ),
        .target(
            name: "VaultifyAutoFill",
            // Matches the app's device families: an iPad or Mac (Designed for
            // iPad) install otherwise ships a vault with no AutoFill at all —
            // the system credential picker simply never offers Loox there.
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "com.bervion.vaultify.autofill",
            deploymentTargets: .iOS("17.3"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Loox",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSFaceIDUsageDescription": "Loox uses Face ID to unlock your vault.",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.authentication-services-credential-provider-ui",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).CredentialProviderViewController",
                    "NSExtensionAttributes": [
                        "ASCredentialProviderExtensionCapabilities": [
                            "ProvidesPasswords": true,
                            "ProvidesPasskeys": true,
                            "SupportsConditionalPasskeyRegistration": true,
                            // iOS 18+: AutoFill 2FA / one-time codes — Vaultify generates the
                            // current TOTP from the stored secret when an OTP field is focused.
                            "ProvidesOneTimeCodes": true,
                            // iOS 26.2+: native "Save password in Vaultify" sheet + branded
                            // "Use Strong Password" generation. Older iOS uses the manual
                            // "＋ Create new login" flow. Generation is headless (no extension UI).
                            "SupportsSavePasswordCredentials": true,
                            "SupportsGeneratePasswordCredentials": true,
                            "SupportsGeneratePasswordCredentialsWithUI": false,
                        ],
                    ],
                ],
            ]),
            sources: ["VaultifyAutoFill/**", "VaultifyCore/**"],
            // Share the app's string catalog so the extension localizes (EN + VI) instead of
            // rendering literal keys, plus the diceware wordlist so the in-extension password
            // generator's passphrase mode works (`Bundle.main` resolves to the .appex bundle).
            resources: [
                "Vaultify/Localizable.xcstrings",
                // Localizes the Face ID usage prompt (the extension's own
                // Info.plist carries only the EN base string).
                "Vaultify/Resources/InfoPlist.xcstrings",
                "Vaultify/Resources/eff_large_wordlist.txt",
                "VaultifyCore/SharedAssets.xcassets",
                // An .appex is its own bundle, so it needs its OWN privacy
                // manifest — the app's does not cover it. This one declares no
                // collection (extensions link no Firebase) and only the
                // UserDefaults reasons VaultifyCore actually needs.
                "ExtensionResources/PrivacyInfo.xcprivacy",
            ],
            entitlements: "VaultifyAutoFill/VaultifyAutoFill.entitlements",
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
                "SWIFT_OBJC_BRIDGING_HEADER": "VaultifyAutoFill/VaultifyAutoFill-Bridging-Header.h",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                // The extension carries the same iCloud container as the app
                // (see VaultifyAutoFill.entitlements), so it needs the same
                // compile flag: VaultifyCore's CloudKit paths are `#if`-gated on
                // it. Without it `SharedGrantLiveCheck` returns .unavailable and
                // `PasskeyApprovalTransport` throws .notConfigured before any
                // network call, so every shared-item fill and every ask-each-time
                // passkey fails. Settings are per-target — `$(inherited)` reads
                // the PROJECT base, it does not inherit from the app target.
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) VAULTIFY_ICLOUD",
                // iPhone + iPad, matching the app; an extension narrower than
                // its host silently disables AutoFill on the wider device.
                "TARGETED_DEVICE_FAMILY": "1,2",
                "SKIP_INSTALL": "YES",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
            ])
        ),
        // macOS AutoFill credential provider. Shares every source file with the
        // iOS extension — the platform differences live in `#if canImport(UIKit)`
        // branches inside them, chiefly the hosting controller (NSViewController
        // + NSHostingController on this side).
        .target(
            name: "VaultifyAutoFillMac",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "com.bervion.vaultify.autofill",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Loox",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.authentication-services-credential-provider-ui",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).CredentialProviderViewController",
                    "NSExtensionAttributes": [
                        // Deliberately narrower than iOS: passwords, passkeys and
                        // one-time codes exist on macOS 15; the save/generate
                        // capabilities do not, and advertising one the code cannot
                        // serve breaks the whole provider rather than that feature.
                        "ASCredentialProviderExtensionCapabilities": [
                            "ProvidesPasswords": true,
                            "ProvidesPasskeys": true,
                            "SupportsConditionalPasskeyRegistration": true,
                            "ProvidesOneTimeCodes": true,
                        ],
                    ],
                ],
            ]),
            sources: ["VaultifyAutoFill/**", "VaultifyCore/**"],
            resources: [
                "Vaultify/Localizable.xcstrings",
                "Vaultify/Resources/InfoPlist.xcstrings",
                "Vaultify/Resources/eff_large_wordlist.txt",
                "VaultifyCore/SharedAssets.xcassets",
                // Same manifest as the iOS twin — same shared sources, same
                // App Group defaults access, same absence of telemetry.
                "ExtensionResources/PrivacyInfo.xcprivacy",
            ],
            entitlements: "VaultifyAutoFillMac/VaultifyAutoFillMac.entitlements",
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
                "SWIFT_OBJC_BRIDGING_HEADER": "VaultifyAutoFill/VaultifyAutoFill-Bridging-Header.h",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                // Same reason as the iOS extension: VaultifyCore's CloudKit
                // paths are `#if`-gated on this flag, and settings do not
                // inherit from the app target.
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) VAULTIFY_ICLOUD",
                "SKIP_INSTALL": "YES",
                // A macOS appex sits deeper in the bundle than an iOS one
                // (Contents/PlugIns/…), so the hop back to the host's
                // Frameworks directory is four levels, not two.
                "LD_RUNPATH_SEARCH_PATHS":
                    "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks",
            ])
        ),
        // Safari web extension: MV3 web bundle + native message handler. Safari
        // requires manifest.json (and the script/page files) at the .appex bundle
        // ROOT with _locales/ and images/ keeping their directory layout — so the
        // root files ship as plain resources and only the subdirectories ship as
        // folder references. (A single folder reference on Resources/ would nest
        // everything under a literal Resources/ dir inside the appex, which Safari
        // cannot read and which even trips embedded-binary validation.)
        .target(
            name: "VaultifySafari",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "com.bervion.vaultify.safari",
            deploymentTargets: .iOS("17.3"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Loox",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSFaceIDUsageDescription": "Loox uses Face ID to unlock your vault.",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
                ],
            ]),
            sources: ["VaultifySafari/**/*.swift", "VaultifyCore/**"],
            resources: [
                "VaultifySafari/Resources/manifest.json",
                "VaultifySafari/Resources/background.js",
                "VaultifySafari/Resources/content.js",
                "VaultifySafari/Resources/field-classifier.js",
                "VaultifySafari/Resources/fill-engine.js",
                "VaultifySafari/Resources/signup-detector.js",
                "VaultifySafari/Resources/save-overlay.js",
                "VaultifySafari/Resources/inline-menu.js",
                "VaultifySafari/Resources/popup.html",
                "VaultifySafari/Resources/popup.js",
                "VaultifySafari/Resources/popup.css",
                .folderReference(path: "VaultifySafari/Resources/_locales"),
                .folderReference(path: "VaultifySafari/Resources/images"),
                "Vaultify/Localizable.xcstrings",
                // Localizes the Face ID usage prompt for the extension bundle.
                "Vaultify/Resources/InfoPlist.xcstrings",
                "VaultifyCore/SharedAssets.xcassets",
                // Own bundle, own privacy manifest (see VaultifyAutoFill).
                "ExtensionResources/PrivacyInfo.xcprivacy",
            ],
            entitlements: "VaultifySafari/VaultifySafari.entitlements",
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
                "SWIFT_OBJC_BRIDGING_HEADER": "VaultifySafari/VaultifySafari-Bridging-Header.h",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "TARGETED_DEVICE_FAMILY": "1,2",
                "SKIP_INSTALL": "YES",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
            ])
        ),
        // Unit tests (pure-logic + in-memory store). Hosted by the app so it can
        // `@testable import Vaultify`. Run with `make test`.
        .target(
            name: "VaultifyTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "com.bervion.vaultify.tests",
            deploymentTargets: .iOS("17.3"),
            infoPlist: .default,
            sources: ["VaultifyTests/**"],
            // Frozen parity fixtures (e.g. Loox Link canonical-hash vectors) —
            // tests load them from the bundle instead of retyping values.
            resources: ["VaultifyTests/Fixtures/**"],
            dependencies: [.target(name: "Vaultify")]
        ),
        .target(
            name: "VaultifySnapshotTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "com.bervion.vaultify.snapshot-tests",
            deploymentTargets: .iOS("17.3"),
            infoPlist: .default,
            sources: ["VaultifySnapshotTests/**"],
            dependencies: [
                .target(name: "Vaultify"),
                .package(product: "SnapshotTesting"),
            ]
        ),
        .target(
            name: "VaultifyUITests",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "com.bervion.vaultify.ui-tests",
            deploymentTargets: .iOS("17.3"),
            infoPlist: .default,
            sources: ["VaultifyUITests/**"],
            dependencies: [.target(name: "Vaultify")]
        ),
    ],
    schemes: [
        // Additive dev-only scheme: same app, but the run action loads the local
        // StoreKit configuration (Loox.storekit) so subscription purchases are
        // testable in the simulator without App Store Connect. `make check` uses
        // the auto-generated "Vaultify" scheme for its compile check; CI and
        // `make test` drive the shared "Vaultify-Quality" scheme, which is the
        // one that carries the test targets. The .storekit file is scheme
        // metadata only — it is deliberately NOT a bundle resource.
        .scheme(
            name: "Vaultify-StoreKit",
            shared: true,
            buildAction: .buildAction(targets: ["Vaultify"]),
            testAction: .targets(["VaultifyTests"]),
            runAction: .runAction(
                executable: "Vaultify",
                options: .options(storeKitConfigurationPath: "Loox.storekit")
            )
        ),
        .scheme(
            name: "Vaultify-Quality",
            shared: true,
            buildAction: .buildAction(targets: ["Vaultify"]),
            testAction: .targets([
                "VaultifyTests",
                "VaultifySnapshotTests",
                "VaultifyUITests",
            ]),
            runAction: .runAction(executable: "Vaultify")
        ),
    ]
)
