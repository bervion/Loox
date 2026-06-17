import SwiftUI

/// A quick-action tile from the Home DS kit: 54pt tinted square with a centred
/// Polaris icon and a short caption below. Each of the four actions carries its
/// own decorative tint (fixed accent/teal/purple/green — same pattern as item
/// favicon tints, allowed per design spec).
struct QuickActionTile: View {
    let icon: String
    let label: LocalizedStringResource
    let tint: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s2) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 54, height: 54)
                    .overlay(
                        PolarisIcon(icon, size: 24)
                            .foregroundStyle(tint)
                    )
                Text(label)
                    .vaultType(.caption)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            // 44pt minimum hit target (Apple HIG)
            .contentShape(.rect(cornerRadius: Radius.md))
        }
        .buttonStyle(QuickActionButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(Text(label))
    }
}

// Press-scale feedback matching DS press = 0.97.
private struct QuickActionButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Motion.fast),
                       value: configuration.isPressed)
    }
}

// MARK: - Convenience factory for the four canonical Home quick actions

extension QuickActionTile {
    /// Accent tint — matches the live theme accent.
    static func add(env: AppEnvironment, action: @escaping () -> Void) -> QuickActionTile {
        QuickActionTile(
            icon: Icons.add,
            label: LocalizedStringResource("Add Item").inAppLocalized,
            tint: Color(rgb: env.theme.active.accent),
            action: action)
    }

    static func generate(action: @escaping () -> Void) -> QuickActionTile {
        QuickActionTile(
            icon: Icons.refresh,
            label: LocalizedStringResource("Generate Password").inAppLocalized,
            // Teal — decorative, fixed per DS spec
            tint: VaultColors.dynamic(light: 0x0E8A7D, dark: 0x1DB8A6),
            action: action)
    }

    static func totp(action: @escaping () -> Void) -> QuickActionTile {
        QuickActionTile(
            icon: Icons.clock,
            label: LocalizedStringResource("2FA Codes").inAppLocalized,
            // Purple — decorative, fixed per DS spec
            tint: VaultColors.dynamic(light: 0x7C3AED, dark: 0x9D65F5),
            action: action)
    }

    static func watchtower(action: @escaping () -> Void) -> QuickActionTile {
        QuickActionTile(
            icon: Icons.watchtower,
            label: LocalizedStringResource("Watchtower").inAppLocalized,
            // Green — decorative, fixed per DS spec
            tint: VaultColors.dynamic(light: 0x0A8F3C, dark: 0x1DB356),
            action: action)
    }
}
