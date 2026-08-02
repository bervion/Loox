import Foundation

/// The built-in role vocabulary. Role IDs are append-only and frozen once
/// shipped — behavior keys off these, never off editable labels.
nonisolated extension FieldRoleID {
    // credential.*
    static let username = FieldRoleID("credential.username")
    static let password = FieldRoleID("credential.password")
    static let totp = FieldRoleID("credential.totp")
    static let website = FieldRoleID("credential.website")

    // note.*
    static let noteBody = FieldRoleID("note.body")

    // card.*
    static let cardHolder = FieldRoleID("card.holder")
    static let cardNumber = FieldRoleID("card.number")
    static let cardExpiry = FieldRoleID("card.expiry")
    static let cardSecurityCode = FieldRoleID("card.security-code")
    static let cardPIN = FieldRoleID("card.pin")

    // identity.*
    static let fullName = FieldRoleID("identity.full-name")
    static let identityEmail = FieldRoleID("identity.email")
    static let identityPhone = FieldRoleID("identity.phone")
    static let identityAddress = FieldRoleID("identity.address")
    static let dateOfBirth = FieldRoleID("identity.date-of-birth")
    static let idNumber = FieldRoleID("identity.id-number")

    // ssh.*
    static let sshPrivateKey = FieldRoleID("ssh.private-key")
    static let sshPublicKey = FieldRoleID("ssh.public-key")
    static let sshPassphrase = FieldRoleID("ssh.passphrase")
    static let sshAlgorithm = FieldRoleID("ssh.algorithm")
    static let sshFingerprint = FieldRoleID("ssh.fingerprint")
    static let sshComment = FieldRoleID("ssh.comment")
    static let sshUsername = FieldRoleID("ssh.username")
    static let sshHosts = FieldRoleID("ssh.hosts")
    static let sshPurpose = FieldRoleID("ssh.purpose")

    // auth.* (recovery/security-question material)
    static let recoveryCodes = FieldRoleID("auth.recovery-codes")
    static let securityQuestion = FieldRoleID("auth.question")
    static let securityAnswer = FieldRoleID("auth.answer")

    // api.*
    static let apiProvider = FieldRoleID("api.provider")
    static let apiAccount = FieldRoleID("api.account")
    static let apiEnvironment = FieldRoleID("api.environment")
    static let apiBaseURL = FieldRoleID("api.base-url")
    static let apiKeyID = FieldRoleID("api.key-id")
    static let apiToken = FieldRoleID("api.token")
    static let apiHeaderName = FieldRoleID("api.header-name")
    static let apiHeaderPrefix = FieldRoleID("api.header-prefix")
    static let apiScopes = FieldRoleID("api.scopes")
    static let apiRotationURL = FieldRoleID("api.rotation-url")

    // git.*
    static let gitProvider = FieldRoleID("git.provider")
    static let gitHost = FieldRoleID("git.host")
    static let gitUsername = FieldRoleID("git.username")
    static let gitProfileURL = FieldRoleID("git.profile-url")
    static let gitOrganizations = FieldRoleID("git.organizations")
    static let gitRepoPath = FieldRoleID("git.repo-path")

    // apple.* (developer assets)
    static let appleIssuerID = FieldRoleID("apple.issuer-id")
    static let appleKeyID = FieldRoleID("apple.key-id")
    static let appleTeamID = FieldRoleID("apple.team-id")
    static let appleRole = FieldRoleID("apple.role")
    static let appleTopics = FieldRoleID("apple.topics")
    static let appleCertKind = FieldRoleID("apple.certificate-kind")
    static let appleCommonName = FieldRoleID("apple.common-name")
    static let appleSerial = FieldRoleID("apple.serial")
    static let appleFingerprint = FieldRoleID("apple.fingerprint")
    static let appleValidity = FieldRoleID("apple.validity")
    static let appleProfileUUID = FieldRoleID("apple.profile-uuid")
    static let appleAppID = FieldRoleID("apple.app-id")
    static let appleDistribution = FieldRoleID("apple.distribution")
    static let applePlatforms = FieldRoleID("apple.platforms")
    static let appleP12Passphrase = FieldRoleID("apple.p12-passphrase")

    // tls.*
    static let tlsSubject = FieldRoleID("tls.subject")
    static let tlsIssuer = FieldRoleID("tls.issuer")
    static let tlsSerial = FieldRoleID("tls.serial")
    static let tlsFingerprint = FieldRoleID("tls.fingerprint")
    static let tlsValidity = FieldRoleID("tls.validity")

    // artifact.*
    static let artifactFile = FieldRoleID("artifact.file")
}

/// The built-in kind vocabulary. Same append-only freeze rule.
nonisolated extension ItemKindID {
    static let login = ItemKindID("credential.login")
    static let secureNote = ItemKindID("note.secure")
    static let paymentCard = ItemKindID("finance.card")
    static let personalIdentity = ItemKindID("identity.personal")
    static let sshKey = ItemKindID("developer.ssh-key")
    static let recoveryCodes = ItemKindID("auth.recovery-codes")
    static let securityQuestions = ItemKindID("auth.security-questions")
    static let custom = ItemKindID("custom.free")
    static let apiSecret = ItemKindID("developer.api-secret")
    static let gitAccount = ItemKindID("developer.git-account")
    static let ascAPIKey = ItemKindID("developer.asc-api-key")
    static let apnsKey = ItemKindID("developer.apns-key")
    static let signingIdentity = ItemKindID("developer.signing-identity")
    static let provisioningProfile = ItemKindID("developer.provisioning-profile")
    static let tlsCertificate = ItemKindID("developer.tls-certificate")
}

/// Typed link roles (`ItemLink.roleID` values).
nonisolated enum LinkRole {
    static let authKey = "link.auth-key"
    static let signingKey = "link.signing-key"
    static let apiSecret = "link.api-secret"
    static let recovery = "link.recovery"
    static let certificate = "link.certificate"
    static let privateKey = "link.private-key"
}
