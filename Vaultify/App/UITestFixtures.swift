#if DEBUG
import Foundation
import SwiftData

/// Synthetic data used only by deterministic Debug UI-test launches.
@MainActor
enum UITestFixtures {
    static let folderID = "ui-test-space"
    static let itemID = "ui-test-login"
    static let initialTitle = "Acme Login"
    static let editedTitle = "Acme Production"

    static func install(
        _ configuration: UITestConfiguration,
        store: VaultStore,
        repository: VaultRepository
    ) throws {
        guard configuration.fixture != nil else { return }
        guard let key = repository.session.vaultKey else { throw AuthError.locked }

        let fixedDate = Date(timeIntervalSince1970: 1_704_067_200)
        repository.reload()
        // Relaunches reuse the already-seeded container — the panic-restart
        // journey kills and restarts the app — so reseeding must not run twice.
        if repository.items.contains(where: { $0.id == itemID }) {
            if configuration.fixture == .privateEmailMemberUX { try installPrivateEmailMemberUX(store: store, repository: repository) }
            return
        }

        let folder = Folder(
            id: folderID,
            name: "Quality Space",
            iconAsset: Icons.lockFill,
            color: .blue,
            sortIndex: 0,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            personaId: repository.activePersona?.id
        )
        let folderRecord = FolderRecord(
            id: folder.id,
            sealed: try repository.sealFolder(folder, key: key),
            iconAsset: folder.iconAsset,
            colorRaw: folder.color.rawValue,
            sortIndex: folder.sortIndex,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt
        )
        store.context.insert(folderRecord)
        try store.context.save()
        repository.reload()

        let item = VaultItem(
            id: itemID,
            category: .login,
            title: initialTitle,
            folderId: folderID,
            fields: [
                DynamicField(
                    id: "ui-test-username",
                    label: "Username",
                    kind: .username,
                    value: "quality@example.invalid"
                ),
                DynamicField(
                    id: "ui-test-password",
                    label: "Password",
                    kind: .password,
                    value: "synthetic-fixture-value"
                ),
            ],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try AnalyticsEngine.shared.runSuppressed {
            try repository.add(item)
        }
        if configuration.fixture == .privateEmailMemberUX { try installPrivateEmailMemberUX(store: store, repository: repository) }
    }

    static let reusableAliasID = "ui-test-reusable-alias"
    static let serviceAliasID = "ui-test-service-alias"
    static let inboxID = "ui-test-forwarding-inbox"
    static let recipient = "quality-recipient@example.invalid"

    /// Existing issued addresses and a verified destination are local fixture
    /// records, not proof that the relay/domain/mail pipeline works.
    static func installPrivateEmailMemberUX(store: VaultStore, repository: VaultRepository) throws {
        guard let key = repository.session.vaultKey, let persona = repository.activePersona else { throw AuthError.locked }
        guard !repository.aliases.contains(where: { $0.id == reusableAliasID }) else { return }
        let fixedDate = Date(timeIntervalSince1970: 1_704_067_200)
        let inbox = ForwardingInbox(id: inboxID, email: recipient, label: "Quality inbox",
                                    isDefault: true, relayDestinationID: "synthetic-destination",
                                    verificationStatus: .verified, createdAt: fixedDate, updatedAt: fixedDate)
        store.context.insert(ForwardingInboxRecord(id: inbox.id,
            sealed: try repository.sealInbox(inbox, key: key), sortIndex: 0,
            createdAt: fixedDate, updatedAt: fixedDate))
        let aliases = [
            EmailAlias(id: reusableAliasID, personaId: persona.id, tier: .persona,
                       localPart: "quality-shared", label: "Personal services", status: .active,
                       forwardingInboxID: inbox.id, forwardingTarget: recipient, backendMinted: true,
                       sortIndex: 0, createdAt: fixedDate, updatedAt: fixedDate),
            EmailAlias(id: serviceAliasID, personaId: persona.id, tier: .perSite,
                       localPart: "quality-github", boundDomain: "github.com", label: "GitHub Work",
                       status: .paused, forwardingInboxID: inbox.id, forwardingTarget: recipient,
                       backendMinted: true, sortIndex: 1, createdAt: fixedDate, updatedAt: fixedDate),
        ]
        for alias in aliases {
            store.context.insert(EmailAliasRecord(id: alias.id,
                sealed: try repository.sealAlias(alias, key: key), sortIndex: alias.sortIndex,
                createdAt: fixedDate, updatedAt: fixedDate))
        }
        try store.context.save()
        repository.reload()
        for (id, title, host, aliasID) in [
            ("ui-test-facebook", "Facebook", "facebook.com", reusableAliasID),
            ("ui-test-gmail", "Gmail", "mail.google.com", reusableAliasID),
            ("ui-test-github", "GitHub", "github.com", serviceAliasID),
        ] {
            let item = VaultItem(id: id, category: .login, title: title, folderId: folderID, fields: [
                DynamicField(label: "Username", kind: .username, value: "quality-user"),
                DynamicField(label: "Email", kind: .email, value: "original@example.invalid"),
                DynamicField(label: "Website", kind: .url, value: "https://" + host),
            ], createdAt: fixedDate, updatedAt: fixedDate)
            try repository.add(item)
            try repository.linkAliasToLogin(aliasID: aliasID, itemID: item.id)
        }
        let legacy = VaultItem(id: "ui-test-legacy-login", category: .login, title: "Older saved login",
            folderId: folderID, fields: [DynamicField(label: "Email", kind: .email,
                value: aliases[0].resolvedAddress ?? "")], createdAt: fixedDate, updatedAt: fixedDate)
        try repository.add(legacy)
    }
}
#endif
