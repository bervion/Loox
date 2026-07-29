import CloudKit
import Combine
import SwiftUI

/// The recipient's ask-and-wait state machine for one `askEachTime` TOTP
/// capability (Phase 6 + ADR-6 gate conditions 3/4):
///
///   IDLE → REQUESTING → WAITING_FOR_OWNER → APPROVED | REJECTED |
///                                           INTERRUPTED | EXPIRED | SUPERSEDED
///
/// Superseding is structural: "Request Again" drops the old request's
/// in-memory ephemeral private key and polls only the NEW requestId — a late
/// response to the old request is both undecryptable (key gone) and never
/// fetched (wrong id). Two live codes are impossible by construction.
/// The countdown is ADVISORY (owner window context, ADR-7); the relying
/// party's clock is the final authority.
@MainActor @Observable final class RequestCodeModel {
    enum Phase: Equatable {
        case idle
        case requesting
        case waiting(sinceUnixMs: Int64, showSlowHint: Bool)
        case approved(code: String, periodEndUnixMs: Int64)
        case rejected
        case interrupted
        case expired
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let service: ApprovalRecipientService
    private let grant: AccessGrant
    private let fieldId: String
    private let zoneID: CKRecordZone.ID
    private var pending: ApprovalRecipientService.PendingRequest?
    private let policy = TOTPIssuancePolicy.v1

    init(service: ApprovalRecipientService, grant: AccessGrant, fieldId: String,
         zoneID: CKRecordZone.ID) {
        self.service = service
        self.grant = grant
        self.fieldId = fieldId
        self.zoneID = zoneID
    }

    private var nowUnixMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// The 5-digit match code the owner's sheet also shows.
    var requestMatchCode: String? {
        guard let pending else { return nil }
        return TrustFingerprint.requestCode(requestId: pending.request.requestId,
                                            nonce: pending.request.nonce)
    }

    func sendRequest(deviceId: String) async {
        guard phase != .requesting else { return }
        // Supersede any previous ask: drop its ephemeral key BEFORE the new
        // request exists — the old response becomes permanently unopenable.
        pending = nil
        phase = .requesting
        do {
            pending = try await service.sendRequest(grant: grant, fieldId: fieldId,
                                                    deviceId: deviceId, zoneID: zoneID,
                                                    nowUnixMs: nowUnixMs)
            phase = .waiting(sinceUnixMs: nowUnixMs, showSlowHint: false)
        } catch {
            phase = .failed(SharingErrorMessage.text(for: error))
        }
    }

    /// Poll + lifecycle tick — runs while `.waiting` (driven by the view's
    /// `.task(id:)` plus push-triggered refreshes).
    ///
    /// Supersede + cancellation discipline (ADR-6 gate conditions 3/4): every
    /// await is followed by a CURRENCY check — if "Request Again" replaced
    /// `self.pending` while we were suspended, the in-flight local copy (and
    /// any response it fetched) is dead and must never render or touch state.
    /// Cancellation errors are honored, never swallowed into a hot loop.
    func tickWhileWaiting() async {
        while case .waiting(let sinceMs, let slowHint) = phase {
            guard let pending else { return }
            let currentId = pending.request.requestId
            // Hard timeout: request lifetime is over → EXPIRED, fail closed.
            if nowUnixMs >= pending.request.expiresAtUnixMs {
                self.pending = nil
                phase = .expired
                return
            }
            // Fetch: only the CURRENT request's response is ever looked up;
            // verification (owner pin, signature, binding) is kernel-owned.
            do {
                let response = try await service.fetchResponse(requestId: currentId,
                                                               zoneID: zoneID)
                guard !Task.isCancelled,
                      self.pending?.request.requestId == currentId else { return }
                if let response {
                    handle(response, pending: pending)
                    return
                }
            } catch is CancellationError {
                return
            } catch let error as ApprovalRecipientService.Failure {
                // A verification failure is DETERMINISTIC — retrying the same
                // response forever would just spin silently. Surface it.
                if case .verifyFailed = error,
                   self.pending?.request.requestId == currentId {
                    self.pending = nil
                    phase = .failed(SharingErrorMessage.text(for: error))
                    return
                }
                // Other service failures (e.g. transient) fall through.
            } catch {
                // Transient (offline/rate limit) — fall through to the sleep.
            }
            // Past the response-time budget → offer Keep Waiting / Request Again.
            if !slowHint, nowUnixMs - sinceMs >= policy.responseTimeoutMs,
               self.pending?.request.requestId == currentId {
                phase = .waiting(sinceUnixMs: sinceMs, showSlowHint: true)
            }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return // cancelled — the .task(id:) driver owns restarts
            }
            guard self.pending?.request.requestId == currentId else { return }
        }
    }

