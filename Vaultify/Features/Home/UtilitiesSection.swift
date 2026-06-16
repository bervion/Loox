import SwiftUI

/// Home "Utilities" — quick tools (Password Generator now; extensible later).
struct UtilitiesSection: View {
    @Binding var showGenerator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Utilities").font(.title3.bold()).padding(.horizontal, Space.s4)
            Button { showGenerator = true } label: {
                HStack(spacing: Space.s3) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)).frame(width: 38, height: 38)
                        .overlay(PolarisIcon(Icons.magic, size: Metric.iconInline).foregroundStyle(Color.accentColor))
                    Text("Password Generator").themedForeground()
                    Spacer()
                    PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                }
                .padding(14)
                .background(VaultColors.surface,
                            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s4)
        }
    }
}
