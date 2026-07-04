import SwiftUI

/// Floating tab-bar surface, applied **directly to the bar content** (not a background
/// sublayer — that prevents `glassEffect` from rendering):
/// - **iOS 26+** (Xcode 26+/Swift ≥ 6.2, transparency allowed): real Apple **Liquid Glass**
///   via `glassEffect(.regular.interactive())` — glass that reacts to touch, with its own
///   floating shadow.
/// - **Else / Reduce Transparency:** `.regularMaterial` (or a solid `surfaceFloatingSolid`)
///   capsule + hairline border + soft `.elevation(.level3)` drop shadow.
///
/// `#if compiler(>=6.2)` keeps a pre-Xcode-26 CI runner from ever seeing the `glassEffect`
/// symbol, so the release build always compiles (deployment target is 17.6).
private struct VaultTabBarSurface: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TabBarMetric.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: shape)
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
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5))
            .elevation(.level3)
    }
}

private struct VaultTabSelectionSurface: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            content.glassEffect(
                .regular
                    .tint(Color(rgb: env.theme.active.accentSoft))
                    .interactive(),
                in: Circle()
            )
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.background(Color(rgb: env.theme.active.accentSoft), in: Circle())
    }
}

extension View {
    /// Render the receiver as the floating tab-bar surface (Liquid Glass on iOS 26+, else
    /// a material/solid capsule). Apply to the bar content itself.
    func vaultTabBarSurface() -> some View { modifier(VaultTabBarSurface()) }

    /// Render the selected tab indicator. On iOS 26+ this is Liquid Glass too; older
    /// OSes and Reduce Transparency use the solid accent-soft fallback.
    func vaultTabSelectionSurface() -> some View { modifier(VaultTabSelectionSurface()) }
}
