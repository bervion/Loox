import SwiftUI

/// The sidebar's identity row, drawn as its own floating card instead of a bare list
/// row: the active persona's avatar, name, and subtitle inside a rounded surface —
/// Liquid Glass on iOS 26, a solid elevated surface elsewhere.
///
/// Deliberately a `Button`, not a tagged selectable row: the card paints its OWN
/// selected state (an accent-soft wash) so it never has to fight the list's row
/// highlight, whose square inset would cut across the card's corners.
struct VaultSidebarProfileCard: View {
    @Environment(AppEnvironment.self) private var env
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                PersonaAvatarView(size: Metric.iconTileLarge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: PersonaDisplay.name(env))
                        .vaultType(.headline)
                        .themedForeground()
                        .lineLimit(1)
                    Text(verbatim: PersonaDisplay.subtitle(env))
                        .vaultType(.caption)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // Inset on every side so the avatar sits INSIDE the card rather than flush
            // against its edge, and the name column keeps its distance from the photo.
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vaultSidebarCardSurface(isSelected: isSelected)
            .contentShape(.rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(PersonaDisplay.name(env)), \(PersonaDisplay.subtitle(env))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Card surface for the sidebar identity row, applied **directly to the content**
/// (not as a background sublayer — that stops `glassEffect` from rendering):
/// - **iOS 26+** (Xcode 26+/Swift ≥ 6.2, transparency allowed): real Liquid Glass,
///   tinted with the elevated surface at rest and accent-soft while selected.
/// - **Else / Reduce Transparency:** the solid token colour + hairline + level-1 shadow.
///
/// `#if compiler(>=6.2)` keeps a pre-Xcode-26 CI runner from ever seeing the
/// `glassEffect` symbol, so the release build always compiles.
private struct VaultSidebarCardSurface: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
    }

    /// At rest the card is the plain elevated surface (white in light, the raised
    /// dark surface in dark); selected swaps in the accent-soft wash.
    private var tint: Color {
        Color(rgb: isSelected ? env.theme.active.accentSoft : env.theme.active.elevatedBackground)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            // The sidebar is itself a near-white material, so a lightly tinted glass
            // card disappears into it. The tint stays near-opaque and the card keeps
            // its own level-1 shadow — that lift, not the fill, is what makes it read
            // as a card floating on the sidebar.
            content
                .glassEffect(
                    .regular.tint(tint.opacity(isSelected ? 1 : 0.92)).interactive(),
                    in: shape)
                .elevation(.level1)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(tint, in: shape)
            .overlay(shape.strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5))
            .elevation(.level1)
    }
}

extension View {
    /// Render the receiver as the sidebar identity card surface (see `VaultSidebarCardSurface`).
    func vaultSidebarCardSurface(isSelected: Bool) -> some View {
        modifier(VaultSidebarCardSurface(isSelected: isSelected))
    }
}
