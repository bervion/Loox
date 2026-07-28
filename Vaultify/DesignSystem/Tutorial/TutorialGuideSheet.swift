import SwiftUI

/// A step-by-step guide sheet for things the user must do OUTSIDE this screen
/// — most often in iOS Settings, where a spotlight cannot follow them.
///
/// Instead of describing a control in prose, a step can embed the real row it
/// is talking about and draw an arrow to it, so the user recognizes the thing
/// on sight when they get there.
struct TutorialGuideSheet<Footer: View>: View {
    let title: LocalizedStringResource
    let intro: LocalizedStringResource?
    let steps: [TutorialGuideStep]
    /// Primary action area (usually "Open Settings" + a dismiss).
    @ViewBuilder let footer: () -> Footer

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                if let intro {
                    Text(intro.inAppLocalized)
                        .vaultType(.callout)
                        .themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index + 1, step: step)
                }
                footer()
            }
            .padding(Space.gutter)
        }
        .themedFormBackground()
        .navigationTitle(Text(title.inAppLocalized))
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    private func stepRow(index: Int, step: TutorialGuideStep) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            stepNumber(index)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(step.text.inAppLocalized)
                    .vaultType(.body)
                    .themedForeground()
                    .fixedSize(horizontal: false, vertical: true)
                if let preview = step.preview {
                    // The arrow points from the sentence into the row it names,
                    // so the two read as one instruction rather than a caption
                    // sitting above an unrelated screenshot.
                    HStack(alignment: .center, spacing: Space.s2) {
                        TutorialArrow()
                            .stroke(Color(rgb: theme.accent),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 34)
                            .accessibilityHidden(true)
                        preview
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func stepNumber(_ index: Int) -> some View {
        Text(verbatim: "\(index)")
            .vaultType(.subhead)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(theme.color(.onAccent))
            .frame(width: 26, height: 26)
            .background(Color(rgb: theme.accent), in: Circle())
            .accessibilityHidden(true)
    }
}

extension TutorialGuideSheet where Footer == EmptyView {
    init(title: LocalizedStringResource,
         intro: LocalizedStringResource? = nil,
         steps: [TutorialGuideStep]) {
        self.init(title: title, intro: intro, steps: steps) { EmptyView() }
    }
}

/// One instruction, optionally carrying the live view it refers to.
struct TutorialGuideStep {
    let text: LocalizedStringResource
    /// The real control (or a faithful stand-in for one that lives in another
    /// app) rendered inline and non-interactive.
    var preview: AnyView?

    init(_ text: LocalizedStringResource) {
        self.text = text
        self.preview = nil
    }

    init(_ text: LocalizedStringResource, @ViewBuilder preview: () -> some View) {
        self.text = text
        self.preview = AnyView(preview())
    }
}

/// Elbow arrow: down from the sentence, then right into the embedded row.
private struct TutorialArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let head: CGFloat = 6
        let turn = CGPoint(x: rect.minX + 3, y: rect.maxY - 8)
        path.move(to: CGPoint(x: turn.x, y: rect.minY))
        path.addLine(to: CGPoint(x: turn.x, y: turn.y - head))
        path.addQuadCurve(to: CGPoint(x: turn.x + head, y: turn.y),
                          control: CGPoint(x: turn.x, y: turn.y))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: turn.y))
        // Arrowhead
        path.move(to: CGPoint(x: rect.maxX - head * 2, y: turn.y - head))
        path.addLine(to: CGPoint(x: rect.maxX, y: turn.y))
        path.addLine(to: CGPoint(x: rect.maxX - head * 2, y: turn.y + head))
        return path
    }
}
