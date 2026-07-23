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
    /// Quota consumption 0…1 — renders the thin iCloud+-style bar. nil for
    /// tiles without a countable quota (Watchtower, pre-launch metrics).
    var progress: Double? = nil
    /// Live service dot for connected-service tiles; nil for local features.
    var status: CapabilityDisplayStatus? = nil
    private let destination: (() -> Destination)?
    private let action: (() -> Void)?

    init(title: LocalizedStringResource, icon: String, metric: String,
         progress: Double? = nil, status: CapabilityDisplayStatus? = nil,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.metric = metric
        self.progress = progress
        self.status = status
        self.destination = destination
        self.action = nil
    }

    init(title: LocalizedStringResource, icon: String, metric: String,
         progress: Double? = nil, status: CapabilityDisplayStatus? = nil,
         action: @escaping () -> Void) where Destination == EmptyView {
        self.title = title
        self.icon = icon
        self.metric = metric
        self.progress = progress
        self.status = status
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
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .vaultType(.subhead)
                    .fontWeight(.semibold)
                    .themedForeground()
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let progress {
                    TileQuotaBar(fraction: progress)
                }
                HStack(spacing: Space.s2) {
                    if let status {
                        CapabilityStatusDot(status: status)
                    }
                    Text(verbatim: metric)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
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
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: Text {
        if let status {
            return Text(verbatim: metric) + Text(verbatim: ", ") + Text(status.accessibilityLabel)
        }
        return Text(verbatim: metric)
    }
}

/// Thin quota bar in the iCloud+ storage idiom: a 4pt track with the used
/// fraction filled accent; the fill warms to warning near the cap and to
/// destructive when the quota is exhausted, so "almost out" is visible without
/// reading a number.
private struct TileQuotaBar: View {
    let fraction: Double
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(VaultColors.fill)
                if clamped > 0 {
                    Capsule()
                        .fill(fillColor)
                        // A sliver of usage stays visible: never thinner than the
                        // bar's own height, so "1 of 200" doesn't render as empty.
                        .frame(width: max(geometry.size.width * clamped, 4))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)   // the metric text carries the numbers
    }

    private var fillColor: Color {
        let theme = env.theme.active
        if fraction >= 1 { return theme.color(.destructive) }
        if fraction >= 0.9 { return theme.color(.warning) }
        return theme.color(.accent)
    }
}
