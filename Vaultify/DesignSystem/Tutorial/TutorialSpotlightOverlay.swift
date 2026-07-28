import SwiftUI

/// The visual half of the tutorial system: one scrim with a hole cut around
/// the current anchor, a tooltip card, and an optional arrow from the card to
/// the hole. Pure presentation — it owns no state, no persistence, and no
/// analytics; the app layer drives it.
///
/// One layer, one animation: the hole is a SINGLE rounded rectangle drawn with
/// `blendMode(.destinationOut)`, never four surrounding rectangles and never a
/// `Canvas`. A shape's frame, position and corner radius are all animatable, so
/// moving between steps morphs one shape — including between the three spotlight
/// shapes, which differ only in the radius this view hands the rectangle. A
/// `Canvas` would redraw each step instead, snapping the hole into place.
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

    /// False for the first frame only: the hole starts wider and closes onto the
    /// control, like a lens pulling focus, instead of the tour appearing fully
    /// formed between two frames.
    ///
    /// Only the CUT reads off this. Fading the tour in and out belongs to the
    /// host, which owns the overlay's appearance — and keeping opacity out of
    /// here is also what lets this view be rendered and asserted statically,
    /// where `onAppear` never runs and an opacity gate would leave a blank page.
    @State private var settled = false

    /// Breathing room between the highlighted control and the cut edge.
    private let padding: CGFloat = Space.s2
    /// How much wider the hole starts before it closes onto the control.
    private let introExpansion: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                scrim
                tooltipCard(in: proxy.size)
            }
            // `hole` folds in `settled`, so one spring covers both the entrance
            // and every later step move.
            .animation(.vault(Motion.spring, reduceMotion: reduceMotion), value: hole)
            // Anchorless flows never move the hole; their steps change only the
            // copy, which crossfades rather than cutting.
            .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: tooltip.title)
        }
        // No `ignoresSafeArea` here: the host's GeometryReader resolves anchors
        // in ITS space, and expanding only this view would shift every drawn
        // frame up by the top inset — the hole would miss what it highlights.
        // The host owns that decision so both spaces stay identical.
        .accessibilityAddTraits(.isModal)
        .onAppear { settled = true }
    }

    /// The hole as drawn: the anchor plus breathing room, expanded further for
    /// the first frame so the entrance closes IN on the control.
    private var hole: CGRect? {
        spotlight.map {
            TutorialSpotlightGeometry.hole(around: $0, shape: shape, padding: padding,
                                           expansion: settled ? 0 : introExpansion)
        }
    }

    /// Dimmed backdrop minus the spotlight. `compositingGroup` is required for
    /// `destinationOut` to erase within this layer instead of the whole window.
    private var scrim: some View {
        Rectangle()
            .fill(Color(rgb: theme.overlayDim).opacity(0.82))
            .overlay(alignment: .topLeading) { cutout }
            .compositingGroup()
            // The hit area carries the same hole when the step asks for a real
            // tap, so the control underneath stays reachable while every tap
            // outside it advances the tour.
            .contentShape(ScrimShape(hole: allowsInteractionInSpotlight ? hole : nil,
                                     cornerRadius: holeCornerRadius,
                                     cornerStyle: holeCornerStyle),
                          eoFill: true)
            .onTapGesture { onNext() }
    }

    @ViewBuilder private var cutout: some View {
        if let hole {
            RoundedRectangle(cornerRadius: holeCornerRadius, style: holeCornerStyle)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .blendMode(.destinationOut)
        }
    }

    private var holeCornerRadius: CGFloat {
        guard let hole else { return Radius.md }
        return TutorialSpotlightGeometry.cornerRadius(for: hole, shape: shape)
    }

    private var holeCornerStyle: RoundedCornerStyle {
        TutorialSpotlightGeometry.cornerStyle(for: shape)
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipCard(in size: CGSize) -> some View {
        let placement = TutorialTooltipPlacement.resolve(spotlight: hole, container: size)
        VStack(alignment: .leading, spacing: Space.s3) {
            if let step = tooltip.stepLabel {
                Text(step)
                    .vaultType(.caption)
                    .themedForeground(.tertiary)
                    .contentTransition(.opacity)
            }
            Text(tooltip.title)
                .vaultType(.headline)
                .themedForeground()
                .contentTransition(.opacity)
            Text(tooltip.message)
                .vaultType(.callout)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            HStack(spacing: Space.s3) {
                if let skipTitle = tooltip.skipTitle {
                    Button(action: onSkip) {
                        Text(verbatim: skipTitle)
                            .vaultType(.subhead)
                            // Leading-aligned so widening the target to 44pt
                            // grows it into the card, not away from the edge
                            // the copy above aligns to.
                            .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin,
                                   alignment: .leading)
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
                // The prominent style ends in `.frame(maxWidth: .infinity)` so a
                // screen primary can fill its slot. Here that made the pill and
                // the Spacer split the free space evenly, parking the button in
                // the middle of the row instead of against the card's edge.
                // `fixedSize` hands the style the hugging case it documents.
                .fixedSize()
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

/// Full-bleed rectangle with the spotlight subtracted, for hit testing under
/// `eoFill`. Only the drawing needs `destinationOut`; taps need a real shape.
private struct ScrimShape: Shape {
    let hole: CGRect?
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole {
            path.addPath(Path(roundedRect: hole, cornerRadius: cornerRadius, style: cornerStyle))
        }
        return path
    }
}

/// Pure geometry of the cut-out, kept out of the view so the shape rules can be
/// asserted without rendering: above all that a circular spotlight is cut from a
/// SQUARE. Cutting an ellipse from the control's own bounds is what made the
/// spotlight over the 260×218 vault-health ring read as a squashed oval.
enum TutorialSpotlightGeometry {
    /// The rect to cut, given the control's frame. `expansion` is the entrance
    /// offset: positive while the spotlight is still closing in on the control,
    /// zero once it has settled.
    static func hole(around anchor: CGRect, shape: TutorialSpotlightShape,
                     padding: CGFloat, expansion: CGFloat = 0) -> CGRect {
        let base = shape == .circle ? anchor.squaredAroundCenter : anchor
        let breathing = padding + expansion
        return base.insetBy(dx: -breathing, dy: -breathing)
    }

    /// All three spotlight shapes are the same rounded rectangle at a different
    /// radius, which is what lets one morph into another between steps. On the
    /// square a circle is cut from, half the side IS a circle.
    static func cornerRadius(for hole: CGRect, shape: TutorialSpotlightShape) -> CGFloat {
        switch shape {
        case .circle, .capsule: min(hole.width, hole.height) / 2
        case .rounded: Radius.md
        }
    }

    /// Apple's continuous curve is the house style for cards, but at a radius of
    /// half the side it draws a SQUIRCLE, with visible straight runs and seams
    /// where the curve meets them. A shape that is meant to read as a circle or
    /// a pill has to use the circular arc.
    static func cornerStyle(for shape: TutorialSpotlightShape) -> RoundedCornerStyle {
        switch shape {
        case .circle, .capsule: .circular
        case .rounded: .continuous
        }
    }
}

private extension CGRect {
    /// The smallest square that contains this rect, sharing its centre — the
    /// frame a circular spotlight is cut from.
    var squaredAroundCenter: CGRect {
        let side = Swift.max(width, height)
        return CGRect(x: midX - side / 2, y: midY - side / 2, width: side, height: side)
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
