import SwiftUI

/// Centered hero title + optional subtitle shared by every onboarding step.
/// Keeps the text inside the same content column as the step's field/button
/// (`Space.s6`), wraps to two lines on narrow phones instead of touching the
/// bezels, and shrinks slightly only when large Dynamic Type would overflow.
struct OnboardingStepHeader: View {
    /// `hero` for airy steps with short titles; `compact` for content-heavy
    /// steps (Emergency Kit) where a large ramp would dominate the screen.
    enum Style { case hero, compact }

    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var style: Style = .hero

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, style: Style = .hero) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            Text(title)
                .vaultType(style == .hero ? .largeTitle : .screenTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .vaultType(style == .hero ? .body : .subhead)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s2)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
    }
}

/// Fills the screen and centers its content (via the caller's own `Spacer`s) when it
/// fits, but becomes a real `ScrollView` the moment large Dynamic Type or a short
/// screen (SE) would otherwise clip a fixed-height onboarding step. Every onboarding
/// step body should be wrapped in this instead of a bare `VStack` between two
/// unbounded `Spacer()`s, which clips silently at accessibility text sizes.
struct OnboardingScrollingStep<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    // Regular width (iPad/Mac): every onboarding and lock step
                    // reads as a centered form column instead of a layout
                    // stretched across the full 1,000+pt screen. No-op on iPhone.
                    .vaultContentWidth(.form)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
