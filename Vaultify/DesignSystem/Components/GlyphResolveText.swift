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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Leading characters currently resolved (0 = fully masked).
    @State private var resolvedCount = 0

    /// Fixed mask length while concealed — independent of the value's length.
    private static let maskCount = 16
    /// Total resolve budget; per-glyph stagger shrinks on long values to stay inside it.
    private static let totalBudget = 0.4
    private static let perGlyph = 0.035

    var body: some View {
        Text(displayed)
            .font(font)
            .lineLimit(isRevealed ? nil : 1)
            .accessibilityLabel(isRevealed ? Text(verbatim: text) : Text("Hidden value"))
            .task(id: isRevealed) { await resolve() }
    }

    /// Resolved prefix + dot remainder while animating; the fixed mask when concealed.
    /// MonoLisa is monospaced, so the dot→glyph swap never shifts layout width.
    private var displayed: String {
        guard isRevealed else {
            return String(repeating: "•", count: Self.maskCount)
        }
        let characters = Array(text)
        let shown = min(resolvedCount, characters.count)
        return String(characters.prefix(shown))
            + String(repeating: "•", count: characters.count - shown)
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
