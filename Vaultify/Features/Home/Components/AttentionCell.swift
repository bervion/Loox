import SwiftUI

/// A single row in the "Cần chú ý" (Needs Attention) grouped list.
/// Shows: favicon/category tile + item name + reason label (with tone icon) +
/// "Đổi" button that opens the item editor.
struct AttentionCell: View {
    let item: VaultItem
    let onEdit: (VaultItem) -> Void
    /// Controls the hairline divider between cells inside the grouped card.
    var showDivider: Bool = true

    @Environment(AppEnvironment.self) private var env

    // Compute attention reason + rotation status once per render.
    private var rotationStatus: RotationStatus {
        RotationStatus.evaluate(
            rotateDays: item.rotateDays,
            passwordChangedAt: item.passwordChangedAt,
            createdAt: item.createdAt)
    }

    private var isWeak: Bool {
        (item.passwordField.map { PasswordStrength.evaluate($0.value) } ?? .strong) == .weak
    }

    private var reason: AttentionReason? {
        RotationStatus.attentionReason(status: rotationStatus, isWeak: isWeak)
    }

    private var reasonLabel: LocalizedStringResource {
        switch reason {
        case .overdue: return rotationStatus.short
        case .weak: return LocalizedStringResource("Weak password").inAppLocalized
        case .soon: return rotationStatus.short
        case .stale: return rotationStatus.short
        case .none: return LocalizedStringResource("Check needed").inAppLocalized
        }
    }

    private var reasonIcon: String {
        switch reason {
        case .overdue, .weak: return Icons.alert
        case .soon, .stale: return Icons.clock
        case .none: return Icons.alert
        }
    }

    private var tone: RotationTone {
        switch reason {
        case .overdue, .weak: return .destructive
        case .soon, .stale: return .warning
        case .none: return .warning
        }
    }

    private var toneColor: Color {
        switch tone {
        case .destructive: return env.theme.active.color(.destructive)
        case .warning: return env.theme.active.color(.warning)
        case .neutral: return env.theme.active.color(.secondary)
        }
    }

    // Destructive reasons get a prominent primary button; others get secondary.
    private var isDestructiveTone: Bool { tone == .destructive }

    var body: some View {
        HStack(spacing: Space.s3) {
            // Leading: favicon/category tile (40pt)
            FaviconView(urlString: item.urlField?.value,
                        category: item.category,
                        size: 40)

            // Name + reason row
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)

                HStack(spacing: 4) {
                    PolarisIcon(reasonIcon, size: 12)
                        .foregroundStyle(toneColor)
                    Text(reasonLabel)
                        .vaultType(.footnote)
                        .foregroundStyle(toneColor)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: Space.s2)

            // "Đổi" action button
            Button {
                onEdit(item)
            } label: {
                Text("Change")
                    .vaultType(.subhead)
                    .fontWeight(.medium)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1 + 2)
                    .background(
                        isDestructiveTone
                            ? env.theme.active.color(.accent)
                            : Color(rgb: env.theme.active.controlBackground),
                        in: Capsule()
                    )
                    .foregroundStyle(
                        isDestructiveTone
                            ? env.theme.active.color(.onAccent)
                            : env.theme.active.color(.primary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: Metric.rowHeight)
        .contentShape(.rect)
        .overlay(alignment: .bottom) {
            if showDivider {
                // Inset divider aligned with text column (after 16 + 40 + 12 = 68 pt).
                Rectangle()
                    .fill(Color(rgb: env.theme.active.separator))
                    .frame(height: 0.5)
                    .padding(.leading, Space.gutter + 40 + Space.s3)
            }
        }
    }
}
