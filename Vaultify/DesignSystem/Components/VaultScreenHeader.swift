import SwiftUI

// MARK: - VaultScreenHeader

/// Floating screen header used by all tab-root screens (Home, Items, Watchtower).
///
/// Pattern — overlay on ZStack so glass blurs content scrolling beneath:
///
///     ZStack(alignment: .top) {
///         ScrollView { topInsetSpacer; content }
///         VaultScreenHeader("Title") { HeaderActionCluster { buttons } }
///     }
///
/// Two generics keep the type system happy while letting screens pass any custom
/// leading view (folder switcher) or a simple string title.
struct VaultScreenHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            leading
            Spacer(minLength: Space.s2)
            trailing
        }
        .frame(minHeight: Metric.hitMin)
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s2)
    }
}

// MARK: Convenience: plain title leading, custom trailing

extension VaultScreenHeader where Leading == AnyView {
    /// Convenience init: leading is a plain `.screenTitle` text label.
    init(_ title: LocalizedStringResource, @ViewBuilder trailing: () -> Trailing) {
        self.init(
            leading: {
                AnyView(
                    Text(title)
                        .vaultType(.screenTitle)
                        .themedForeground()
                        .lineLimit(1)
                )
            },
            trailing: trailing
        )
    }
}

// MARK: Convenience: plain title, no trailing

extension VaultScreenHeader where Leading == AnyView, Trailing == EmptyView {
    /// Convenience init: plain title, no trailing actions.
    init(_ title: LocalizedStringResource) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - HeaderActionCluster

/// The right-side glass action cluster for tab-root headers.
///
/// Wrap any combination of `Button`, `Menu`, or `HeaderIconButton` views inside this
/// container and they will appear in a floating Liquid-Glass capsule (iOS 26+) or a
/// regular-material capsule fallback.
///
/// Only the cluster receives the glass treatment — leading content (e.g. the Home
/// folder switcher) is intentionally left plain.
struct HeaderActionCluster<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .headerGlassCapsule()
    }
}

// MARK: - HeaderGlassCapsule modifier

/// Applies Liquid-Glass (iOS 26+) or a material/solid fallback to the receiver.
///
/// Guard strategy mirrors VaultTabBarBackground:
///   - `#if compiler(>=6.2)` keeps the `glassEffect` symbol hidden from pre-Xcode-26 CI
///   - `#available(iOS 26, *)` ensures it only runs on the OS that ships the API
///   - `!reduceTransparency` honours the Accessibility setting
private struct HeaderGlassCapsule: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let fill: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(Color(rgb: env.theme.active.surfaceFloatingSolid))
            : AnyShapeStyle(.regularMaterial)
        return content
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5))
            .elevation(.level2)
    }
}

extension View {
    /// Applies the floating glass-capsule style. Available to any view in this module.
    func headerGlassCapsule() -> some View { modifier(HeaderGlassCapsule()) }
}

// MARK: - HeaderIconButton

/// 44pt tappable icon button for use inside `HeaderActionCluster`.
///
/// Wraps a `PolarisIcon` in a fixed-frame button that satisfies WCAG 44pt minimum
/// touch target. Screens may also inline `Button/Menu` directly if they need a menu.
struct HeaderIconButton: View {
    let icon: String
    let role: ThemeRole
    let accessibilityLabel: LocalizedStringResource
    let action: () -> Void

    init(
        _ icon: String,
        role: ThemeRole = .iconPrimary,
        accessibilityLabel: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.role = role
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PolarisIcon(icon, size: Metric.iconUtility)
                .themedForeground(role)
        }
        .frame(width: Metric.hitMin, height: Metric.hitMin)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
