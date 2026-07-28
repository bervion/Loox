import SwiftUI

/// Bridges published anchors to the spotlight overlay: reads the frames the
/// screens below publish, resolves the current step's anchor into this view's
/// coordinate space, and hands the result to the pure overlay.
///
/// A sheet is its own presentation, so an overlay hosted at the root is drawn
/// BEHIND it. Any flow that runs inside a sheet therefore needs a host in that
/// sheet — and each host declares which flows it serves, so exactly one of them
/// ever draws.
struct TutorialHost: ViewModifier {
    let coordinator: TutorialCoordinator
    /// Flow ids this host is responsible for. `nil` means "anything that is not
    /// claimed by a nested host" — the root's role.
    let flowIDs: Set<String>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: TutorialStep? {
        guard let flow = coordinator.flow else { return nil }
        if let flowIDs, !flowIDs.contains(flow.id) { return nil }
        if flowIDs == nil, TutorialFlow.sheetHostedFlowIDs.contains(flow.id) { return nil }
        return coordinator.currentStep
    }

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
                // One coordinate space for both the anchor resolution and the
                // drawing, extended under the safe area so the scrim reaches
                // the status bar and home indicator.
                GeometryReader { proxy in
                    // The ZStack is what gives the overlay a stable slot to
                    // transition in and out of: without it the tour also
                    // VANISHES in one frame when it ends, which reads as a
                    // glitch right after the user taps Done.
                    ZStack {
                        if let step {
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
                                .transition(.opacity)
                        }
                    }
                    .animation(.vault(Motion.standard, reduceMotion: reduceMotion),
                               value: step != nil)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    /// Host tutorial overlays for everything below this point. Pass `flowIDs`
    /// inside a sheet to host only the flows that belong to it.
    func tutorialHost(_ coordinator: TutorialCoordinator, flowIDs: Set<String>? = nil) -> some View {
        modifier(TutorialHost(coordinator: coordinator, flowIDs: flowIDs))
    }
}
