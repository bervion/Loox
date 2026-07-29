import SwiftUI

/// One selectable field row in the quick-link config: toggle + label +
/// masked/plain preview. Secrets never render in the clear here — the owner
/// already knows the value; the row only needs to identify the field.
struct QuickLinkFieldRow: View {
    let field: DynamicField
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: Space.s3) {
                VaultIcon(field.kind.iconAsset, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: appLabel(field.label))
                        .vaultType(.body).themedForeground()
                    Text(verbatim: field.protected ? "••••••••" : field.value)
                        .vaultType(.footnote).themedForeground(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
