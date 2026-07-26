import SwiftUI

/// One gray tile inside a Loox hub section card (the iCloud+ "Saved to iCloud"
/// tile idiom): a solid-tint icon badge, the feature title, and a short totals
/// line with an optional live service-status dot. Tiles sit INSIDE a white
/// section card, so they carry the fixed systemGray6-class fill themselves and
/// no elevation of their own. Either pushes a destination or performs an
/// action (e.g. switching to the Watchtower tab).
struct LooxFeatureTile<Destination: View>: View {
    @Environment(AppEnvironment.self) private var env
    let title: LocalizedStringResource
    let icon: String
    /// Solid badge tint (`SettingsBadgeTint` family) — the iCloud-style colored
    /// icon square. White-on-tint is the documented fixed-tile exemption class.
    let tint: Color
    /// Pre-localized usage/status line (built by the screen from live counts).
    let metric: String
    /// Live service dot for connected-service tiles; nil for local features.
    var status: CapabilityDisplayStatus? = nil
    private let destination: (() -> Destination)?
    private let action: (() -> Void)?

    init(title: LocalizedStringResource, icon: String, tint: Color, metric: String,
         status: CapabilityDisplayStatus? = nil,
         @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.metric = metric
        self.status = status
        self.destination = destination
        self.action = nil
    }

    init(title: LocalizedStringResource, icon: String, tint: Color, metric: String,
         status: CapabilityDisplayStatus? = nil,
         action: @escaping () -> Void) where Destination == EmptyView {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.metric = metric
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

    /// Badge column width — the metric line indents past it so it aligns with
    /// the TITLE, the iCloud+ tile anatomy (icon + title inline, value under
    /// the title, never a stacked icon-over-text pile). Computed because the
    /// generic type can't hold static storage.
    private var badgeWidth: CGFloat { 29 }

    private var label: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                SettingsIconBadge(icon: icon, tint: tint)
                // Long titles (VI "Gửi sang trình duyệt") WRAP at full size
                // instead of squeezing into a "…" line, and every tile sizes its
                // title block to the same TWO-line height (owner 260726: cards in
                // one grid must match) — the hidden two-line template sets the
                // height at the current Dynamic Type size, and the real title
                // centers inside it whether it takes one line or two.
                ZStack(alignment: .leading) {
                    Text(verbatim: " \n ")
                        .vaultType(.subhead)
                        .fontWeight(.semibold)
                        .hidden()
                    Text(title)
                        .vaultType(.subhead)
                        .fontWeight(.semibold)
                        .themedForeground()
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
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
            // The dot sits INSIDE the indent column so the metric text always
            // starts flush with the title — and keeps its full width (the dot
            // stealing text room truncated "0 trong 30 ngày").
            .padding(.leading, badgeWidth + Space.s2 - (status != nil ? 6 + Space.s2 : 0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(Self.tileFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValueText)
    }

    /// Fixed systemGray6-class inner-tile pair (iCloud+ storage cards) — the
    /// same documented fixed-tile class as the paywall's plan cards; a themed
    /// role would repaint the grid on accent changes.
    private static var tileFill: Color { VaultColors.dynamic(light: 0xF2F2F7, dark: 0x2C2C2E) }

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
/// reading a number. Used by the hub's Plan-limits row and the quota screen.
struct LooxQuotaBar: View {
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
        .accessibilityHidden(true)   // the row's text carries the numbers
    }

    private var fillColor: Color {
        let theme = env.theme.active
        if fraction >= 1 { return theme.color(.destructive) }
        if fraction >= 0.9 { return theme.color(.warning) }
        return theme.color(.accent)
    }
}
