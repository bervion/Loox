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
        Group {
            switch authorizer.state {
            case .authorized:
                content()
            case .offline:
                stateCard(icon: Icons.globe, tint: .warning,
                          message: "You need an internet connection to view this shared item.")
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
                        Text("Try Again").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
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
