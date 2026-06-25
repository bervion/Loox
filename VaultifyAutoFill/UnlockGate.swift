import SwiftUI
import os

/// Diagnostic logger for the extension's biometric unlock attempt. Filter Console by subsystem
/// `com.bervion.vaultify.autofill`, category `biometric`. Non-sensitive markers only.
private let bioLog = Logger(subsystem: "com.bervion.vaultify.autofill", category: "biometric")

/// Shared unlock gate for every AutoFill flow (fill / save / one-time-code). Tries Face ID first
/// (shared keychain group, no Argon2); on any failure reveals the master-password form. Once the
/// Vault Key is in hand it renders `content(vaultKey)`. Hosts the NavigationStack + Cancel so each
/// flow only supplies its post-unlock content — removing the unlock duplication the three flows had.
struct UnlockGate<Content: View>: View {
    let title: LocalizedStringKey
    let onCancel: () -> Void
    @ViewBuilder let content: (_ vaultKey: [UInt8]) -> Content

    @State private var masterPassword = ""
    @State private var unlocking = false
    @State private var errorMessage: String?
    /// True while the initial Face ID attempt is in flight — shows a spinner instead of flashing
    /// the master-password form. Set false on any biometric failure or when not enrolled.
    @State private var biometricInProgress = true
    @State private var vaultKey: [UInt8]?

    var body: some View {
        NavigationStack {
            Group {
                if let vaultKey { content(vaultKey) }
                else if biometricInProgress {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { unlockForm }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
        .task { await attemptBiometricUnlock() }
    }

    private var unlockForm: some View {
        Form {
            Section {
                SecureField("Master password", text: $masterPassword)
                    .textContentType(.password).submitLabel(.go).onSubmit(unlockWithMaster)
            } header: {
                Text("Unlock your vault")
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button(action: unlockWithMaster) { HStack { Spacer(); Text("Unlock").bold(); Spacer() } }
                    .disabled(masterPassword.isEmpty || unlocking)
            }
        }
        .overlay { if unlocking { ProgressView().controlSize(.large) } }
        .disabled(unlocking)
    }

    /// Face ID unlock — no Argon2. Any failure (cancel, item-not-found, entitlement, biometrics
    /// changed) reveals the master-password form as a fallback.
    private func attemptBiometricUnlock() async {
        let enrolled = BiometricKeyStore.isEnrolled
        bioLog.log("attemptBiometricUnlock: isEnrolled(shared group)=\(enrolled, privacy: .public)")
        guard enrolled else { biometricInProgress = false; return }
        do {
            let key = try await BiometricKeyStore.retrieve(reason: appString("Unlock your vault"))
            bioLog.log("biometric retrieve OK — unlocking via Face ID")
            vaultKey = key
        } catch {
            bioLog.error("biometric retrieve FAILED: \(String(describing: error), privacy: .public) — fallback to master password")
            biometricInProgress = false
        }
    }

    private func unlockWithMaster() {
        guard !masterPassword.isEmpty else { return }
        unlocking = true; errorMessage = nil
        let password = masterPassword
        Task {
            do {
                vaultKey = try await Task.detached(priority: .userInitiated) {
                    try VaultReader.deriveVaultKey(masterPassword: password)
                }.value
            } catch VaultReader.Failure.wrongPassword {
                errorMessage = appString("Incorrect master password.")
            } catch {
                errorMessage = appString("Couldn’t unlock the vault.")
            }
            unlocking = false
        }
    }
}
