import SwiftUI

/// The visual half of the tutorial system: one scrim with a hole cut around
/// the current anchor, a tooltip card, and an optional arrow from the card to
/// the hole. Pure presentation — it owns no state, no persistence, and no
/// analytics; the app layer drives it.
///
/// One layer, one animation: the hole is drawn by a single `Canvas` using
/// `blendMode(.destinationOut)` rather than four surrounding rectangles, so
/// moving between steps morphs one shape instead of animating four edges.
struct TutorialSpotlightOverlay: View {
    /// Resolved frame of the step's anchor in this overlay's coordinate space.
    /// `nil` (anchor not on screen, or a step that deliberately has none)
    /// centers the tooltip and draws no hole.
    let spotlight: CGRect?
    let shape: TutorialSpotlightShape
    let tooltip: TutorialTooltipContent
    /// Taps inside the hole reach the app (the step asks the user to press the
    /// real control); taps elsewhere are swallowed by the scrim.
    let allowsInteractionInSpotlight: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Breathing room between the highlighted control and the cut edge.
    private let padding: CGFloat = Space.s2

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                scrim
                if let hole = paddedSpotlight, allowsInteractionInSpotlight {
                    // Punch a real hit-testing hole: the scrim above swallows
                    // everything, so the step's own control needs this window
                    // to stay tappable.
                    Color.clear
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)
                        .allowsHitTesting(false)
                }
                tooltipCard(in: proxy.size)
            }
            .animation(.vault(Motion.spring, reduceMotion: reduceMotion), value: spotlight)
        }
        // No `ignoresSafeArea` here: the host's GeometryReader resolves anchors
        // in ITS space, and expanding only this view would shift every drawn
        // frame up by the top inset — the hole would miss what it highlights.
        // The host owns that decision so both spaces stay identical.
        .accessibilityAddTraits(.isModal)
    }

    private var paddedSpotlight: CGRect? {
        spotlight?.insetBy(dx: -padding, dy: -padding)
    }

    /// Dimmed backdrop minus the spotlight. `compositingGroup` is required for
    /// `destinationOut` to erase within this layer instead of the whole window.
    private var scrim: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(rgb: theme.overlayDim).opacity(0.82)))
            if let hole = paddedSpotlight {
                context.blendMode = .destinationOut
                context.fill(path(for: hole), with: .color(.black))
            }
        }
        .compositingGroup()
        .contentShape(.rect)
        .onTapGesture { onNext() }
    }

    private func path(for rect: CGRect) -> Path {
        switch shape {
        case .capsule:
            Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous)
        case .rounded:
            Path(roundedRect: rect, cornerRadius: Radius.md, style: .continuous)
        case .circle:
            Path(ellipseIn: rect)
        }
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipCard(in size: CGSize) -> some View {
        let placement = TutorialTooltipPlacement.resolve(spotlight: paddedSpotlight,
                                                         container: size)
        VStack(alignment: .leading, spacing: Space.s3) {
            if let step = tooltip.stepLabel {
                Text(step)
                    .vaultType(.caption)
                    .themedForeground(.tertiary)
            }
            Text(tooltip.title)
                .vaultType(.headline)
                .themedForeground()
            Text(tooltip.message)
                .vaultType(.callout)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s3) {
                if let skipTitle = tooltip.skipTitle {
                    Button(action: onSkip) {
                        Text(verbatim: skipTitle)
                            .vaultType(.subhead)
                            .frame(minHeight: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .themedForeground(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onNext) {
                    Text(verbatim: tooltip.primaryTitle)
                        .frame(minWidth: 96)
                }
                .buttonStyle(.themedProminent)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: 340, alignment: .leading)
        .background(Color(rgb: theme.surfaceFloatingSolid),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level3)
        .padding(.horizontal, Space.gutter)
        .offset(x: 0, y: placement.offsetY(in: size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
        .accessibilityLabel(Text(tooltip.title))
    }
}

/// Cut shape around the highlighted control — matched to the control itself so
/// the hole reads as part of the UI, not a sticker on top of it.
enum TutorialSpotlightShape {
    case capsule
    case rounded
    case circle
}

/// Copy for one step's card. Every string arrives already resolved against the
/// IN-APP language — a `Text("…")` literal here would follow the device locale
/// and mix languages inside the card.
struct TutorialTooltipContent {
    var stepLabel: String?
    var title: String
    var message: String
    var primaryTitle: String
    /// Nil on the closing step, which has nothing left to skip.
    var skipTitle: String?
}

/// Keeps the card clear of the spotlight by measuring against the hole's own
/// edges, not a fraction of the screen: a card that covers the thing it is
/// describing is worse than no tour at all.
///
/// Anchored to the container edge nearest the free space (top when the card
/// goes below the hole, bottom when above) so the offset can be expressed
/// without knowing the card's own height, which SwiftUI resolves later.
enum TutorialTooltipPlacement {
    case below(holeBottom: CGFloat)
    case above(holeTop: CGFloat, containerHeight: CGFloat)
    case centered

    /// Breathing room between the hole edge and the card.
    private static let gap: CGFloat = Space.s5

    static func resolve(spotlight: CGRect?, container: CGSize) -> TutorialTooltipPlacement {
        guard let spotlight else { return .centered }
        // Put the card wherever there is more room, so a highlight near either
        // edge still gets a card fully on screen.
        let roomBelow = container.height - spotlight.maxY
        let roomAbove = spotlight.minY
        return roomBelow >= roomAbove
            ? .below(holeBottom: spotlight.maxY)
            : .above(holeTop: spotlight.minY, containerHeight: container.height)
    }

    var alignment: Alignment {
        switch self {
        case .below: .top
        case .above: .bottom
        case .centered: .center
        }
    }

    func offsetY(in size: CGSize) -> CGFloat {
        switch self {
        case .below(let holeBottom):
            holeBottom + Self.gap
        case .above(let holeTop, let containerHeight):
            -(containerHeight - holeTop + Self.gap)
        case .centered:
            0
        }
    }
}
