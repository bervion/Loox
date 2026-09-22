import SwiftUI

/// The single tinted inline surface for contextual notices.
///
/// Severity vocabulary: `.info` is neutral context, `.warning` flags a degraded
/// or reversible state, `.error` marks a state the user has to resolve before
/// the feature works again.
///
/// The surface PAINTS the severity hue solid and sets its copy in the
/// WCAG-derived on-color (`onFill`), matching its expandable sibling
/// (`VaultExpandableBanner`, the item detail's password warnings) — one banner
/// language everywhere. The earlier soft-tint treatment washed out against a
/// white card, and a notice the eye slides past is a notice that does not work.
/// `fill` darkens each hue just enough for the on-color to clear 4.5:1 (body
/// sentences, not a button label), so the pairing holds on every theme.
///
/// `.subtle()` opts contextual notices into semantic soft surfaces with dark/light
/// text and modest corners; solid severity banners remain the default.
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

    private var usesSubtleSurface = false
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

    /// Quiet notices use a soft surface and modest corners. Prominent warnings
    /// keep the existing solid treatment unless the caller opts in.
    func subtle() -> Self {
        var banner = self
        banner.usesSubtleSurface = true
        return banner
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // 1pt optical nudge: the glyph's cap height sits above the first
            // text baseline without it (VaultIcon is already a11y-hidden).
            VaultIcon(icon ?? defaultIcon, size: Metric.iconCompact)
                .foregroundStyle(usesSubtleSurface ? tintColor : onFillColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.s1) {
                copyStack
                if let actionLabel, let action {
                    // Same chip the expandable banner uses: filled with the
                    // plain background, label in the TEXT-rank status color —
                    // never the raw fill hue, which measures too low on its
                    // own light chip.
                    Button(action: action) {
                        Text(actionLabel)
                            .vaultType(.footnote).fontWeight(.semibold)
                            .foregroundStyle(tintColor)
                            .padding(.horizontal, Space.s4)
                            .frame(minHeight: usesSubtleSurface ? Metric.hitMin : Metric.controlSmall)
                            .background(Color(rgb: env.theme.active.background),
                                        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s1)
                }
            }
        }
        .padding(usesSubtleSurface ? Space.s4 : Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: usesSubtleSurface ? variant.subtleFill(env.theme.active) : variant.fill(env.theme.active)))
        .vaultCornerRadius(usesSubtleSurface ? Radius.sm : Radius.md)
    }

    /// Title + body read as one VoiceOver element, prefixed with the severity
    /// the tint carries visually. The action button stays separately focusable.
    private var copyStack: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if let title {
                title.resolved
                    .vaultType(.subhead).fontWeight(.semibold)
                    .foregroundStyle(onFillColor)
                    .fixedSize(horizontal: false, vertical: usesSubtleSurface)
            }
            text.resolved
                .vaultType(.footnote)
                .foregroundStyle(onFillColor)
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

    private var severityLabel: LocalizedStringKey { variant.severityLabel }

    /// TEXT-rank status color — only for the action chip, which sits on the
    /// plain background rather than the severity fill.
    private var tintColor: Color {
        usesSubtleSurface ? Color(rgb: variant.subtleTint(env.theme.active)) : variant.tintColor(env.theme.active)
    }

    /// Copy and glyphs on the painted surface.
    private var onFillColor: Color {
        let theme = env.theme.active
        return Color(rgb: usesSubtleSurface
                     ? RGBMath.ensureContrast(theme.primaryText, on: variant.subtleFill(theme), floor: 4.5)
                     : variant.onFill(theme))
    }

    private var defaultIcon: String { variant.defaultIcon }
}

// MARK: - Severity vocabulary

/// The severity → color/glyph/label mapping, shared with `VaultExpandableBanner`
/// so both banner shapes speak the same vocabulary (and the measured contrast
/// contract above holds for both).
extension VaultInfoBanner.Variant {
    /// Existing semantic surfaces: neutral context, amber prerequisite, red error.
    func subtleFill(_ theme: AppTheme) -> UInt32 {
        switch self {
        case .info: return theme.secondaryBackground
        case .warning: return theme.warningSoft
        case .error: return theme.destructiveSoft
        }
    }

    func subtleTint(_ theme: AppTheme) -> UInt32 {
        let hue: UInt32 = switch self {
        case .info: theme.accentText
        case .warning: theme.warningText
        case .error: theme.destructiveText
        }
        let onSurface = RGBMath.ensureContrast(hue, on: subtleFill(theme), floor: 4.5)
        return RGBMath.ensureContrast(onSurface, on: theme.background, floor: 4.5)
    }

    /// TEXT-rank status color for the glyph and the action label.
    func tintColor(_ theme: AppTheme) -> Color {
        switch self {
        case .info: return Color(rgb: theme.accentText)
        case .warning: return Color(rgb: theme.warningText)
        case .error: return Color(rgb: theme.destructiveText)
        }
    }

    /// FILL-rank severity surface: both banner shapes PAINT the whole surface
    /// with this hue. Pair only with `onFill`.
    ///
    /// Darkened by the minimum that lets white clear **4.5:1**, not the 3:1 a
    /// filled control gets: a banner carries sentences, not a two-word button
    /// label. The raw Day red (`#E5484D`) measures 3.91 against white, which is
    /// why the tinted version read washed out and the plain one would read thin.
    /// The budget matters as much as the floor — a genuinely light hue (dark-mode
    /// yellow, the mono accent) exceeds it, keeps its color, and pairs with the
    /// dark on-color rather than losing its identity.
    func fill(_ theme: AppTheme) -> UInt32 {
        let hue: UInt32 = switch self {
        case .info: theme.accentFill
        case .warning: theme.warning
        case .error: theme.destructive
        }
        return RGBMath.controlFill(hue, floor: 4.5, maxDarken: 0.25)
    }

    /// Copy and glyph color on `fill`: white wherever it clears the control floor
    /// (the iOS convention this banner is styled after), black on the light hues
    /// where white would be unreadable. Derived per theme, never hardcoded.
    func onFill(_ theme: AppTheme) -> UInt32 { RGBMath.onAccent(fill(theme)) }

    /// Surface for a quiet secondary chip sitting ON `fill` (the banner's Ignore).
    ///
    /// Stepped AWAY from the on-color, not toward it: lightening a red fill under
    /// white text is the obvious-looking choice and measures 3.48:1, under the floor
    /// its label needs. Deepening keeps the same chip legible at 6.2:1 — and it is
    /// the idiom the tokens already use for `accentPress`.
    func fillQuiet(_ theme: AppTheme) -> UInt32 {
        let away: UInt32 = onFill(theme) == 0xFFFFFF ? 0x000000 : 0xFFFFFF
        return RGBMath.blend(fill(theme), away, 0.18)
    }

    var defaultIcon: String {
        switch self {
        case .info: return Icons.info
        case .warning: return Icons.alert
        case .error: return Icons.closeCircle
        }
    }

    /// Prefix VoiceOver reads before the copy, since the tint alone carries
    /// severity visually.
    var severityLabel: LocalizedStringKey {
        switch self {
        case .info: return "Information"
        case .warning: return "Warning"
        case .error: return "Important"
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
