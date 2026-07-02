import SwiftUI

/// Centered hero title + optional subtitle shared by every onboarding step.
/// Keeps the text inside the same content column as the step's field/button
/// (`Space.s6`), wraps to two lines on narrow phones instead of touching the
/// bezels, and shrinks slightly only when large Dynamic Type would overflow.
struct OnboardingStepHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            Text(title)
                .vaultType(.largeTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .vaultType(.body)
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
