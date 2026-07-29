import SwiftUI

/// Compact strength read-out for a password row: the graded label plus a ring that fills with
/// the grade.
///
/// The ring carries the same information as the label, which is the point — the label is the
/// precise answer and the ring is the one you read at a glance, without stopping to parse a word.
/// Both come from `PasswordStrengthEngine`, the pattern-aware estimate, so this can never
/// disagree with the meter shown while the password is being created.
struct PasswordStrengthRing: View {
    let password: String
    /// True while the row paints its accent "Copied" flash, where the normal colours vanish.
    var onAccent: Bool = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var grade: PasswordGrade { PasswordStrengthEngine.evaluate(password).grade }

    private var tint: Color {
        onAccent ? env.theme.active.color(.onAccent) : VaultColors.strength(grade: grade)
    }
    private var labelColor: Color {
        onAccent ? VaultColors.copyFlashText.opacity(0.85) : env.theme.active.color(.secondary)
    }
    /// The unfilled remainder. Kept visible rather than transparent so the ring always reads as
    /// a gauge with a maximum, not as an arc of arbitrary length.
    private var trackColor: Color {
        onAccent ? env.theme.active.color(.onAccent).opacity(0.3) : Color.platformSystemGray5
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            Text(grade.title)
                .vaultType(.subhead)
                .foregroundStyle(labelColor)
                .lineLimit(1)
            ZStack {
                Circle().stroke(trackColor, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: grade.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    // From twelve o'clock, like every other progress ring in the app.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: grade)
        }
        // One label for both halves: VoiceOver should hear the verdict once, not a word
        // followed by an unexplained gauge.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(grade.title))
    }
}

/// Hairline rule separating a row's read-out from its actions, so the "•••" reads as a control
/// rather than as one more piece of the value beside it.
struct RowActionDivider: View {
    var onAccent: Bool = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Rectangle()
            .fill(onAccent ? env.theme.active.color(.onAccent).opacity(0.3)
                           : Color(rgb: env.theme.active.separator))
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}
