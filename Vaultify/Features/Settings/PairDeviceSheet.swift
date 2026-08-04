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
        // macOS-safe: own NavigationStack+toolbar Cancel could render unreliably on macOS
        // sheets (dismiss button could vanish) — use the shared scaffold instead.
        VaultSheetScaffold(title: "Pair New Device") {
            content
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
            VaultStatusScreen(icon: Icons.scanCode,
                              title: "Scan on iPhone",
                              message: .key("Open Loox on your other device (Settings → iCloud Sync → Pair New Device) to scan the new device’s code."))
            #endif
        case .confirm(let qrPayload):
            // Explicit approval gate: sealing the Vault Key to a scanned key is the
            // single most security-sensitive action in the app — never do it silently
            // off a scan. Cancel returns to the scanner so a mis-scan can be redone
            // without reopening the sheet.
            VaultStatusScreen(icon: Icons.personLockFilled,
                              title: "Add this device to your vault?",
                              message: .key("Your vault key will be sent end-to-end encrypted to the device showing this code. Only approve a device that belongs to you."),
                              primary: .init(title: "Approve") { approve(qrPayload: qrPayload) },
                              secondary: .init(title: "Cancel") { phase = .scanning })
        case .publishing:
            VaultStatusScreen(busySystemImage: "iphone.and.arrow.forward",
                              title: "Sending encrypted key…", busy: true)
        case .done:
            VaultStatusScreen(icon: Icons.checkCircle, tint: .success,
                              title: "Device Paired",
                              message: .key("Continue on your new device. It will finish setting up and download your vault."),
                              primary: .init(title: "Done") { dismiss() })
        case .failed(let message):
            // The service error is already localized at the throw site, so it rides
            // the verbatim slot rather than pretending to be a catalog key.
            VaultStatusScreen(icon: Icons.shieldAlert, tint: .destructive,
                              title: "Something went wrong",
                              message: .verbatim(message),
                              primary: .init(title: "Try again") { phase = .scanning })
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
}
