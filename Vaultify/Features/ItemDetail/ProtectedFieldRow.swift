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
    /// Removal asked while still locked — reveal first (prompting if needed),
    /// then fall through to the confirmation below.
    @State private var pendingRemoval = false
    @State private var confirmRemoval = false

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
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(copied ? theme.color(.accent) : Color.clear)
        .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.primary))
        .contentShape(.rect)
        .onTapGesture { primaryTap() }
        .animation(.easeOut(duration: 0.18), value: copied)
        .sheet(isPresented: $showLevel2Prompt) {
            CodePromptSheet(title: "Extra Password",
                            message: "Enter your Extra Password to reveal this field.",
                            confirmLabel: "Reveal", placeholder: "Extra Password",
                            onSubmit: unlockLevel2AndReveal)
        }
        .sheet(isPresented: $showCustomPrompt) {
            CodePromptSheet(title: "Custom code",
                            message: "Enter this field's custom code to reveal it.",
                            confirmLabel: "Reveal", placeholder: "Custom code",
                            onSubmit: revealCustom)
        }
        .platformFullScreenCover(isPresented: $showLargeType) { LargeTypeView(text: plaintext ?? "") }
        .confirmationDialog("Remove protection from this field?", isPresented: $confirmRemoval,
                            titleVisibility: .visible) {
            Button("Remove Protection", role: .destructive) { removeProtection() }
        } message: {
            Text("The value will be visible like a normal field.")
        }
    }

    @ViewBuilder private var value: some View {
        if copied {
            Text("Copied").vaultType(.body)
        } else if let plaintext {
            Text(plaintext).font(.vaultCode()).textSelection(.enabled).lineLimit(nil)
        } else {
            HStack(spacing: 6) {
                PolarisIcon(Icons.lockFill, size: 14).themedForeground(.secondary)
                // Name the secret up front — which prompt appears on tap must
                // not be a surprise (Extra Password unlocks the session once;
                // a custom code is asked every time).
                Text(scheme == .custom ? "Protected. Reveal with custom code"
                                       : "Protected. Reveal with Extra Password")
                    .vaultType(.subhead).themedForeground(.secondary)
            }
        }
    }

    private var trailing: some View {
        Menu {
            if plaintext == nil {
                Button { primaryTap() } label: { Label("Reveal", image: Icons.reveal) }
                // Unprotecting must not require FINDING the reveal first — ask
                // for the secret here, then confirm.
                Button(role: .destructive) { requestRemoval() } label: {
                    Label("Remove Protection", image: Icons.lock)
                }
            } else {
                Button { copy() } label: { Label("Copy", image: Icons.copy) }
                Button { showLargeType = true } label: { Label("Large Type", image: "ic_text") }
                Button { plaintext = nil } label: { Label("Conceal", image: Icons.hide) }
                Button(role: .destructive) { requestRemoval() } label: {
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
            finishPendingRemoval()
        } else {
            error = appString("Couldn’t decrypt this field.")
            pendingRemoval = false
        }
    }

    private func unlockLevel2AndReveal(_ password: String) async -> String? {
        do {
            try await env.session.unlockLevel2(password: password)
            guard let key = env.session.level2Key else { return appString("Unlock failed.") }
            revealLevel2(with: key.bytes)
            return nil
        } catch {
            return (error as? AuthError)?.errorDescription ?? appString("Incorrect Extra Password.")
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
            finishPendingRemoval()
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

    /// Removal entry point from either menu state: with plaintext in hand go
    /// straight to the confirmation; while locked, run the reveal ceremony
    /// first (the secret still gates the write-back) and confirm on success.
    private func requestRemoval() {
        if plaintext != nil {
            confirmRemoval = true
        } else {
            pendingRemoval = true
            primaryTap()
        }
    }

    /// A reveal that was started as a removal falls through to the confirmation.
    /// Slight delay so the prompt sheet finishes dismissing first — presenting a
    /// dialog while a sheet is mid-dismiss silently drops the dialog.
    private func finishPendingRemoval() {
        guard pendingRemoval else { return }
        pendingRemoval = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            confirmRemoval = true
        }
    }

    private func removeProtection() {
        guard let plaintext else { return }
        var updated = field
        updated.value = plaintext
        updated.guard2 = false
        onChange(updated)
    }
}
