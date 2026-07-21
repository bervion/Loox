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
        guard configuration.fixture == .vaultEditSaveRelock else { return }
        guard let key = repository.session.vaultKey else { throw AuthError.locked }

        let fixedDate = Date(timeIntervalSince1970: 1_704_067_200)
        repository.reload()

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
    }
}
#endif
