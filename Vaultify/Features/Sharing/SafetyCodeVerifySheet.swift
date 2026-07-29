import SwiftUI

/// OPTIONAL out-of-band check on a received share, reachable on demand from
/// the item's safety-code card. It is never a gate: the share was already
/// agreed to at accept time, where the sender's CloudKit identity was on
/// screen, and the Keychain pin independently rejects any later owner-key
/// change. What this adds is the one property automation cannot — reading the
/// same code off the owner's own device excludes a key substituted in the
/// cloud itself.
///
/// The code is 17 characters nobody should retype, so it copies with one tap
/// and travels over whatever channel the two people already use.
///
/// Two audiences reach this sheet: someone curious about a share they already
/// use, where comparing upgrades the recorded decision, and someone holding a
/// share from before decisions were recorded, whose content stays out of
/// AutoFill until they either compare or say to use it as is.
struct SafetyCodeVerifySheet: View {
    let itemID: String
    /// Receives a decision; the presenter persists it (and re-feeds the
    /// AutoFill cache) then dismisses. Closing the sheet decides nothing.
    let onDecision: (OwnerKeyVerification) -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var code: String?
    @State private var codeUnavailable = false

    var body: some View {
        VaultStatusScreen(
            icon: Icons.shield,
            title: "Compare safety code",
            message: .key("Ask the owner to open this item's sharing details and read their safety code. If both codes match, this share really came from them."),
            feature: {
                SafetyCodeCard(code: code, unavailable: codeUnavailable, onCopy: copyCode)
            },
            primary: .init(title: "The codes match", enabled: code != nil) {
                onDecision(.confirmed)
            },
            secondary: skipAction)
        .platformPresentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: itemID) { await loadCode() }
    }

    /// The escape hatch exists only where something is actually held back;
    /// offering it on a share that already works would invent a choice with
    /// no consequence.
    private var skipAction: VaultStatusScreen<SafetyCodeCard>.Action? {
        guard env.sharedItems.verification(forItem: itemID) == .pending else { return nil }
        return .init(title: "Use without verifying") { onDecision(.skipped) }
    }

    private func copyCode() {
        guard let code else { return }
        // The haptic belongs to the copy and already fires inside
        // ClipboardService — a second one here would double-tap.
        env.clipboard.copy(code, label: appString("Safety code"), sensitive: false)
    }

    private func loadCode() async {
        guard let vaultKey = env.session.vaultKey?.bytes else {
            codeUnavailable = true
            return
        }
        code = await env.sharedItems.safetyCode(forItem: itemID, vaultKey: vaultKey)
        codeUnavailable = code == nil
    }
}

/// The code, centred inside the left-aligned status layout on purpose: it is
/// the object both people hold side by side. Copy sits with it rather than in
/// the action stack, because copying is not one of the two decisions.
struct SafetyCodeCard: View {
    let code: String?
    let unavailable: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: Space.s3) {
            if let code {
                Text(verbatim: code)
                    .font(.vaultCode(size: 28))
                    .monospacedDigit()
                    .themedForeground()
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button(action: onCopy) {
                    HStack(spacing: Space.s2) {
                        VaultIcon(Icons.copy, size: Metric.iconInline)
                        Text("Copy code").vaultType(.body).fontWeight(.medium)
                    }
                    .themedForeground(.accentText)
                    .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else if unavailable {
                Text("The safety code isn't available right now. Try again later.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }
}
