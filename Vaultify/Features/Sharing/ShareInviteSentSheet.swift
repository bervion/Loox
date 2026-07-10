import SwiftUI

/// The calm "you don't have to wait here" card (design 10f) shown right
/// after an invite is created or accepted — replaces a bare spinner with
/// reassurance and a preview of where the pending state now lives (Home's
/// pending row). Presentation-only: `ShareAccessSheet` still owns polling
/// and the escape-hatch buttons (Nudge / Check Now) below this card.
struct ShareInviteSentSheet: View {
    let recipientLabel: String
    let itemTitle: String
    /// true once the recipient accepted the CKShare (their device is
    /// finishing setup) — swaps the reassurance copy and the status chip.
    let accepted: Bool

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: Space.s5) {
            ZStack {
                Circle()
                    .fill(Color(rgb: env.theme.active.successSoft))
                    .frame(width: 72, height: 72)
                PolarisIcon(Icons.checkCircle, size: 32).themedForeground(.success)
            }
            VStack(spacing: Space.s2) {
                Text("Invite sent to \(recipientLabel)")
                    .vaultType(.section).themedForeground()
                    .multilineTextAlignment(.center)
                if accepted {
                    Text("They've accepted. Their device finishes automatically the next time they open Loox and unlock. This can take a moment.")
                        .vaultType(.callout).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No need to wait here. They'll get a notification, and we'll ping you the moment they accept. You can track it anytime from Home.")
                        .vaultType(.callout).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            statusChip
        }
    }

    @ViewBuilder private var statusChip: some View {
        HStack(spacing: Space.s2) {
            StatusDot(kind: accepted ? .active : .pending, size: 7)
            if accepted {
                Text("Sharing \"\(itemTitle)\" is finishing on their device")
                    .vaultType(.footnote).themedForeground().lineLimit(1)
            } else {
                Text("Sharing \"\(itemTitle)\" is waiting for \(recipientLabel)")
                    .vaultType(.footnote).themedForeground().lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(VaultColors.surface, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
        )
    }
}
