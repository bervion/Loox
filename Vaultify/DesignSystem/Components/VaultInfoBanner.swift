import SwiftUI

/// The single tinted inline surface for contextual notices.
///
/// Severity vocabulary: `.info` is neutral context, `.warning` flags a degraded
/// or reversible state, `.error` marks a state the user has to resolve before
/// the feature works again.
///
/// Contrast contract (why body copy is PRIMARY rank, not secondary): measured
/// across the 4 themes x 7 accents, secondary text on the soft tint fills lands
/// between 1.77:1 (day / mono) and 8.04:1, failing the 4.5:1 floor on 22 of 28
/// accent combinations and the 3:1 large-text floor on 15 of them. Primary text
/// clears 4.5:1 on every combination (worst case 5.56:1, night-tinted / mono).
/// The leading glyph and the action label use the TEXT-rank status tokens
/// (`accentText` / `warningText` / `destructiveText`), never the FILL-rank hue,
/// which measures as low as 2.48:1 on its own soft fill.
///
/// Feature banners (e.g. `CapabilityBannerView`) keep their own content logic
/// and render through this surface rather than re-drawing the anatomy.
struct VaultInfoBanner: View {
    enum Variant {
        case info, warning, error
    }

    /// Banner copy: a catalog key (localized) or a runtime string (verbatim).
    private enum Copy {
        case key(LocalizedStringKey)
        case verbatim(String)

        var resolved: Text {
            switch self {
            case .key(let key): return Text(key)
            case .verbatim(let value): return Text(verbatim: value)
            }
        }
    }

    private let variant: Variant
    /// Polaris asset name; defaults per variant.
    private let icon: String?
    private let title: Copy?
    private let text: Copy
    private let actionLabel: LocalizedStringKey?
    private let action: (() -> Void)?

    @Environment(AppEnvironment.self) private var env

    /// Localized copy (the common case).
    init(_ variant: Variant,
         icon: String? = nil,
         title: LocalizedStringKey? = nil,
         text: LocalizedStringKey,
         actionLabel: LocalizedStringKey? = nil,
         action: (() -> Void)? = nil) {
        self.init(variant: variant, icon: icon,
                  titleCopy: title.map(Copy.key), textCopy: .key(text),
                  actionLabel: actionLabel, action: action)
    }

    /// Runtime body copy (a service error, a manifest-provided message) with an
    /// optional localized title. Deliberately a DIFFERENT argument label: with a
    /// shared `text:` label a plain string literal would resolve to `String` and
    /// silently skip the catalog.
    init(_ variant: Variant,
         icon: String? = nil,
         title: LocalizedStringKey? = nil,
         verbatimText: String,
         actionLabel: LocalizedStringKey? = nil,
         action: (() -> Void)? = nil) {
        self.init(variant: variant, icon: icon,
                  titleCopy: title.map(Copy.key), textCopy: .verbatim(verbatimText),
                  actionLabel: actionLabel, action: action)
    }

    /// Runtime title and body (both already localized by the caller).
    init(_ variant: Variant,
         icon: String? = nil,
         verbatimTitle: String,
         verbatimText: String,
         actionLabel: LocalizedStringKey? = nil,
         action: (() -> Void)? = nil) {
        self.init(variant: variant, icon: icon,
                  titleCopy: .verbatim(verbatimTitle), textCopy: .verbatim(verbatimText),
                  actionLabel: actionLabel, action: action)
    }

    private init(variant: Variant, icon: String?, titleCopy: Copy?, textCopy: Copy,
                 actionLabel: LocalizedStringKey?, action: (() -> Void)?) {
        self.variant = variant
        self.icon = icon
        self.title = titleCopy
        self.text = textCopy
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // 1pt optical nudge: the glyph's cap height sits above the first
            // text baseline without it (PolarisIcon is already a11y-hidden).
            PolarisIcon(icon ?? defaultIcon, size: Metric.iconCompact)
                .foregroundStyle(tintColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.s1) {
                copyStack
                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel)
                            .vaultType(.footnote).fontWeight(.semibold)
                            .foregroundStyle(tintColor)
                            .frame(minHeight: Metric.hitMin, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: softBackground))
        .vaultCornerRadius(Radius.md)
    }

    /// Title + body read as one VoiceOver element, prefixed with the severity
    /// the tint carries visually. The action button stays separately focusable.
    private var copyStack: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if let title {
                title.resolved
                    .vaultType(.subhead).fontWeight(.semibold)
                    .themedForeground(.primary)
            }
            text.resolved
                .vaultType(.footnote)
                .themedForeground(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var accessibilityCopy: Text {
        var label = Text(severityLabel)
        if let title { label = label + Text(verbatim: ", ") + title.resolved }
        return label + Text(verbatim: ", ") + text.resolved
    }

    private var severityLabel: LocalizedStringKey {
        switch variant {
        case .info: return "Information"
        case .warning: return "Warning"
        case .error: return "Important"
        }
    }

    /// TEXT-rank status color for the glyph and the action label.
    private var tintColor: Color {
        let theme = env.theme.active
        switch variant {
        case .info: return Color(rgb: theme.accentText)
        case .warning: return Color(rgb: theme.warningText)
        case .error: return Color(rgb: theme.destructiveText)
        }
    }

    private var softBackground: UInt32 {
        let theme = env.theme.active
        switch variant {
        case .info: return theme.accentSoft
        case .warning: return theme.warningSoft
        case .error: return theme.destructiveSoft
        }
    }

    private var defaultIcon: String {
        switch variant {
        case .info: return Icons.info
        case .warning: return Icons.alert
        case .error: return Icons.closeCircle
        }
    }
}

extension VaultInfoBanner {
    /// Drop the banner into a `List` / `Form` section: the banner already draws
    /// its own padding and tint, so the row contributes neither inset nor card
    /// background (without the clear background the tint sits on a card).
    func inList() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}
