import SwiftUI

/// Wraps the value-bearing section of a SHARED item detail. The content
/// closure is evaluated ONLY in the `.authorized` state — SwiftUI's lazy
/// `@ViewBuilder` means secrets never materialize into the render tree in
/// any other state (INV-01). Re-verifies on appear, on every reachability
/// flip, and whenever the scene becomes active again (the background-revoke
/// race lands in `.verifying`, never on stale values).
struct SharedAccessGateView<Content: View>: View {
    let itemID: String
    @ViewBuilder var content: () -> Content

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizer = SharedAccessAuthorizer()

    var body: some View {
        // Tier 0 outranks the whole gate: an unauthorized device never even
        // starts verification — there is nothing it could be authorized FOR.
        if env.sharedItems.item(id: itemID)?.sharedOrigin?.deviceAuthorized == false {
            stateCard(icon: Icons.personLockFilled, tint: .secondary,
                      message: "The owner limited this item to a different device.")
        } else {
            gateBody
        }
    }

    private var gateBody: some View {
        Group {
            switch authorizer.state {
            case .authorized:
                content()
            case .offline:
                // Design 9b: secrets stay sealed before this gate passes —
                // metadata (item title/type/sharer, rendered by the caller
                // above this view) is the only thing shown while offline.
                // Auto-recheck already happens via `gateKey` below (it
                // includes reachability); `Try Again` is the manual twin.
                VStack(spacing: Space.s2) {
                    VaultInfoBanner(.warning, icon: Icons.globe,
                                    title: "You're offline",
                                    text: "You need an internet connection to view this shared item. Its secrets stay sealed until access is verified.",
                                    actionLabel: "Try again") {
                        Task { await authorizer.refresh(itemID: itemID, env: env) }
                    }
                    Text("Re-checks automatically when the connection returns.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .multilineTextAlignment(.center)
                }
            case .verifying:
                VStack(spacing: Space.s3) {
                    ProgressView()
                    Text("Verifying access…")
                        .vaultType(.footnote).themedForeground(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Space.s6)
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.lg)
            case .unavailable:
                VStack(spacing: Space.s3) {
                    stateCard(icon: Icons.alert, tint: .warning,
                              message: "Couldn't verify access right now.")
                    Button {
                        Task { await authorizer.refresh(itemID: itemID, env: env) }
                    } label: {
                        Text("Try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                }
            case .revoked:
                stateCard(icon: Icons.shieldAlert, tint: .destructive,
                          message: "The owner has revoked access to this item.")
            }
        }
        // One task keyed on everything that must restart a gate pass; the
        // authorizer's run token discards results from superseded passes.
        .task(id: gateKey) {
            await authorizer.refresh(itemID: itemID, env: env)
        }
    }

    /// Reachability flip or scene reactivation restarts verification.
    private var gateKey: String {
        "\(env.reachability.hasSatisfiedNetworkPath)|\(scenePhase == .active)"
    }

    private func stateCard(icon: String, tint: ThemeRole,
                           message: LocalizedStringKey) -> some View {
        VStack(spacing: Space.s3) {
            PolarisIcon(icon, size: Metric.iconTile).themedForeground(tint)
            Text(message)
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s6)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.lg)
    }
}
