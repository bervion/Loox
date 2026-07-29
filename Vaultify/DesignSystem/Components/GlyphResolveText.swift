import SwiftUI

/// Per-glyph "resolve" for secret values (Controlled Reveal): concealed shows a
/// fixed-length dot mask (like `SpoilerText` — never leaks the value's length);
/// on reveal the real characters resolve left to right within a fixed time
/// budget, so long secrets finish as fast as short ones. Conceal snaps straight
/// back to the mask. Reduce Motion collapses the stagger to an instant swap.
struct GlyphResolveText: View {
    let text: String
    let isRevealed: Bool
    var font: Font = .vaultCode()
    /// Colour resolved glyphs by character class (digit / letter / symbol), the same
    /// reading aid the generator and the Large Type viewer use. Off by default: a card
    /// number is all digits, so colouring one just paints the whole field blue.
    var colorized: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    /// Leading characters currently resolved (0 = fully masked).
    @State private var resolvedCount = 0

    /// Fixed mask length while concealed — independent of the value's length.
    private static let maskCount = 12
    /// Total resolve budget; per-glyph stagger shrinks on long values to stay inside it.
    private static let totalBudget = 0.4
    private static let perGlyph = 0.035

    var body: some View {
        Text(attributed)
            .font(font)
            .lineLimit(isRevealed ? nil : 1)
            .accessibilityLabel(isRevealed ? Text(verbatim: text) : Text("Hidden value"))
            // Keyed on the revealed VALUE too: if the text changes while revealed
            // (edit/sync), the resolve re-runs instead of leaving stale mask dots.
            // The id is an in-memory Equatable only — never logged or persisted.
            .task(id: isRevealed ? "revealed:\(text)" : "concealed") { await resolve() }
    }

    /// Resolved prefix + dot remainder while animating; the fixed mask when concealed.
    /// MonoLisa is monospaced, so the dot→glyph swap never shifts layout width.
    ///
    /// Colour is applied per glyph rather than to the whole string so it tracks the resolve:
    /// a character takes its class colour at the moment it lands, and the dots still waiting
    /// stay neutral instead of flashing red because "•" is punctuation.
    private var attributed: AttributedString {
        guard isRevealed else {
            return AttributedString(String(repeating: "•", count: Self.maskCount))
        }
        let characters = Array(text)
        let shown = min(resolvedCount, characters.count)
        let resolved = String(characters.prefix(shown))
        let pending = String(repeating: "•", count: characters.count - shown)

        guard colorized else { return AttributedString(resolved + pending) }
        var result = SecretColoring.attributed(resolved, theme: env.theme.active)
        var mask = AttributedString(pending)
        mask.foregroundColor = env.theme.active.color(.secondary)
        result.append(mask)
        return result
    }

    private func resolve() async {
        guard isRevealed else {
            resolvedCount = 0
            return
        }
        guard !reduceMotion, !text.isEmpty else {
            resolvedCount = text.count
            return
        }
        let step = min(Self.perGlyph, Self.totalBudget / Double(text.count))
        resolvedCount = 0
        for index in 1...text.count {
            try? await Task.sleep(for: .seconds(step))
            guard !Task.isCancelled, isRevealed else { return }
            resolvedCount = index
        }
    }
}
