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
        .padding(.top, Space.gutter)
    }
}