    private func handle(_ response: ApprovalResponse,
                        pending: ApprovalRecipientService.PendingRequest) {
        switch response.decision {
        case .approved:
            do {
                let payload = try ApprovalRecipientService.openApprovedPayload(response,
                                                                               pending: pending)
                // Stale/late fail-closed: a code whose window already ended
                // must never render as usable.
                guard payload.periodEndUnixMs > nowUnixMs else {
                    self.pending = nil
                    phase = .expired
                    return
                }
                self.pending = nil // key consumed; response can't be re-opened
                phase = .approved(code: payload.code, periodEndUnixMs: payload.periodEndUnixMs)
            } catch {
                self.pending = nil
                phase = .failed(appString("The response couldn't be verified."))
            }
        case .rejected:
            self.pending = nil
            phase = .rejected
        case .interrupted:
            self.pending = nil
            phase = .interrupted
        }
    }

    /// Drop the ephemeral code the moment its window ends (never persisted).
    func expireDisplayedCode() {
        if case .approved = phase { phase = .expired }
    }

    func reset() {
        pending = nil
        phase = .idle
    }
}

/// UI for one shared TOTP field on the recipient side.
struct RequestCodeView: View {
    let model: RequestCodeModel
    /// Stable opaque id for this device (request metadata, not secret).
    let deviceId: String
    /// True while the share's safety-code decision is still pending. A
    /// request leaks intent to the zone owner, so composing one is blocked
    /// until the user confirms or explicitly skips verification — the
    /// detail screen already withholds this view while pending, but the
    /// send path enforces it independently so a layout change can never
    /// reopen the hole.
    var verificationPending: Bool = false
    /// Invoked instead of sending when `verificationPending` — presents
    /// the shared safety-code interstitial.
    var onVerificationRequired: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            switch model.phase {
            case .idle:
                requestButton(title: "Request Code")
            case .requesting:
                HStack(spacing: Space.s2) { ProgressView(); Text("Sending request…").themedForeground(.secondary) }
            case .waiting(_, let showSlowHint):
                waitingView(showSlowHint: showSlowHint)
            case .approved(let code, let periodEndUnixMs):
                ApprovedCodeView(code: code, periodEndUnixMs: periodEndUnixMs) {
                    model.expireDisplayedCode()
                }
            case .rejected:
                outcome("Request declined", icon: Icons.shieldAlert)
            case .interrupted:
                // The outcome line states what happened; what to do next is the
                // button's job, so the sentence never duplicates its label.
                outcome("Approval was interrupted", icon: Icons.info)
            case .expired:
                outcome("The code expired", icon: Icons.info)
            case .failed(let message):
                Text(verbatim: message).vaultType(.footnote).themedForeground(.destructive)
            }
            // A terminal state always offers a fresh ask.
            if isTerminal {
                requestButton(title: "Request Again")
            }
        }
        .task(id: taskKey) {
            if case .waiting = model.phase { await model.tickWhileWaiting() }
        }
    }

    private var isTerminal: Bool {
        switch model.phase {
        case .rejected, .interrupted, .expired, .failed: return true
        default: return false
        }
    }

    private var taskKey: String {
        if case .waiting = model.phase { return "waiting" }
        return "idle"
    }

    /// Single choke point for every "ask the owner" affordance.
    private func startRequest() {
        if verificationPending {
            onVerificationRequired()
        } else {
            Task { await model.sendRequest(deviceId: deviceId) }
        }
    }

    /// The one "ask the owner" affordance, in two ranks. It is the filled
    /// primary wherever nothing is pending (idle, every terminal outcome), and
    /// drops to the quiet rank while a request is still live — superseding an
    /// ask that may still land is an escape hatch, not the expected next step.
    @ViewBuilder
    private func requestButton(title: LocalizedStringKey, quiet: Bool = false) -> some View {
        let button = Button {
            startRequest()
        } label: {
            Label { Text(title) } icon: { VaultIcon(Icons.shield, size: Metric.iconInline) }
                .frame(maxWidth: .infinity)
        }
        if quiet {
            button.buttonStyle(.themedTinted)
        } else {
            button.buttonStyle(.themedProminent)
        }
    }

    private func waitingView(showSlowHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ProgressView()
                Text("Waiting for approval…").themedForeground(.secondary)
            }
            if let matchCode = model.requestMatchCode {
                Text("Match code: \(matchCode)")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .monospacedDigit()
            }
            if showSlowHint {
                Text("This is taking longer than usual.")
                    .vaultType(.footnote).themedForeground(.secondary)
                // Same builder, same choke point, same label as the terminal
                // ask: the slow hint offers ONE more attempt, not a second
                // parallel action competing with the one still in flight.
                requestButton(title: "Request Again", quiet: true)
            }
        }
    }

    private func outcome(_ text: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: Space.s2) {
            VaultIcon(icon, size: Metric.iconInline).themedForeground(.iconSecondary)
            Text(text).vaultType(.footnote).themedForeground(.secondary)
        }
    }
}

