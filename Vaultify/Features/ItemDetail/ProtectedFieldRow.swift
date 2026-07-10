import SwiftUI

/// A field with second-layer ("Extra") protection. Shown locked until revealed
/// with the app-wide Level-2 password or the field's custom code. Copy / Large
/// Type act on the revealed value; "Remove Protection" unseals it.
struct ProtectedFieldRow: View {
    let field: DynamicField
    let onChange: (DynamicField) -> Void
    var onUsed: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var plaintext: String?
    @State private var copied = false
    @State private var error: String?
    @State private var showLevel2Prompt = false
    @State private var showCustomPrompt = false
    @State private var showLargeType = false

    private var scheme: SecretGuard.Scheme? { SecretGuard.scheme(of: field.value) }
    private var theme: AppTheme { env.theme.active }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                fieldLabelText(field.label)
                    .vaultType(.caption).fontWeight(.medium)
                    .foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85) : theme.color(.accent))
                value
                if let error { Text(error).vaultType(.caption).foregroundStyle(copied ? theme.color(.onAccent) : VaultColors.strengthWeak) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Space.gutter).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(copied ? theme.color(.accent) : Color.clear)
        .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.primary))
        .contentShape(.rect)
        .onTapGesture { primaryTap() }
        .animation(.easeOut(duration: 0.18), value: copied)
        .sheet(isPresented: $showLevel2Prompt) {
            CodePromptSheet(title: "Extra Password", message: "Enter your Level-2 password to reveal this field.",
                            confirmLabel: "Reveal", onSubmit: unlockLevel2AndReveal)
        }
        .sheet(isPresented: $showCustomPrompt) {
            CodePromptSheet(title: "Field Code", message: "Enter this field's code to reveal it.",
                            confirmLabel: "Reveal", onSubmit: revealCustom)
        }
        .platformFullScreenCover(isPresented: $showLargeType) { LargeTypeView(text: plaintext ?? "") }
    }

    @ViewBuilder private var value: some View {
        if copied {
            Text("Copied").vaultType(.body)
        } else if let plaintext {
            Text(plaintext).font(.vaultCode()).textSelection(.enabled).lineLimit(nil)
        } else {
            HStack(spacing: 6) {
                PolarisIcon(Icons.lockFill, size: 14).themedForeground(.secondary)
                Text("Protected. Tap to reveal").vaultType(.subhead).themedForeground(.secondary)
            }
        }
    }

    private var trailing: some View {
        Menu {
            if plaintext == nil {
                Button { primaryTap() } label: { Label("Reveal", image: Icons.reveal) }
            } else {
                Button { copy() } label: { Label("Copy", image: Icons.copy) }
                Button { showLargeType = true } label: { Label("Large Type", image: "ic_text") }
                Button { plaintext = nil } label: { Label("Conceal", image: Icons.hide) }
                Button(role: .destructive) { removeProtection() } label: {
                    Label("Remove Protection", image: Icons.lock)
                }
            }
        } label: {
            PolarisIcon("ic_menu_horizontal", size: 17)
                .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.secondary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(copied ? theme.color(.onAccent).opacity(0.22) : VaultColors.fill))
                // Invisible padded hit area: the visual circle stays 30pt, the
                // tappable region meets the 44pt minimum (rule 6).
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .contentShape(Rectangle())
        }
        // Plain glyph menu — macOS would otherwise draw a bordered pull-down button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func primaryTap() {
        if let plaintext { copyText(plaintext); return }
        error = nil
        switch scheme {
        case .level2:
            if let key = env.session.level2Key {
                revealLevel2(with: key.bytes)
            } else {
                showLevel2Prompt = true
            }
        case .custom:
            showCustomPrompt = true
        case .none:
            error = appString("This field is malformed.")
        }
    }

    private func revealLevel2(with key: [UInt8]) {
        if let text = try? SecretGuard.openLevel2(field.value, l2Key: key) {
            withAnimation { plaintext = text }
            onUsed()
            // Crossing the Extra Protection boundary is a risky state (rule:
            // haptics vocabulary), distinct from the plain `.success` on copy.
            Haptics.warning()
        } else {
            error = appString("Couldn’t decrypt this field.")
        }
    }

    private func unlockLevel2AndReveal(_ password: String) async -> String? {
        do {
            try await env.session.unlockLevel2(password: password)
            guard let key = env.session.level2Key else { return appString("Unlock failed.") }
            revealLevel2(with: key.bytes)
            return nil
        } catch {
            return appString("Incorrect Level-2 password.")
        }
    }

    private func revealCustom(_ code: String) async -> String? {
        do {
            let text = try await SecretGuard.openCustom(field.value, code: code)
            withAnimation { plaintext = text }
            onUsed()
            // Crossing the Extra Protection boundary is a risky state (rule:
            // haptics vocabulary), distinct from the plain `.success` on copy.
            Haptics.warning()
            return nil
        } catch {
            return appString("Incorrect code.")
        }
    }

    private func copy() { if let plaintext { copyText(plaintext) } }

    private func copyText(_ text: String) {
        env.clipboard.copy(text, label: field.label, sensitive: true)
        onUsed()
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation { copied = false } }
    }

    private func removeProtection() {
        guard let plaintext else { return }
        var updated = field
        updated.value = plaintext
        updated.guard2 = false
        onChange(updated)
    }
}
