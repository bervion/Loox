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
    private var isPasskeyRequest: Bool {
        PasskeySlot.isPasskeySlot(pending.request.fieldId)
    }

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
        case .waitingForFreshWindow(let boundaryUnixMs, let periodSeconds):
            issuingView(boundaryUnixMs: boundaryUnixMs, periodSeconds: periodSeconds)
        case .issuing:
            progress("Sending the code…")
        case .finished(let decision):
            finished(decision)
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: Request details + actions

    /// Action hierarchy: Approve is the single filled primary (the expected
    /// path); Reject is the quiet secondary so it never competes.
    private var requestDetails: some View {
        VaultStatusScreen(
            icon: Icons.shield,
            title: isPasskeyRequest ? "Sign-in requested" : "Code requested",
            message: .key(requestExplanation),
            feature: { requestCodeCard },
            primary: .init(title: "Approve with Face ID") {
                Task { await ceremony.approve(pending) }
            },
            secondary: .init(title: "Reject") {
                Task { await ceremony.reject(pending) }
            })
    }

    /// Passkey vs code, named requester vs not — four separate sentences so
    /// each locale can put the name where its grammar wants it.
    private var requestExplanation: LocalizedStringKey {
        if isPasskeyRequest {
            if let requesterLabel {
                return "\(requesterLabel) is asking to sign in with the shared passkey for \(itemTitle)."
            }
            return "Someone you shared with is asking to sign in with the shared passkey for \(itemTitle)."
        }
        if let requesterLabel {
            return "\(requesterLabel) is asking for the current verification code for \(itemTitle)."
        }
        return "Someone you shared with is asking for the current verification code for \(itemTitle)."
    }

    /// Centred inside the left-aligned status layout on purpose: the digits are
    /// what both people hold side by side.
    private var requestCodeCard: some View {
        VStack(spacing: Space.s2) {
            Text("Request code")
                .vaultType(.sectionLabel).themedForeground(.secondary)
            Text(verbatim: requestCode)
                .font(.vaultCode(size: 24))
                .monospacedDigit()
                .themedForeground()
            Text("It should match the code on their screen.")
                .vaultType(.footnote).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    /// Design 9c: rather than send the current TOTP code (which may have
    /// only seconds left to live), `ApprovalCeremonyService` waits for the
    /// next fresh window before issuing — this view says so explicitly,
    /// with a live countdown to the boundary the ceremony is already timed
    /// against (no separate timer, just a display of the same boundary).
    private func issuingView(boundaryUnixMs: Int64, periodSeconds: UInt32) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingMs = max(0, boundaryUnixMs - Int64(context.date.timeIntervalSince1970 * 1000))
            let remainingSeconds = Int((remainingMs + 999) / 1000)
            let period = Int(periodSeconds)
            VaultStatusScreen(
                busySystemImage: "clock.badge.checkmark",
                title: "Preparing a fresh verification code…",
                message: .key(freshWindowExplanation(period: period)),
                busy: true,
                feature: {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(spacing: Space.s2) {
                            CountdownRing(remaining: min(remainingSeconds, period), period: period)
                            Text("New window in \(remainingSeconds)s")
                                .vaultType(.footnote).fontWeight(.semibold).themedForeground(.warning)
                        }
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .background(VaultColors.surface, in: Capsule())
                        Text("This sheet stays open while the code is being issued.")
                            .vaultType(.footnote).themedForeground(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                })
        }
    }

    private func freshWindowExplanation(period: Int) -> LocalizedStringKey {
        if let requesterLabel {
            return "Loox waits for the next \(period)-second window so \(requesterLabel) gets a full-life code. The old one is never sent."
        }
        return "Loox waits for the next \(period)-second window so they get a full-life code. The old one is never sent."
    }

    private func progress(_ message: LocalizedStringKey) -> some View {
        VaultStatusScreen(busySystemImage: "checkmark.shield", title: message, busy: true)
    }

    private func finished(_ decision: ApprovalDecision) -> some View {
        let approved = decision == .approved
        // What was approved decides the wording: a passkey request hands over a
        // single signed sign-in, never a code.
        let title: LocalizedStringKey = approved
            ? (isPasskeyRequest ? "Sign-in approved" : "Code sent")
            : "Request rejected"
        let approvedMessage: LocalizedStringKey = isPasskeyRequest
            ? "They can finish this one sign-in. The passkey itself never left your device."
            : "They received a one-time code. It expires with the current window. Nothing else was shared."
        return VaultStatusScreen(
            icon: approved ? Icons.shield : Icons.shieldAlert,
            tint: approved ? .success : .secondary,
            title: title,
            message: approved ? .key(approvedMessage) : nil,
            primary: .init(title: "Done") {
                onFinished()
                dismiss()
            })
        // The ceremony is over — a parked sheet only resurfaces stale UI
        // later, so close it by itself after the outcome is readable.
        .task {
            env.notificationHistory.log(
                decision == .approved ? .approvalApproved : .approvalRejected,
                label: requesterLabel.map { "\($0): \(itemTitle)" } ?? itemTitle)
            try? await Task.sleep(for: .seconds(1.5))
            onFinished()
            dismiss()
        }
    }

    private func failed(_ message: String) -> some View {
        // The service message is already localized, so it stays verbatim under
        // a titled headline instead of standing alone as grey body copy.
        VaultStatusScreen(icon: Icons.alert, tint: .destructive,
                          title: "Something went wrong",
                          message: .verbatim(message),
                          primary: .init(title: "Close") {
                              onFinished()
                              dismiss()
                          })
    }
}
