import SwiftUI

/// Copy-action feedback glyph: the clipboard icon morphs into clipboard-check
/// when `copied` flips on (opacity + scale crossfade of two Polaris icons — no
/// SF Symbols). Reduce Motion swaps instantly. Purely visual: the haptic for a
/// copy comes from `ClipboardService.copy` — firing another one here would
/// double-buzz. The parent owns the `copied` state and its reset timing.
struct CopyMorphIcon: View {
    let copied: Bool
    var size: CGFloat = Metric.iconInline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VaultIcon(Icons.copy, size: size)
                .opacity(copied ? 0 : 1)
                .scaleEffect(copied ? 0.6 : 1)
            VaultIcon(Icons.copyDone, size: size)
                .opacity(copied ? 1 : 0)
                .scaleEffect(copied ? 1 : 0.6)
        }
        .animation(.vault(Motion.spring, reduceMotion: reduceMotion), value: copied)
        // Decorative feedback — the row/button announces the copy itself.
        .accessibilityHidden(true)
    }
}
