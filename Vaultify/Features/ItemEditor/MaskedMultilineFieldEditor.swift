import SwiftUI

/// Controlled-Reveal editor for a `protected` multiline field (SSH Private Key,
/// Recovery Codes): masked by default, reveal is local and deliberate. Unlike the
/// single-line protected fields (which keep one persistent `TextField` and only
/// toggle its opacity), a multiline value is masked with a fixed-line summary and a
/// dedicated Reveal button — swapping to the real editor only after that explicit tap.
///
/// Empty fields skip the mask entirely (nothing to protect yet) so first-time entry
/// has no extra tap. Once revealed the editor stays up while focused; losing focus
/// (tap away, dismiss keyboard) remasks it — "stays until the row loses focus/collapses".
struct MaskedMultilineFieldEditor: View {
    @Binding var value: String
    let placeholder: LocalizedStringKey

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The real editor shows while typing/focused or when there's nothing yet to mask;
    /// otherwise the masked summary is shown until the user deliberately reveals it.
    private var showsEditor: Bool { focused || isEmpty }

    var body: some View {
        Group {
            if showsEditor {
                TextField(placeholder, text: $value, axis: .vertical)
                    .font(.vaultCode())
                    .lineLimit(2...6)
                    .focused($focused)
            } else {
                maskedSummary
            }
        }
        .animation(.vault(.easeOut(duration: Motion.fast), reduceMotion: reduceMotion), value: showsEditor)
    }

    private var maskedSummary: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Fixed-length dot line, matching the single-line mask convention
                // (`EditorFieldRow.maskedValue`) — never hints at the real content or
                // its precise length.
                Text(String(repeating: "•", count: 16))
                    .font(.vaultCode())
                    .themedForeground(.primary)
                Text(lineCountHint)
                    .vaultType(.caption)
                    .themedForeground(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                // Revealing a protected multiline secret is a deliberate boundary
                // crossing (same vocabulary as `ProtectedFieldRow`'s Level-2 reveal).
                Haptics.warning()
                focused = true
            } label: {
                PolarisIcon(Icons.reveal, size: 20)
                    .themedForeground(.secondary)
                    // Visual glyph stays compact; tappable region meets the 44pt
                    // minimum (rule 6 hit-target convention used across this file).
                    .frame(width: Metric.hitMin, height: Metric.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reveal to edit"))
        }
    }

    /// Line-count hint only (never the character count), so the mask can't be used
    /// to estimate the secret's real length.
    private var lineCountHint: String {
        let count = value.components(separatedBy: .newlines).count
        return count == 1 ? appString("1 line hidden") : appString("\(count) lines hidden")
    }
}
