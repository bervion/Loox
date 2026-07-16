import SwiftUI

/// One tile of the Loox membership screen's feature grid (the iCloud+
/// "Saved to iCloud" tile idiom): leading icon tile, feature title, and a live
/// usage/status line. Either pushes a destination or performs an action
/// (e.g. switching to the Watchtower tab).
struct LooxFeatureTile<Destination: View>: View {
    @Environment(AppEnvironment.self) private var env
    let title: LocalizedStringResource
    let icon: String
    /// Pre-localized usage/status line (built by the screen from live counts).
    let metric: String
    private let destination: (() -> Destination)?
    private let action: (() -> Void)?

    init(title: LocalizedStringResource, icon: String, metric: String,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.metric = metric
        self.destination = destination
        self.action = nil
    }

    init(title: LocalizedStringResource, icon: String, metric: String,
         action: @escaping () -> Void) where Destination == EmptyView {
        self.title = title
        self.icon = icon
        self.metric = metric
        self.destination = nil
        self.action = action
    }

    var body: some View {
        if let destination {
            NavigationLink { destination() } label: { label }
                .buttonStyle(.plain)
        } else {
            Button { action?() } label: { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProfileRowTile(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .vaultType(.subhead)
                    .fontWeight(.semibold)
                    .themedForeground()
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(verbatim: metric)
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(Color(rgb: env.theme.active.elevatedBackground))
        .vaultCornerRadius(Radius.lg)
        .elevation(.level1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: metric))
    }
}
