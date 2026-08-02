import SwiftUI

/// One primary, safe action per developer template — the task the user came
/// to do: copy the PUBLIC key of an SSH item, copy an API token behind
/// re-auth, copy a Git setup snippet. High-risk material never gets a primary
/// button; it stays behind the per-field reveal policy.
struct TemplateActionsCard: View {
    let item: VaultItem

    @Environment(AppEnvironment.self) private var env
    @State private var confirmation: LocalizedStringKey?

    var body: some View {
        if let action = primaryAction {
            VStack(spacing: Space.s2) {
                Button {
                    action.perform()
                } label: {
                    Label { Text(action.title) } icon: { VaultIcon(action.icon, size: Metric.iconInline) }
                        .vaultType(.headline)
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .themedForeground(.accentText)
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
                .elevation(.level1)
                if let confirmation {
                    Text(confirmation)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .transition(.opacity)
                }
            }
        }
    }

    private struct PrimaryAction {
        let title: LocalizedStringKey
        let icon: String
        let perform: () -> Void
    }

    private var primaryAction: PrimaryAction? {
        guard item.sharedOrigin == nil, !item.isUnsupportedSchema,
              let kind = item.kindID else { return nil }
        switch kind {
        case .sshKey:
            guard let publicKey = item.fields.first(where: { $0.roleID == .sshPublicKey }),
                  !publicKey.isEmpty, !publicKey.isExtraProtected else { return nil }
            return PrimaryAction(title: "Copy Public Key", icon: Icons.copy) {
                env.clipboard.copy(publicKey.value, label: publicKey.label, sensitive: false)
                env.repository.markUsed(item)
                flash("Public key copied")
            }
        case .apiSecret:
            guard let token = item.fields.first(where: { $0.roleID == .apiToken }),
                  !token.isEmpty, !token.isExtraProtected else { return nil }
            return PrimaryAction(title: "Copy Token", icon: Icons.copy) {
                Task {
                    do {
                        try await env.session.requireBiometrics(reason: appString("Confirm it’s you"))
                        env.clipboard.copy(token.value, label: token.label, sensitive: true)
                        env.repository.markUsed(item)
                        flash("Token copied. It clears from the clipboard automatically.")
                    } catch {
                        Haptics.warning()
                    }
                }
            }
        case .gitAccount:
            guard let snippet = GitSnippets.setupSnippet(for: item) else { return nil }
            return PrimaryAction(title: "Copy Setup Snippet", icon: Icons.copy) {
                env.clipboard.copy(snippet, label: appString("Setup snippet"), sensitive: false)
                env.repository.markUsed(item)
                flash("Snippet copied")
            }
        default:
            return nil
        }
    }

    private func flash(_ message: LocalizedStringKey) {
        withAnimation(.easeOut(duration: 0.18)) { confirmation = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.3)) { confirmation = nil }
        }
    }
}

/// Pure snippet construction for Git Hosting Accounts. Copy-only — nothing is
/// ever executed, and no secret value enters a snippet (linked tokens/keys
/// stay in their own items). A clone snippet exists ONLY when an explicit
/// repository path is stored; account-only items get config/SSH-host lines.
nonisolated enum GitSnippets {
    static func setupSnippet(for item: VaultItem) -> String? {
        func value(_ role: FieldRoleID) -> String? {
            guard let field = item.fields.first(where: { $0.roleID == role }),
                  !field.isEmpty, !field.protected, !field.isExtraProtected else { return nil }
            return field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let host = value(.gitHost)
        let username = value(.gitUsername)
        let repoPath = value(.gitRepoPath)

        var lines: [String] = []
        if let username {
            lines.append("git config user.name \(shellQuoted(username))")
        }
        if let host, let repoPath {
            lines.append("git clone git@\(host):\(repoPath).git")
        } else if let host {
            lines.append("ssh -T git@\(host)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Single-quote shell quoting — the value rides inside a snippet the USER
    /// pastes; it must never be able to break out of its quoting.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
