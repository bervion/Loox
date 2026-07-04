import SwiftUI

/// Trusted-device side of QR pairing: scan the code shown on the NEW device,
/// confirm, then HPKE-seal the Vault Key to the scanned ephemeral public key and
/// publish the hand-off (see `VaultKeyPairing` / `VaultKeyEscrowService`).
///
/// The camera scanner is iOS-only; on macOS this sheet directs the user to their
/// iPhone (pairing approval needs a camera — the Mac is usually the NEW device).
struct PairDeviceSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case scanning
        case confirm(qrPayload: String)
        case publishing
        case done
        case failed(String)
    }

    @State private var phase: Phase = .scanning

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pair New Device")
                .platformNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .scanning:
            #if os(iOS)
            ZStack(alignment: .bottom) {
                QRScannerView { code in
                    guard case .scanning = phase else { return }
                    phase = .confirm(qrPayload: code)
                }
                .ignoresSafeArea(edges: .bottom)
                Text("Scan the QR code shown on your new device.")
                    .vaultType(.subhead)
                    .foregroundStyle(.white)
                    .padding(Space.s4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, Space.s7)
            }
            .background(.black)
            #else
            statusLayout(icon: Icons.scanCode, tint: VaultColors.accent,
                         title: "Scan on iPhone",
                         detail: "Open Loox on your iPhone (Settings → iCloud Sync → Pair New Device) to scan the new device’s code.")
            #endif
        case .confirm(let qrPayload):
            confirmView(qrPayload: qrPayload)
        case .publishing:
            VStack(spacing: Space.s4) {
                ProgressView()
                Text("Sending encrypted key…").vaultType(.subhead).themedForeground(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            statusLayout(icon: Icons.checkCircle, tint: VaultColors.strengthStrong,
                         title: "Device Paired",
                         detail: "Continue on your new device — it will finish setting up and download your vault.")
        case .failed(let message):
            VStack(spacing: Space.s4) {
                PolarisIcon(Icons.shieldAlert, size: 48).foregroundStyle(VaultColors.strengthWeak)
                Text(message)
                    .vaultType(.subhead).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                Button { phase = .scanning } label: { Text("Try Again") }
                    .buttonStyle(.themedProminent)
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Explicit approval gate: sealing the Vault Key to a scanned key is the single
    /// most security-sensitive action in the app — never do it silently off a scan.
    private func confirmView(qrPayload: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.personLockFilled, size: 48).foregroundStyle(VaultColors.accent)
            Text("Add this device to your vault?")
                .vaultType(.screenTitle)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s5)
            Text("Your vault key will be sent end-to-end encrypted to the device showing this code. Only approve a device that belongs to you.")
                .vaultType(.subhead).themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s6)
            Spacer()
            VStack(spacing: Space.s3) {
                Button { approve(qrPayload: qrPayload) } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .controlSize(.large)
                Button { phase = .scanning } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
    }

    private func approve(qrPayload: String) {
        guard let vaultKey = env.session.vaultKey else {
            phase = .failed(appString("The vault is locked."))
            return
        }
        phase = .publishing
        Task {
            do {
                let request = try VaultKeyPairing.parse(qrPayload: qrPayload)
                var keyBytes = vaultKey.bytes
                defer { secureZero(&keyBytes) }
                let sealed = try VaultKeyPairing.seal(vaultKey: keyBytes, to: request)
                try await VaultKeyEscrowService()
                    .publishPairingHandoff(pairingId: request.pairingId, sealedVaultKey: sealed)
                phase = .done
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func statusLayout(icon: String, tint: Color,
                              title: LocalizedStringResource,
                              detail: LocalizedStringResource) -> some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(icon, size: 48).foregroundStyle(tint)
            Text(title.inAppLocalized).vaultType(.screenTitle)
            Text(detail.inAppLocalized)
                .vaultType(.subhead).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
