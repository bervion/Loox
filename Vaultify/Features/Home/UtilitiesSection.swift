import SwiftUI

/// Home "Utilities" — quick tools (Password Generator now; extensible later).
struct UtilitiesSection: View {
    @Binding var showGenerator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Utilities").font(.title3.bold()).padding(.horizontal, 16)
            Button { showGenerator = true } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)).frame(width: 38, height: 38)
                        .overlay(PolarisIcon(Icons.magic, size: 20).foregroundStyle(Color.accentColor))
                    Text("Password Generator").themedForeground()
                    Spacer()
                    PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                }
                .padding(14)
                .background(VaultColors.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }
}