/// The delivered one-time code + ADVISORY countdown ("About Ns remaining" —
/// the RP's clock decides real validity). The code is dropped at window end.
private struct ApprovedCodeView: View {
    let code: String
    let periodEndUnixMs: Int64
    let onExpired: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var remainingSeconds: Int = 0
    @State private var copied = false
    @State private var showLargeType = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Same interaction language as the app's own TOTP rows: tap-to-copy
        // with the "Copied" flash, CountdownRing, and the "…" menu
        // (Copy / Large Type) — only the code's origin differs.
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                // Codes are a typographic object (design DNA #4), same face as
                // the app's own TOTP rows — not a raw system font.
                Text(verbatim: copied ? appString("Copied") : TOTPCodeView.format(code))
                    .font(.vaultCode(.title3, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .themedForeground(copied ? .accent : .primary)
                Spacer()
                CountdownRing(remaining: remainingSeconds, period: 30)
                Menu {
                    Button { copy() } label: { Label { Text("Copy") } icon: { VaultIcon(Icons.copy) } }
                    Button { showLargeType = true } label: { Label { Text("Large Type") } icon: { VaultIcon("ic_text") } }
                } label: {
                    VaultIcon("ic_menu_horizontal", size: 17)
                        .themedForeground(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(VaultColors.fill))
                        // Invisible padded hit area: the visual circle stays
                        // 30pt, the tappable region meets the 44pt minimum.
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            Text("Use it now. It expires with the current window.")
                .vaultType(.footnote).themedForeground(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture { copy() }
        .platformFullScreenCover(isPresented: $showLargeType) {
            LargeTypeView(text: code, totpSecret: nil, liveTOTPSecret: nil)
        }
        .onAppear { updateRemaining() }
        .onReceive(timer) { _ in updateRemaining() }
    }

    private func copy() {
        guard !copied else { return }
        env.clipboard.copy(code, label: appString("verification code"), sensitive: true)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    private func updateRemaining() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let remaining = max(0, periodEndUnixMs - nowMs)
        remainingSeconds = Int(remaining / 1000)
        if remaining <= 0 { onExpired() }
    }
}
