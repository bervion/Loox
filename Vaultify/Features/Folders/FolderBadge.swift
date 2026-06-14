import SwiftUI

/// Resolves a `FolderColor` to a trait-aware SwiftUI `Color`. Lives in the app
/// layer so VaultifyCore stays UI-free.
extension FolderColor {
    var tint: Color { VaultColors.dynamic(light: light, dark: dark) }
}

/// Rounded, tinted tile showing a folder's Polaris icon over its color — the
/// shared visual for Spaces in the grid, picker rows, and editor preview.
struct FolderBadge: View {
    let icon: String
    let color: FolderColor
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                PolarisIcon(icon, size: size * 0.56)
                    .foregroundStyle(color.tint)
            )
    }
}
