import SwiftUI

/// Tinted inline banner for contextual notices. Neutral infrastructure states
/// stay on the accent tint (`.info`); `.warning` flags reversible risk;
/// `.danger` is reserved for destructive / security consequences.
/// Feature-specific banners (e.g. `CapabilityBannerView`) can keep their own
/// content logic and render through this surface.
struct VaultInfoBanner: View {
    enum Variant {
        case info, warning, danger
    }

    let variant: Variant
    /// Polaris asset name; defaults per variant.
    var icon: String?
    /// Optional bold first line.
    var title: LocalizedStringKey?
    let text: LocalizedStringKey
    /// Optional inline action rendered under the text (e.g. "Try Again").
    var actionLabel: LocalizedStringKey?
    var action: (() -> Void)?

    @Environment(AppEnvironment.self) private var env

    init(_ variant: Variant,
         icon: String? = nil,
         title: LocalizedStringKey? = nil,
         text: LocalizedStringKey,
         actionLabel: LocalizedStringKey? = nil,
         action: (() -> Void)? = nil) {
        self.variant = variant
        self.icon = icon
        self.title = title
        self.text = text
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        let theme = env.theme.active
        HStack(alignment: .top, spacing: Space.s3) {
            PolarisIcon(icon ?? defaultIcon, size: Metric.iconCompact)
                .foregroundStyle(theme.color(tintRole))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.s1) {
                if let title {
                    Text(title).vaultType(.subhead).fontWeight(.semibold)
                        .themedForeground(.primary)
                }
                Text(text)
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel).vaultType(.footnote).fontWeight(.semibold)
                            .foregroundStyle(theme.color(tintRole))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: softBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var tintRole: ThemeRole {
        switch variant {
        case .info: return .accent
        case .warning: return .warning
        case .danger: return .destructive
        }
    }

    private var softBackground: UInt32 {
        let theme = env.theme.active
        switch variant {
        case .info: return theme.accentSoft
        case .warning: return theme.warningSoft
        case .danger: return theme.destructiveSoft
        }
    }

    private var defaultIcon: String {
        switch variant {
        case .info: return Icons.info
        case .warning: return Icons.alert
        case .danger: return Icons.alert
        }
    }
}
