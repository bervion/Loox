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
        .background(VaultScreenHeaderBackground())
    }
}

// MARK: - VaultScreenHeaderBackground

/// Blur surface behind the floating header. Extends up behind the status bar like a real
/// nav bar.
///
/// **iOS 26+ (Liquid Glass):** `glassEffect`, but **revealed only once content is actually
/// beneath the header** (`vaultHeaderScrolledUnder`). At rest the surface is `Color.clear`
/// — not a faded glass — so the screen background shows through with **zero band** (an
/// always-on glass renders a faint material band even over pure black on-device). The glass
/// is conditionally inserted, never given a static opacity (Apple forbids opacity on glass).
///
/// **Older OSes / Reduce Transparency:** a material reveal that mirrors the tab bar —
/// transparent at rest, cross-fading to `.regularMaterial` (or a solid `surfaceFloatingSolid`)
/// on the same `scrolledUnder` signal.
///
/// Either way the blur appears only when real content has scrolled up beneath the header
/// (threshold in `VaultHeaderScrollSpacer`), not on the first pixel of scroll.
private struct VaultScreenHeaderBackground: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.vaultHeaderScrolledUnder) private var scrolledUnder

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            glassReveal
        } else {
            materialReveal
        }
        #else
        materialReveal
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26, macOS 26, *)
    private var glassReveal: some View {
        ZStack {
            Color.clear
            if scrolledUnder {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: scrolledUnder)
    }
    #endif

    private var materialReveal: some View {
        let fill: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(Color(rgb: env.theme.active.surfaceFloatingSolid))
            : AnyShapeStyle(.regularMaterial)
        return Rectangle()
            .fill(fill)
            .opacity(scrolledUnder ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: scrolledUnder)
            .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Header scroll-edge plumbing

/// Whether tab-root scroll content has slid beneath the floating header. Drives the
/// header blur's reveal. Set per screen via `VaultHeaderScrollSpacer`; read by
/// `VaultScreenHeaderBackground`.
private struct VaultHeaderScrolledUnderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var vaultHeaderScrolledUnder: Bool {
        get { self[VaultHeaderScrolledUnderKey.self] }
        set { self[VaultHeaderScrolledUnderKey.self] = newValue }
    }
}

/// Top inset spacer for tab-root screens: clears the floating header height AND reports
/// when content scrolls beneath it. Use as the first child of the screen's `ScrollView`
/// (replaces the manual `Color.clear.frame(...)` spacer), then forward `scrolledUnder`
/// to the header via `.environment(\.vaultHeaderScrolledUnder, …)`.
struct VaultHeaderScrollSpacer: View {
    @Binding var scrolledUnder: Bool

    /// Breathing room between the header's visual bottom and the first content
    /// section. s6 keeps the screen airy without the ~90pt dead band the old s10
    /// left above the first card (user-flagged on the Items tab).
    private static let headerGap = Space.s6

    var body: some View {
        Color.clear
            .frame(height: Self.headerGap + Metric.hitMin)
            .background(
                GeometryReader { proxy in
                    // Reveal only once content has scrolled far enough to actually sit
                    // beneath the header — i.e. past the gap between where content starts
                    // (this spacer's full height) and the header's visual bottom edge.
                    // Gap = spacerHeight − headerHeight = headerGap − 2·Space.s2 (the
                    // shared Metric.hitMin cancels), so the blur doesn't trigger on the
                    // first pixel of scroll. (iOS 26 ignores this — native edge effect.)
                    Color.clear
                        .onChange(of: proxy.frame(in: .scrollView).minY < -(Self.headerGap - Space.s2 * 2)) { _, under in
                            scrolledUnder = under
                        }
                }
            )
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
///   - `#available(iOS 26, macOS 26, *)` ensures it only runs on the OS that ships the API
///   - `!reduceTransparency` honours the Accessibility setting
private struct HeaderGlassCapsule: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
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
            // Frame + contentShape live INSIDE the label so the whole 44pt
            // area is hit-testable, not just the 24pt glyph (SwiftUI only taps
            // the label's content shape, ignoring a frame applied to the Button).
            PolarisIcon(icon, size: Metric.iconUtility)
                .themedForeground(role)
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .contentShape(.rect)
        }
        // Explicit plain style: macOS's default bordered button style would wrap the
        // glyph in a gray push-button box (iOS's default is already borderless).
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
