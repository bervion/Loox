import SwiftUI

/// One-time recipient-side trust interstitial: before FIRST use of a share's
/// content, the user either confirms the safety code matches the one on the
/// owner's device or explicitly chooses to proceed without checking. The
/// Keychain pin already froze the owner key at first sight (later changes
/// are rejected) — this sheet turns first sight from silent trust into a
/// recorded human decision. Dismissing decides nothing: the prompt returns
/// on the next use attempt.
struct SafetyCodeVerifySheet: View {
    let itemID: String
    /// Receives the terminal decision; the presenter persists it (and
    /// re-feeds the AutoFill cache) then dismisses.
    let onDecision: (OwnerKeyVerification) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var codeUnavailable = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                PolarisIcon(Icons.shield, size: Metric.iconTile)
                    .themedForeground(.accent)
                Text("Verify this share")
                    .vaultType(.section)
                    .themedForeground()
                Text("Ask the owner to open this item's sharing details and read their safety code. If both codes match, this share really came from them.")
                    .vaultType(.callout)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                codeCard
                VStack(spacing: Space.s3) {
                    Button {
                        Haptics.success()
                        onDecision(.confirmed)
                    } label: {
                        Text("The codes match").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    // Confirming requires having SEEN the code — while it is
                    // still loading (or unavailable) only the explicit skip
                    // and plain dismissal remain.
                    .disabled(code == nil)

                    Button {
                        onDecision(.skipped)
                    } label: {
                        Text("Use without verifying")
                            .vaultType(.callout)
                            .themedForeground(.secondary)
                            .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Text("If you skip this check, you cannot be sure who this share came from.")
                        .vaultType(.footnote)
                        .themedForeground(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Space.gutter)
            .padding(.top, Space.s5)
        }
        .platformPresentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: itemID) { await loadCode() }
    }

    @ViewBuilder private var codeCard: some View {
        Group {
            if let code {
                // Codes are a typographic object — same face and grouped
                // format as the owner's activation screen shows.
                Text(verbatim: code)
                    .font(.vaultCode(size: 28))
                    .monospacedDigit()
                    .themedForeground()
            } else if codeUnavailable {
                Text("The safety code isn't available right now. Try again later, or use the share without verifying.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, Space.s4)
        .padding(.horizontal, Space.s5)
        .frame(maxWidth: .infinity)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
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
