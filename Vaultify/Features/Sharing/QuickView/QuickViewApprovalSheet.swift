import SwiftUI

/// The authorization boundary: browser context line, SAS match/abort,
/// per-field toggles (owner-locked defaults), expiry countdown, and the
/// Face ID action. There is deliberately no "continue anyway" control for a
/// SAS mismatch — only abort.
struct QuickViewApprovalSheet: View {
    @Bindable var flow: QuickViewApprovalFlowModel
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var paywallContext: LooxPaywallContext?

    private var item: VaultItem? { env.repository.item(id: flow.itemID) }

    private var isBusy: Bool {
        if case .approving = flow.state { return true }
        if case .resolving = flow.state { return true }
        return false
    }

    /// Device-local approximation of the rolling 30-day successful-approval
    /// count — the backend counter is the enforcement authority once it exists.
    private var quickViewCompletions30d: Int {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 3600)
        return env.quickViewHistory.rows.filter { $0.result == .completed && $0.timestamp >= cutoff }.count
    }

    var body: some View {
        VaultSheetScaffold(title: "Send to Browser",
                           leading: { EmptyView() },
                           trailing: { if !isBusy { SheetDismissButton("Close") } }) {
            content
        }
        .interactiveDismissDisabled(isBusy)
    }

    @ViewBuilder private var content: some View {
        switch flow.state {
        case .idle:
            EmptyView()
        case .resolving:
            progress(appString("Connecting to your browser…"))
        case .verified(let session):
            if let item {
                approvalDetails(session: session, item: item)
            } else {
                failed(appString("Start again in the browser."))
            }
        case .approving:
            progress(appString("Sending fields to your browser…"))
        case .done:
            finished
        case .error(let message):
            failed(message)
        }
    }

    // MARK: - Verified: SAS + field toggles + Face ID

    private func approvalDetails(session: QuickViewApprovalFlowModel.VerifiedSession,
                                 item: VaultItem) -> some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                PolarisIcon("ic_globe", size: Metric.iconTileLarge).themedForeground(.accent)

                Text("A browser wants to view fields from \(item.title.isEmpty ? appString("this item") : item.title).")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)

                QuickViewApprovalFieldsSection(flow: flow, item: item, sas: session.sas,
                                               expiresAtUnixMs: session.expiresAtUnixMs)

                VStack(spacing: Space.s3) {
                    Button {
                        // Over-quota upsell gate (§5.3), pre-Face-ID so biometrics
                        // never run for an approval the plan wouldn't cover. Only
                        // successful approvals consume the rolling quota (§3.2).
                        if env.entitlements.purchasesEnabled,
                           case .needsUpgrade = LooxGate.canApproveQuickView(
                               tier: env.entitlements.tier, approvedIn30d: quickViewCompletions30d) {
                            paywallContext = .quickViewQuota
                        } else {
                            Task { await flow.approve() }
                        }
                    } label: {
                        Text("Approve with Face ID")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }

                    Button(role: .destructive) {
                        flow.abortSASMismatch()
                        dismiss()
                    } label: {
                        Text("They don't match")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(Space.gutter)
        }
    }

    // MARK: - Terminal states

    private func progress(_ message: String) -> some View {
        VStack(spacing: Space.s4) {
            ProgressView()
            Text(verbatim: message).vaultType(.callout).themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finished: some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.shield, size: Metric.iconTileLarge).themedForeground(.success)
            Text("Sent to your browser").vaultType(.section).themedForeground()
            Text("Only the fields you picked were shared, once.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onFinished()
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.alert, size: Metric.iconTile).themedForeground(.destructive)
            Text(verbatim: message).vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onFinished()
                dismiss()
            } label: {
                Text("Close").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
