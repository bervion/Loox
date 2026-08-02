import Foundation

/// The compile-time template registry: every built-in item type, its
/// composition, and its capability policy. Code-reviewed data, never
/// downloaded, never user-supplied.
///
/// Registry policy is a trusted MINIMUM: stored/imported field policy may only
/// tighten what the registry says, never relax it. A kind or role the registry
/// does not know receives secret-safe defaults and zero external capability.
nonisolated enum ItemTemplateRegistry {

    /// Kind → definition. The single lookup integrations use (via the
    /// resolver — feature code should not consult the registry directly for
    /// capability decisions).
    static func definition(for kindID: ItemKindID) -> ItemTemplateDefinition? {
        byKind[kindID]
    }

    /// The template a LEGACY (pre-semantic) category maps onto for rendering
    /// and inference. Every shipped category has one.
    static func definition(forLegacy category: ItemCategory) -> ItemTemplateDefinition? {
        byKind[legacyKind(for: category)]
    }

    /// Stable kind for each legacy category.
    static func legacyKind(for category: ItemCategory) -> ItemKindID {
        switch category {
        case .login: .login
        case .note: .secureNote
        case .card: .paymentCard
        case .identity: .personalIdentity
        case .sshKey: .sshKey
        case .recoveryCodes: .recoveryCodes
        case .securityQuestions: .securityQuestions
        case .custom: .custom
        }
    }

    /// Every registered template, picker order within family preserved.
    static let all: [ItemTemplateDefinition] = legacyTemplates + developerTemplates

    private static let byKind: [ItemKindID: ItemTemplateDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.kindID, $0) })

    // MARK: - Legacy eight (parity with `ItemCategory.fieldTemplate`)

    private static let legacyTemplates: [ItemTemplateDefinition] = [
        ItemTemplateDefinition(
            kindID: .login, version: 1, family: .common, legacyCategory: .login,
            title: "Login", blurb: "Website and app passwords",
            iconAsset: "ic_globe", avatarIcon: "dt_globe",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .username, label: "Username", kind: .username,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .password, label: "Password", kind: .password,
                                            protected: true, sensitivity: .secret),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                c.loginAutoFill = true; c.totpSource = true; c.safariLoginListing = true
                c.passwordAudit = true; c.loginHygieneAudit = true
                c.spaceShareEligible = true; c.quickShareEligible = true
                c.approvalShareEligible = true
                c.csvCredentialExport = true; c.credentialExchangeExport = true
                return c
            }(),
            subtitleRole: .username),

        ItemTemplateDefinition(
            kindID: .secureNote, version: 1, family: .common, legacyCategory: .note,
            title: "Secure Note", blurb: "Private text, encrypted at rest",
            iconAsset: "ic_note", avatarIcon: "dt_note",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .noteBody, label: "Note", kind: .multiline,
                                            sensitivity: .private),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                c.quickShareEligible = true; c.approvalShareEligible = true
                c.credentialExchangeExport = true
                return c
            }(),
            subtitleRole: nil),

        ItemTemplateDefinition(
            kindID: .paymentCard, version: 1, family: .finance, legacyCategory: .card,
            title: "Payment Card", blurb: "Card numbers, PINs, and CVV",
            iconAsset: "ic_credit_card", avatarIcon: "dt_credit_card",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .cardHolder, label: "Cardholder", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .cardNumber, label: "Card Number", kind: .monospace,
                                            protected: true, sensitivity: .secret),
                    TemplateFieldDescriptor(roleID: .cardExpiry, label: "Expiry", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .cardSecurityCode, label: "Security Code", kind: .monospace,
                                            protected: true, sensitivity: .secret),
                    TemplateFieldDescriptor(roleID: .cardPIN, label: "PIN", kind: .number,
                                            protected: true, sensitivity: .secret,
                                            actionAuthorization: .reauthenticate),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                c.cardFill = true
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: .cardHolder),

        ItemTemplateDefinition(
            kindID: .personalIdentity, version: 1, family: .personal, legacyCategory: .identity,
            title: "Identity", blurb: "Personal and contact details",
            iconAsset: "ic_identity_card", avatarIcon: "dt_id_card",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .fullName, label: "Full Name", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .identityEmail, label: "Email", kind: .email,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .identityPhone, label: "Phone", kind: .phone,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .identityAddress, label: "Address", kind: .multiline,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .dateOfBirth, label: "Date of Birth", kind: .date,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .idNumber, label: "ID Number", kind: .monospace,
                                            protected: true, sensitivity: .secret),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                c.identityFill = true
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: .identityEmail),

        ItemTemplateDefinition(
            kindID: .sshKey, version: 2, family: .developer, legacyCategory: .sshKey,
            title: "SSH Key", blurb: "Key pairs with fingerprint and import",
            iconAsset: "ic_key", avatarIcon: "dt_key",
            sections: [
                TemplateSection(id: "keys", fields: [
                    TemplateFieldDescriptor(roleID: .sshPrivateKey, label: "Private Key", kind: .multiline,
                                            protected: true, sensitivity: .keyMaterial,
                                            actionAuthorization: .reauthenticate),
                    TemplateFieldDescriptor(roleID: .sshPublicKey, label: "Public Key", kind: .multiline,
                                            sensitivity: .public),
                    TemplateFieldDescriptor(roleID: .sshPassphrase, label: "Passphrase", kind: .password,
                                            protected: true, sensitivity: .secret,
                                            actionAuthorization: .reauthenticate, isDefault: false),
                ]),
                TemplateSection(id: "metadata", title: "Key Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .sshAlgorithm, label: "Algorithm", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .sshFingerprint, label: "Fingerprint", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .sshComment, label: "Comment", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .sshUsername, label: "Username", kind: .username,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .sshHosts, label: "Hosts", kind: .text,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .sshPurpose, label: "Purpose", kind: .text,
                                            sensitivity: .private, isDefault: false),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                // Sharing stays possible at the ITEM level so a public key can
                // travel; field policy denies the private key and passphrase.
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: .sshFingerprint),

        ItemTemplateDefinition(
            kindID: .recoveryCodes, version: 1, family: .common, legacyCategory: .recoveryCodes,
            title: "Recovery Codes", blurb: "Backup codes for two-factor sign in",
            iconAsset: "ic_refresh", avatarIcon: "dt_life_ring",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .recoveryCodes, label: "Recovery Codes", kind: .multiline,
                                            protected: true, sensitivity: .keyMaterial,
                                            actionAuthorization: .reauthenticate),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: nil),

        ItemTemplateDefinition(
            kindID: .securityQuestions, version: 1, family: .personal, legacyCategory: .securityQuestions,
            title: "Security Questions", blurb: "Question and answer pairs",
            iconAsset: "ic_question_circle", avatarIcon: "dt_question",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .securityQuestion, label: "Question 1", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .securityAnswer, label: "Answer 1", kind: .text,
                                            protected: true, sensitivity: .secret),
                    TemplateFieldDescriptor(roleID: .securityQuestion, label: "Question 2", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .securityAnswer, label: "Answer 2", kind: .text,
                                            protected: true, sensitivity: .secret),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: nil),

        ItemTemplateDefinition(
            kindID: .custom, version: 1, family: .common, legacyCategory: .custom,
            title: "Custom", blurb: "Your own fields, any shape",
            iconAsset: "ic_metafields", avatarIcon: "dt_sliders_up",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: nil, label: "Field", kind: .text,
                                            sensitivity: .private),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                // Parity with shipped duck-typing: a custom item carrying real
                // credential fields participates in fill/audit surfaces.
                c.loginAutoFill = true; c.totpSource = true; c.safariLoginListing = true
                c.passwordAudit = true
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: nil),
    ]

    // MARK: - Developer pack (Phases 5 + 6)

    private static let developerTemplates: [ItemTemplateDefinition] = [
        ItemTemplateDefinition(
            kindID: .apiSecret, version: 1, family: .developer, legacyCategory: .custom,
            title: "API Secret", blurb: "Tokens, keys, and service credentials",
            iconAsset: "ic_hashtag", avatarIcon: "dt_code",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .apiProvider, label: "Provider", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .apiToken, label: "Token", kind: .password,
                                            protected: true, sensitivity: .secret,
                                            actionAuthorization: .reauthenticate),
                    TemplateFieldDescriptor(roleID: .apiEnvironment, label: "Environment", kind: .text,
                                            sensitivity: .private),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .apiAccount, label: "Account", kind: .username,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiBaseURL, label: "Base URL", kind: .url,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiKeyID, label: "Key ID", kind: .monospace,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiHeaderName, label: "Header Name", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiHeaderPrefix, label: "Header Prefix", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiScopes, label: "Scopes", kind: .text,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .apiRotationURL, label: "Rotation URL", kind: .url,
                                            sensitivity: .private, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .apiEnvironment),

        ItemTemplateDefinition(
            kindID: .gitAccount, version: 1, family: .developer, legacyCategory: .custom,
            title: "Git Hosting Account", blurb: "Hosting profile with linked keys and tokens",
            iconAsset: "ic_organization", avatarIcon: "dt_sitemap",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .gitProvider, label: "Provider", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .gitHost, label: "Host", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .gitUsername, label: "Username", kind: .username,
                                            sensitivity: .private),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .gitProfileURL, label: "Profile URL", kind: .url,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .gitOrganizations, label: "Organizations", kind: .text,
                                            sensitivity: .private, isDefault: false),
                    TemplateFieldDescriptor(roleID: .gitRepoPath, label: "Repository", kind: .text,
                                            sensitivity: .private, isDefault: false),
                ]),
            ],
            capabilities: {
                var c = ItemCapabilities()
                // Account metadata only — secrets live in LINKED items.
                c.quickShareEligible = true; c.approvalShareEligible = true
                return c
            }(),
            subtitleRole: .gitUsername),

        ItemTemplateDefinition(
            kindID: .ascAPIKey, version: 1, family: .developer, legacyCategory: .custom,
            title: "App Store Connect API Key", blurb: "Issuer, key ID, and the .p8 you can only download once",
            iconAsset: "ic_logo_apple", avatarIcon: "dt_apple_whole",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .appleKeyID, label: "Key ID", kind: .monospace,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleIssuerID, label: "Issuer ID", kind: .monospace,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleTeamID, label: "Team ID", kind: .monospace,
                                            sensitivity: .private),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .appleRole, label: "Role", kind: .text,
                                            sensitivity: .private, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .appleKeyID),

        ItemTemplateDefinition(
            kindID: .apnsKey, version: 1, family: .developer, legacyCategory: .custom,
            title: "APNs Authentication Key", blurb: "Push notification signing key",
            iconAsset: "ic_notification", avatarIcon: "dt_bell",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .appleKeyID, label: "Key ID", kind: .monospace,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleTeamID, label: "Team ID", kind: .monospace,
                                            sensitivity: .private),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .appleTopics, label: "Topics", kind: .text,
                                            sensitivity: .private, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .appleKeyID),

        ItemTemplateDefinition(
            kindID: .signingIdentity, version: 1, family: .developer, legacyCategory: .custom,
            title: "Apple Signing Identity", blurb: "Distribution certificate and private key (.p12)",
            iconAsset: "ic_shield_check_mark", avatarIcon: "dt_id_badge",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .appleCommonName, label: "Common Name", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleTeamID, label: "Team ID", kind: .monospace,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleP12Passphrase, label: "Passphrase", kind: .password,
                                            protected: true, sensitivity: .secret,
                                            actionAuthorization: .reauthenticate),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .appleCertKind, label: "Certificate Type", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .appleSerial, label: "Serial", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .appleFingerprint, label: "Fingerprint", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .appleValidity, label: "Valid Until", kind: .date,
                                            sensitivity: .public, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .appleTeamID),

        ItemTemplateDefinition(
            kindID: .provisioningProfile, version: 1, family: .developer, legacyCategory: .custom,
            title: "Provisioning Profile", blurb: "App ID, entitlements, devices, and expiry",
            iconAsset: "ic_clipboard", avatarIcon: "dt_files",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .appleAppID, label: "App Identifier", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleTeamID, label: "Team ID", kind: .monospace,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .appleValidity, label: "Expires", kind: .date,
                                            sensitivity: .public),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .appleProfileUUID, label: "UUID", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .appleDistribution, label: "Distribution", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .applePlatforms, label: "Platforms", kind: .text,
                                            sensitivity: .public, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .appleAppID),

        ItemTemplateDefinition(
            kindID: .tlsCertificate, version: 1, family: .developer, legacyCategory: .custom,
            title: "TLS Certificate", blurb: "Certificates with validity and fingerprint",
            iconAsset: "ic_domain_landing_page", avatarIcon: "dt_shield_halved",
            sections: [
                TemplateSection(id: "core", fields: [
                    TemplateFieldDescriptor(roleID: .tlsSubject, label: "Subject", kind: .text,
                                            sensitivity: .private),
                    TemplateFieldDescriptor(roleID: .tlsValidity, label: "Valid Until", kind: .date,
                                            sensitivity: .public),
                ]),
                TemplateSection(id: "details", title: "Details", isAdvanced: true, fields: [
                    TemplateFieldDescriptor(roleID: .tlsIssuer, label: "Issuer", kind: .text,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .tlsSerial, label: "Serial", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                    TemplateFieldDescriptor(roleID: .tlsFingerprint, label: "Fingerprint", kind: .monospace,
                                            sensitivity: .public, isDefault: false),
                ]),
            ],
            capabilities: ItemCapabilities(),
            subtitleRole: .tlsSubject),
    ]
}
