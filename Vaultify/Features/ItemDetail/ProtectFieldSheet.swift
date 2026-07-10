import SwiftUI

/// Seal a plaintext field under second-layer protection — using the app-wide
/// Level-2 password or a per-field custom code. Returns the sealed field.
struct ProtectFieldSheet: View {
    let field: DynamicField
    let onProtected: (DynamicField) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var scheme: SecretGuard.Scheme = .level2
    @State private var level2Password = ""
    @State private var customCode = ""
    @State private var confirmCode = ""
    @State private var busy = false
    @State private var error: String?

    private var hasLevel2: Bool { env.session.hasLevel2 }
    private var level2Unlocked: Bool { env.session.level2Key != nil }

    private var canProtect: Bool {
        if busy { return false }
        switch scheme {
        case .level2: return hasLevel2 && (level2Unlocked || !level2Password.isEmpty)
        case .custom: return customCode.count >= 4 && customCode == confirmCode
        }
    }

    var body: some View {
        VaultSheetScaffold(title: "Protect Field", trailing: {
            Button("Protect") { Task { await protect() } }.disabled(!canProtect)
        }) {
            Form {
                Picker("Protect with", selection: $scheme) {
                    Text("Extra Password").tag(SecretGuard.Scheme.level2)
                    Text("Custom code").tag(SecretGuard.Scheme.custom)
                }
                .pickerStyle(.segmented)

                if scheme == .level2 {
                    level2Section
                } else {
                    Section {
                        RevealableSecureField(title: "Code", text: $customCode).listRowInsets(.init())
                        RevealableSecureField(title: "Confirm code", text: $confirmCode).listRowInsets(.init())
                    } header: {
                        Text("Custom code")
                    } footer: {
                        Text("Only this code can reveal the field. If you forget it, the field cannot be recovered.")
                    }
                    .listRowBackground(VaultColors.surface)
                }

                if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    @ViewBuilder private var level2Section: some View {
        if !hasLevel2 {
            Section {
                Label {
                    Text("Set an Extra Protection password in Settings → Security first.")
                        .vaultType(.footnote).themedForeground(.secondary)
                } icon: { PolarisIcon(Icons.alert).foregroundStyle(VaultColors.strengthMedium) }
            }
            .listRowBackground(VaultColors.surface)
        } else if !level2Unlocked {
            Section {
                RevealableSecureField(title: "Extra password", text: $level2Password).listRowInsets(.init())
            } header: {
                Text("Extra password")
            } footer: {
                Text("Enter it once to unlock extra protection for this session.")
            }
            .listRowBackground(VaultColors.surface)
        } else {
            Section { Text("This field will be protected with your Extra Password.").vaultType(.footnote).themedForeground(.secondary) }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func protect() async {
        busy = true; error = nil
        do {
            let sealed: String
            switch scheme {
            case .level2:
                if !level2Unlocked { try await env.session.unlockLevel2(password: level2Password) }
                guard let key = env.session.level2Key else { throw AuthError.locked }
                sealed = try SecretGuard.sealLevel2(field.value, l2Key: key.bytes)
            case .custom:
                sealed = try await SecretGuard.sealCustom(field.value, code: customCode)
            }
            var updated = field
            updated.value = sealed
            updated.guard2 = true
            onProtected(updated)
            Haptics.success()
            dismiss()
        } catch {
            self.error = (error as? AuthError)?.errorDescription ?? "Couldn’t protect this field."
            Haptics.error()
        }
        busy = false
    }
}
