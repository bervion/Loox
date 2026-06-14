import SwiftUI

/// Set or change the app-wide Level-2 ("extra protection") password — a second
/// password that gates the most sensitive fields (recovery codes, files…).
struct Level2SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var hasLevel2: Bool { env.session.hasLevel2 }
    private var canSubmit: Bool {
        newPassword.count >= 6 && newPassword == confirm && (!hasLevel2 || !current.isEmpty) && !busy
    }

    var body: some View {
        Form {
            Section {
                Label {
                    Text("A second password for your most sensitive fields. Items can use this or their own code. If you forget it, those fields cannot be recovered.")
                        .font(.footnote).themedForeground(.secondary)
                } icon: {
                    PolarisIcon(Icons.lockFill).foregroundStyle(Color.accentColor)
                }
            }
            .listRowBackground(VaultColors.surface)

            if hasLevel2 {
                Section("Current password") {
                    RevealableSecureField(title: "Current extra password", text: $current).listRowInsets(.init())
                }
                .listRowBackground(VaultColors.surface)
            }

            Section(hasLevel2 ? "New password" : "Set password") {
                RevealableSecureField(title: "Extra password", text: $newPassword).listRowInsets(.init())
                PasswordStrengthMeter(password: newPassword)
                RevealableSecureField(title: "Confirm", text: $confirm).listRowInsets(.init())
            }
            .listRowBackground(VaultColors.surface)

            if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
        }
        .themedFormBackground()
        .navigationTitle("Extra Protection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(hasLevel2 ? "Change" : "Set") { Task { await submit() } }.disabled(!canSubmit)
            }
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    private func submit() async {
        busy = true; error = nil
        do {
            if hasLevel2 {
                try await env.session.changeLevel2Password(current: current, new: newPassword)
            } else {
                try await env.session.setLevel2Password(newPassword)
            }
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}
