import SwiftUI

/// The owner-side approval sheet (ADR-1 ceremony surface). Shown ONLY for a
/// request that already passed display verification (pinned signature, grant,
/// lifetime — via `PreviewNonceStore`, which does NOT burn the nonce). The
/// authoritative verify + nonce burn happen inside Approve, after Face ID.
struct ApprovalRequestSheet: View {
    let pending: ApprovalCoordinator.PendingOwnerRequest
    /// Item title resolved by the presenter (repository lookup).
    let itemTitle: String
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var ceremony: ApprovalCeremonyService { env.approvalCeremony }

    /// Who is asking — the owner's device-local registry maps the request's
    /// zone back to the recipient email this share was created for.
    private var requesterLabel: String? {
        env.sharingStore.shares.first { $0.zoneName == pending.zoneName }?.recipientLabel
    }

    /// Same 5-digit code renders on the requester's waiting screen — the
    /// human check that THIS request is the one they actually sent.
    private var requestCode: String {
        TrustFingerprint.requestCode(requestId: pending.request.requestId,
                                     nonce: pending.request.nonce)
    }

    var body: some View {
        VaultSheetScaffold(title: "Approval Request",
                           leading: { EmptyView() },
                           trailing: {
            // No escape hatch while the ceremony runs — the wait is bounded
            // (< one TOTP period); closing mid-flight would either drop the
            // requester silently or issue a code headless. Backgrounding is
            // still covered by the abort path.
            if !isBusy { SheetDismissButton("Close") }
        }) {
            content
        }
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            // Fresh sheet → fresh state; never stomp a mid-flight ceremony.
            if !isBusy { ceremony.resetState() }
        }
        .onDisappear {
            // Belt-and-braces: if the sheet dies mid-ceremony anyway (parent
            // teardown, deep link), abort per ADR-6 — never continue headless.
            ceremony.abandonIfBusy(pending)
        }
    }

    private var isBusy: Bool {
        switch ceremony.state {
        case .authenticating, .waitingForFreshWindow, .issuing: return true
        default: return false
        }
    }

    @ViewBuilder private var content: some View {
        switch ceremony.state {
        case .idle:
            requestDetails
        case .authenticating:
            progress("Confirming it's you…")
        case .waitingForFreshWindow:
            progress("Preparing a fresh verification code…")
        case .issuing:
            progress("Sending the code…")
        case .finished(let decision):
            finished(decision)
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: Request details + actions

    private var requestDetails: some View {
        VStack(spacing: Space.s5) {
            PolarisIcon(Icons.shield, size: Metric.iconTileLarge)
                .themedForeground(.accent)
            VStack(spacing: Space.s2) {
                Text("Code requested")
                    .vaultType(.section).themedForeground()
                if let requesterLabel {
                    Text("\(requesterLabel) is asking for the current verification code for \(itemTitle).")
                        .vaultType(.callout).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Someone you shared with is asking for the current verification code for \(itemTitle).")
                        .vaultType(.callout).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            VStack(spacing: Space.s2) {
                Text("Request code")
                    .vaultType(.sectionLabel).themedForeground(.secondary)
                Text(verbatim: requestCode)
                    .font(.vaultCode(size: 24))
                    .monospacedDigit()
                    .themedForeground()
                Text("It should match the code on their screen.")
                    .vaultType(.footnote).themedForeground(.secondary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.md)

            VStack(spacing: Space.s3) {
                Button {
                    Task { await ceremony.approve(pending) }
                } label: {
                    Text("Approve with Face ID")
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
                .buttonStyle(.themedProminent)
                Button {
                    Task {
                        await ceremony.reject(pending)
                    }
                } label: {
                    Text("Reject")
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: Space.s4) {
            ProgressView()
            Text(message)
                .vaultType(.callout).themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finished(_ decision: ApprovalDecision) -> some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(decision == .approved ? Icons.shield : Icons.shieldAlert,
                        size: Metric.iconTileLarge)
                .themedForeground(decision == .approved ? .success : .secondary)
            Text(decision == .approved ? "Code sent" : "Request rejected")
                .vaultType(.section).themedForeground()
            if decision == .approved {
                Text("They received a one-time code. It expires with the current window — nothing else was shared.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onFinished()
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The ceremony is over — a parked sheet only resurfaces stale UI
        // later, so close it by itself after the outcome is readable.
        .task {
            env.notificationHistory.log(
                decision == .approved ? .approvalApproved : .approvalRejected,
                label: requesterLabel.map { "\($0) · \(itemTitle)" } ?? itemTitle)
            try? await Task.sleep(for: .seconds(1.5))
            onFinished()
            dismiss()
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.alert, size: Metric.iconTile)
                .themedForeground(.destructive)
            Text(verbatim: message)
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onFinished()
                dismiss()
            } label: {
                Text("Close").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
