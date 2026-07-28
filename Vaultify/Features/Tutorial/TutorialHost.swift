import SwiftUI

/// Bridges published anchors to the spotlight overlay: reads the frames the
/// screens below publish, resolves the current step's anchor into this view's
/// coordinate space, and hands the result to the pure overlay.
///
/// Applied once, high in the unlocked hierarchy — a tour can then highlight
/// anything on any tab without those screens knowing the tutorial exists
/// beyond the `tutorialAnchor` tag they publish.
struct TutorialHost: ViewModifier {
    let coordinator: TutorialCoordinator

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
                // One coordinate space for both the anchor resolution and the
                // drawing, extended under the safe area so the scrim reaches
                // the status bar and home indicator.
                GeometryReader { proxy in
                    if let step = coordinator.currentStep {
                        TutorialSpotlightOverlay(
                            spotlight: step.anchor
                                .flatMap { anchors[$0] }
                                .map { proxy[$0] },
                            shape: step.shape,
                            tooltip: TutorialTooltipContent(
                                stepLabel: coordinator.stepLabel,
                                title: String(localized: step.title.inAppLocalized),
                                message: String(localized: step.message.inAppLocalized),
                                primaryTitle: coordinator.isLastStep
                                    ? appString("Done") : appString("Next"),
                                skipTitle: coordinator.isLastStep ? nil : appString("Skip")),
                            allowsInteractionInSpotlight: step.awaitsRealTap,
                            onNext: { coordinator.advance() },
                            onSkip: { coordinator.skip() })
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    /// Host tutorial overlays for everything below this point.
    func tutorialHost(_ coordinator: TutorialCoordinator) -> some View {
        modifier(TutorialHost(coordinator: coordinator))
    }
}
