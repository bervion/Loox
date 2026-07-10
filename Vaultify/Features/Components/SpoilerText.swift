import SwiftUI

/// Concealed secret display: a static row of bullet dots (no animation). Reveal
/// / conceal is controlled by the parent (the detail row's "•••" menu) — this
/// view just renders the hidden state.
///
/// The dot count is FIXED (not the value's length) so the mask never overflows /
/// truncates and never leaks how long the secret is.
struct SpoilerText: View {
    let text: String
    var font: Font = .vaultCode()

    /// Fixed number of masking dots, independent of the real value length.
    private let dotCount = 12

    var body: some View {
        Text(String(repeating: "•", count: dotCount))
            .font(font)
            .lineLimit(1)
            .accessibilityLabel("Hidden value")
    }
}
