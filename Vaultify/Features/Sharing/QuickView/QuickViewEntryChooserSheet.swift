import SwiftUI

/// "Send to Browser" entry: Scan QR or Enter Code, then the approval sheet.
/// Both capture paths feed the SAME session client — only the input method
/// differs.
struct QuickViewEntryChooserSheet: View {
    let itemID: String
    let defaultSelectedFieldIDs: Set<String>

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showEnterCode = false
    @State private var flow: QuickViewApprovalFlowModel?

    private var flowPresented: Binding<Bool> {
        Binding(get: { flow != nil }, set: { if !$0 { flow = nil } })
    }

    var body: some View {
        VaultSheetScaffold(title: "Send to Browser") {
            Form {
                Section {
                    optionRow(icon: Icons.scanCode, title: "Scan QR Code",
                             subtitle: "Point your camera at the code shown in your browser.") {
                        showScanner = true
                    }
                    optionRow(icon: Icons.text, title: "Enter Code",
                             subtitle: "Type the code shown in your browser.") {
                        showEnterCode = true
                    }
                } footer: {
                    Text("You'll pick exactly what to share on the next screen.")
                }
                .listRowBackground(VaultColors.surface)
            }
        }
        // Full screen, not a sheet: a camera viewfinder inset in a card with the
        // parent showing behind it fights the one thing the screen is for, which
        // is aiming. Framing a code on a monitor needs the whole viewport.
        // `platformFullScreenCover`, not `fullScreenCover` — the latter does not
        // exist on macOS, where the helper falls back to a sheet.
        .platformFullScreenCover(isPresented: $showScanner) {
            QuickViewScannerSheet { code in startFlow(code: code) }
        }
        .sheet(isPresented: $showEnterCode) {
            QuickViewEnterCodeSheet { code in startFlow(code: code) }
        }
        .sheet(isPresented: flowPresented) {
            if let flow {
                QuickViewApprovalSheet(flow: flow) { dismiss() }
            }
        }
        // Best-effort background refresh — never blocks the sheet; a session
        // resolved before this completes just fails closed (generic error)
        // and the owner can retry, same silent-failure posture as the other
        // signed-document clients.
        .task { await env.quickViewSignerKeyset.refresh() }
        // Hosted here, not at the root: this is a sheet, and a root overlay
        // would be drawn behind it.
        .tutorialHost(env.tutorial, flowIDs: ["quick-view"])
        .task { env.tutorial.startIfNeeded(.quickView) }
        .onDisappear { env.tutorial.cancelPendingStart() }
    }

    private func startFlow(code: String) {
        let model = QuickViewApprovalFlowModel(
            itemID: itemID, defaultSelectedFieldIDs: defaultSelectedFieldIDs,
            vaultSession: env.session,
            repository: env.repository, history: env.quickViewHistory,
            capabilities: env.capabilities, signerKeyset: env.quickViewSignerKeyset)
        flow = model
        Task { await model.resolve(code: code) }
    }

    private func optionRow(icon: String, title: LocalizedStringResource,
                          subtitle: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                VaultIcon(icon, size: Metric.iconUtility).themedForeground(.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.inAppLocalized).vaultType(.headline).themedForeground()
                    Text(subtitle.inAppLocalized).vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VaultIcon(Icons.chevronRight, size: Metric.iconInline).themedForeground(.iconSecondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, Space.s1)
        }
        .buttonStyle(.plain)
    }
}
