import SwiftUI

/// The expandable sibling of `VaultInfoBanner`: a tinted notice that shows only its
/// title until tapped, then reveals the explanation and its single action.
///
/// Use it where a notice must be honest about a problem without shouting over the
/// screen's protagonist — an item's password warnings on the detail screen state the
/// most severe one in a line, and the sentences plus the fix stay one tap away.
/// Anything that needs no disclosure stays a plain `VaultInfoBanner`.
///
/// Severity comes from `VaultInfoBanner.Variant`, but the SURFACE differs on
/// purpose: this banner paints the severity hue solid and puts its copy in the
/// WCAG-derived on-color (`onFill`), the way 1Password states a credential
/// problem. The soft-tint treatment washed out against a white card — a warning
/// the eye slides past is a warning that does not work. `VaultInfoBanner` keeps
/// the soft fill for notices that sit inside forms and lists.
///
/// The `detail` slot is a view builder because a banner may speak for several
/// findings at once; the component styles the slot (footnote, on-fill color) so
/// callers supply structure, never fonts or colors.
struct VaultExpandableBanner<Detail: View>: View {
    private let variant: VaultInfoBanner.Variant
    /// Polaris glyph shown trailing the title; defaults to the variant's own.
    private let icon: String?
    private let title: LocalizedStringResource
    /// How many findings this banner speaks for. Rendered beside the title when
    /// greater than 1, so a collapsed banner never hides that there is more.
    private let count: Int
    private let actionLabel: LocalizedStringResource?
    private let action: (() -> Void)?
    private let detail: Detail

    /// Collapsed by default: the title alone carries the warning, and a detail
    /// screen that opens with an unfolded banner reads as an interruption.
    @State private var expanded = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width of the disclosure chevron column. The expanded copy indents by this
    /// plus the header spacing so it lines up under the title, not under the chevron.
    private let chevronSize: CGFloat = 13

    init(_ variant: VaultInfoBanner.Variant,
         icon: String? = nil,
         title: LocalizedStringResource,
         count: Int = 1,
         actionLabel: LocalizedStringResource? = nil,
         action: (() -> Void)? = nil,
         @ViewBuilder detail: () -> Detail) {
        self.variant = variant
        self.icon = icon
        self.title = title
        self.count = count
        self.actionLabel = actionLabel
        self.action = action
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // Selection-class event: one tap, one light haptic (DNA vocabulary).
                Haptics.tap()
                expanded.toggle()
            } label: {
                headerRow
            }
            .buttonStyle(.plain)

            if expanded { expandedContent }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: variant.fill(env.theme.active)))
        .vaultCornerRadius(Radius.md)
        .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: expanded)
        .accessibilityElement(children: .contain)
    }

    /// Collapsed, this row IS the banner: one line of type at `Metric.hitMin`, so
    /// the notice reads as a bar above the content rather than a second card. The
    /// padding lives inside the button label, making the whole bar the tap target.
    private var headerRow: some View {
        HStack(spacing: Space.s3) {
            VaultIcon(Icons.chevronRight, size: chevronSize)
                .foregroundStyle(onFillColor)
                .rotationEffect(.degrees(expanded ? 90 : 0))
            Text(title)
                .vaultType(.subhead).fontWeight(.semibold)
                .foregroundStyle(onFillColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            if count > 1 {
                Text(verbatim: "\(count)")
                    .vaultType(.footnote).fontWeight(.semibold)
                    .foregroundStyle(onFillColor)
            }
            VaultIcon(icon ?? variant.defaultIcon, size: Metric.iconCompact)
                .foregroundStyle(onFillColor)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(minHeight: Metric.hitMin)
        .contentShape(Rectangle())
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityHint(Text(expanded ? "Hide details" : "Show details"))
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            detail
                .vaultType(.footnote)
                .foregroundStyle(onFillColor)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                // A filled pill on the severity hue: the label carries the
                // TEXT-rank status color (guarded for light surfaces), never the
                // raw fill hue, which measures too low on its own light chip.
                Button(action: action) {
                    Text(actionLabel)
                        .vaultType(.footnote).fontWeight(.semibold)
                        .foregroundStyle(tintColor)
                        .padding(.horizontal, Space.s3)
                        .frame(minHeight: Metric.controlSmall)
                        .background(Color(rgb: env.theme.active.background), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        // Indent past the chevron column so the sentences start under the title.
        .padding(.leading, chevronSize + Space.s3 + Space.s3)
        .padding(.trailing, Space.s3)
        .padding(.bottom, Space.s3)
        .transition(.opacity)
    }

    /// VoiceOver reads severity, then title, then how many findings are folded in;
    /// the expanded sentences are their own elements.
    private var headerAccessibilityLabel: Text {
        let label = Text(variant.severityLabel) + Text(verbatim: ", ") + Text(title)
        guard count > 1 else { return label }
        return label + Text(verbatim: ", ") + Text("^[\(count) issue](inflect: true) to review")
    }

    /// Copy and glyphs on the painted surface.
    private var onFillColor: Color { Color(rgb: variant.onFill(env.theme.active)) }

    /// TEXT-rank status color — only for the action pill, which sits on the plain
    /// background rather than the severity fill.
    private var tintColor: Color { variant.tintColor(env.theme.active) }
}

extension VaultExpandableBanner where Detail == Text {
    /// Single-sentence banner — the common case.
    init(_ variant: VaultInfoBanner.Variant,
         icon: String? = nil,
         title: LocalizedStringResource,
         detail: LocalizedStringResource,
         actionLabel: LocalizedStringResource? = nil,
         action: (() -> Void)? = nil) {
        self.init(variant, icon: icon, title: title,
                  actionLabel: actionLabel, action: action) {
            Text(detail)
        }
    }
}
