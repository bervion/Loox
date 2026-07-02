import ProjectDescription

// Single source of truth for the Xcode project. Run `tuist generate` to produce
// Vaultify.xcodeproj / Vaultify.xcworkspace — both are gitignored and generated
// per machine, so a beta-Xcode dev and a stable-Xcode CI runner each get a
// project file their Xcode can open. Version lives here (bumped by release.sh).

let project = Project(
    name: "Vaultify",
    options: .options(
        defaultKnownRegions: ["en", "vi"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "WDNL2F75V7",
            "MARKETING_VERSION": "1.7.0",
            "CURRENT_PROJECT_VERSION": "13",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "SWIFT_VERSION": "5.0",
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "Vaultify",
            destinations: [.iPhone],
            product: .app,
            bundleId: "com.bervion.vaultify",
            deploymentTargets: .iOS("17.6"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Vaultify",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleLocalizations": ["en", "vi"],
                // Export compliance: app uses only exempt encryption (standard
                // algorithms protecting the user's own on-device data) → skips the
                // per-upload encryption questionnaire in App Store Connect.
                "ITSAppUsesNonExemptEncryption": false,
                "LSApplicationCategoryType": "public.app-category.utilities",
                // Exported document type for shareable `.vaultheme` custom themes.
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.bervion.vaultify.theme",
                        "UTTypeDescription": "Vaultify Theme",
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
                ],
                "NSCameraUsageDescription": "Vaultify uses the camera to scan 2FA setup QR codes.",
                "NSFaceIDUsageDescription": "Vaultify uses Face ID to unlock your vault.",
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
            ]),
            sources: ["Vaultify/**", "VaultifyCore/**"],
            resources: [
                "Vaultify/Assets.xcassets",
                "Vaultify/vaultify.icon",
                "Vaultify/Localizable.xcstrings",
                "Vaultify/LaunchScreen.storyboard",
                "Vaultify/Resources/**",
            ],
            entitlements: "Vaultify/Vaultify.entitlements",
            dependencies: [
                .target(name: "VaultifyAutoFill"),
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
                "TARGETED_DEVICE_FAMILY": "1",
            ])
        ),
        .target(
            name: "VaultifyAutoFill",
            destinations: [.iPhone],
            product: .appExtension,
            bundleId: "com.bervion.vaultify.autofill",
            deploymentTargets: .iOS("17.6"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Vaultify",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSFaceIDUsageDescription": "Vaultify uses Face ID to unlock your vault.",
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
                "Vaultify/Resources/eff_large_wordlist.txt",
            ],
            entitlements: "VaultifyAutoFill/VaultifyAutoFill.entitlements",
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
                "SWIFT_OBJC_BRIDGING_HEADER": "VaultifyAutoFill/VaultifyAutoFill-Bridging-Header.h",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "TARGETED_DEVICE_FAMILY": "1",
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
            deploymentTargets: .iOS("17.6"),
            infoPlist: .default,
            sources: ["VaultifyTests/**"],
            dependencies: [.target(name: "Vaultify")]
        ),
    ]
)
