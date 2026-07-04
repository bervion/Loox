import SwiftUI

/// First-run "set up from another device" flow: obtain the EXISTING vault's key —
/// by QR pairing (a trusted device scans this device's code and hands the key off
/// end-to-end encrypted) or by entering the Emergency-Kit recovery key against the
/// synced recovery envelope — then set a local master password and pull the vault.
///
/// No first-run seeding happens on this path (see `VaultSession.joinVault`).
struct JoinVaultFlow: View {
    @Environment(AppEnvironment.self) private var env
    let onCancel: () -> Void

    private enum Step: Equatable { case choice, qrPairing, recoveryEntry, password, biometric }

    @State private var step: Step = .choice
    /// The received Vault Key, held only between hand-off and `joinVault`. Kept as
    /// `SecureBytes` (mlocked, zeroed on deinit) — a raw array in `@State` would defeat
    /// zeroization via copy-on-write and could linger after an abandoned flow.
    @State private var receivedKey: SecureBytes?
    /// Set when the key came from the recovery path, so the same Emergency Kit
    /// keeps working on this device (re-wrapped locally).
    @State private var usedRecoveryKey: String?

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .choice:
                JoinMethodChoiceView(
                    onQR: { step = .qrPairing },
                    onRecovery: { step = .recoveryEntry },
                    onBack: onCancel)
            case .qrPairing:
                JoinByQRView(
                    onKey: { key in
                        adoptKey(key, recoveryKey: nil)
                    },
                    onBack: { step = .choice })
            case .recoveryEntry:
                JoinByRecoveryView(
                    onKey: { key, recoveryKey in
                        adoptKey(key, recoveryKey: recoveryKey)
                    },
                    onBack: { step = .choice })
            case .password:
                // Join-specific copy: the vault EXISTS and was just received — without
                // this context the reused creation screen reads like "pairing failed,
                // a brand-new vault is being made".
                CreateMasterPasswordView(
                    onSubmit: completeJoin,
                    title: "Vault received — protect this device",
                    subtitle: "Pairing succeeded. Now create a master password to unlock Loox on this device — it can match your other device or be different, and it never syncs.")
            case .biometric:
                EnableBiometricView(onEnable: enableBiometricAndFinish) { finish() }
            }
        }
        .animation(.smooth(duration: 0.35), value: step)
        // Backing out of the password step abandons the hand-off — drop the key
        // (SecureBytes deinit zeroes it) instead of leaving it parked in state.
        .onChange(of: step) { _, newStep in
            if newStep == .choice { clearReceivedKey() }
        }
    }

    /// Move the received key straight into zeroing storage and advance.
    private func adoptKey(_ key: [UInt8], recoveryKey: String?) {
        var bytes = key
        receivedKey = SecureBytes(bytes)
        secureZero(&bytes)
        usedRecoveryKey = recoveryKey
        step = .password
    }

    private func clearReceivedKey() {
        receivedKey = nil
        usedRecoveryKey = nil
    }

    /// Wrap the received key under the chosen local password, enable sync, and pull.
    private func completeJoin(_ password: String) async -> String? {
        guard let key = receivedKey else { return appString("Pairing failed — try again with a fresh QR code.") }
        do {
            // `.bytes` yields a fresh, uniquely-referenced copy → zeroing it works.
            var bytes = key.bytes
            defer { secureZero(&bytes) }
            try await env.session.joinVault(vaultKey: bytes, masterPassword: password,
                                            recoveryKey: usedRecoveryKey)
            clearReceivedKey()
            // Joining is an explicit iCloud action — turn sync on and start pulling
            // right away (the vault downloads while the user finishes the last step).
            env.settings.iCloudSyncEnabled = true
            env.syncNow()
            if BiometricAuth.isAvailable {
                step = .biometric
            } else {
                finish()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func enableBiometricAndFinish() {
        Task {
            try? await env.session.enableBiometricUnlock()
            finish()
        }
    }

    /// Leave onboarding — the unlocked app takes over (content arrives via sync).
    private func finish() {
        env.settings.onboardingCompleted = true
    }
}

// MARK: - Method choice

private struct JoinMethodChoiceView: View {
    let onQR: () -> Void
    let onRecovery: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s8)
            OnboardingStepHeader(
                "Set Up from Another Device",
                subtitle: "Restore your existing vault on this device.",
                style: .compact)

            VStack(spacing: Space.s3) {
                JoinOptionCard(icon: Icons.scanCode,
                               title: "Pair with QR Code",
                               detail: "Show a QR code here and approve it on a device that already has your vault.",
                               action: onQR)
                JoinOptionCard(icon: Icons.key,
                               title: "Use Recovery Key",
                               detail: "Enter the recovery key from your Emergency Kit.",
                               action: onRecovery)
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s6)

            Spacer()
            Button(action: onBack) {
                Text("Back").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
    }
}

private struct JoinOptionCard: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let action: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s4) {
                PolarisIcon(icon, size: Metric.iconUtility)
                    .foregroundStyle(VaultColors.accent)
                    .frame(width: Metric.controlLarge, height: Metric.controlLarge)
                    .background(Color(rgb: env.theme.active.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(title.inAppLocalized).vaultType(.callout).fontWeight(.semibold)
                        .themedForeground(.primary)
                    Text(detail.inAppLocalized).vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .elevation(.level2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QR pairing (new-device side)

private struct JoinByQRView: View {
    let onKey: ([UInt8]) -> Void
    let onBack: () -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var session = VaultKeyPairing.makeSession()
    @State private var errorMessage: String?
    @State private var waitTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s8)
            OnboardingStepHeader(
                "Pair with QR Code",
                subtitle: "On your other device, open Settings → iCloud Sync → Pair New Device, then scan this code.",
                style: .compact)

            QRCodeView(payload: session.qrPayload)
                .frame(maxWidth: 260)
                .padding(.top, Space.s6)

            Group {
                if let errorMessage {
                    Text(errorMessage)
                        .vaultType(.footnote)
                        .foregroundStyle(VaultColors.strengthWeak)
                        .multilineTextAlignment(.center)
                } else {
                    HStack(spacing: Space.s2) {
                        ProgressView()
                        Text("Waiting for your other device…")
                            .vaultType(.subhead).themedForeground(.secondary)
                    }
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s5)

            Spacer()
            VStack(spacing: Space.s3) {
                if errorMessage != nil {
                    Button {
                        // A fresh session (new ephemeral key + pairing id) — the old QR is dead.
                        session = VaultKeyPairing.makeSession()
                        errorMessage = nil
                        startWaiting()
                    } label: {
                        Text("Start Over").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .controlSize(.large)
                }
                Button(action: onBack) {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
        .onAppear(perform: startWaiting)
        .onDisappear { waitTask?.cancel() }
    }

    private func startWaiting() {
        waitTask?.cancel()
        let escrow = VaultKeyEscrowService()
        let current = session
        waitTask = Task {
            do {
                let sealed = try await escrow.waitForPairingHandoff(pairingId: current.pairingId)
                let key = try VaultKeyPairing.open(sealed, session: current)
                guard !Task.isCancelled else { return }
                onKey(key)
            } catch is CancellationError {
                // View dismissed — nothing to report.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Recovery key (Emergency-Kit side)

private struct JoinByRecoveryView: View {
    let onKey: ([UInt8], _ recoveryKey: String) -> Void
    let onBack: () -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var recoveryKey = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s8)
            OnboardingStepHeader(
                "Use Recovery Key",
                subtitle: "Enter the recovery key from your Emergency Kit. Your vault will download from iCloud.",
                style: .compact)

            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.key, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: env.theme.active.accent))
                    .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                    .background(Color(rgb: env.theme.active.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                    .font(recoveryKey.isEmpty ? .body : .vaultCode())
                    .platformAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Space.s3)
            .background(Color(rgb: env.theme.active.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .elevation(.level2)
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s6)

            if let errorMessage {
                Text(errorMessage)
                    .vaultType(.footnote)
                    .foregroundStyle(VaultColors.strengthWeak)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s4)
            }

            Spacer()
            VStack(spacing: Space.s3) {
                Button(action: submit) {
                    Group {
                        if busy { ProgressView() } else { Text("Continue") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .controlSize(.large)
                .disabled(recoveryKey.isEmpty || busy)

                Button(action: onBack) {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
    }

    private func submit() {
        busy = true
        errorMessage = nil
        let entered = recoveryKey
        Task {
            defer { busy = false }
            let envelope: (wrapped: Data, salt: Data, kdf: KdfParams)
            do {
                envelope = try await VaultKeyEscrowService().fetchRecoveryEnvelope()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            do {
                // Heavy Argon2 unwrap runs off-main (same helper the unlock path uses).
                // A GCM authentication failure here means the key was mistyped.
                let key = try await VaultSession.unwrap(
                    wrapped: envelope.wrapped,
                    password: RecoveryKey.normalize(entered),
                    salt: Array(envelope.salt),
                    params: envelope.kdf)
                onKey(key, entered)
            } catch {
                errorMessage = appString("That recovery key didn’t work.")
            }
        }
    }
}
