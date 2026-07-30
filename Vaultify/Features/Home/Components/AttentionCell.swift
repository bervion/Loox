import SwiftUI

/// A single row in the Needs Attention grouped list.
/// Shows: favicon/category tile + item name + reason label (with tone icon) +
/// an "Update" button that opens the item editor on the password.
struct AttentionCell: View {
    let item: VaultItem
    /// Runs the row's Update action — the caller decides whether that means the
    /// editor with the password generator up, or the plain editor.
    let onEdit: (VaultItem) -> Void
    /// Tapping the row (outside the Update button) opens the item detail.
    let onOpen: (VaultItem) -> Void
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

    private var reason: AttentionReason? {
        RotationStatus.attentionReason(status: rotationStatus, isWeak: item.hasWeakPassword)
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

    private var tone: RotationTone { reason?.tone ?? .warning }

    private var toneColor: Color { env.theme.active.color(tone.role) }

    // Destructive reasons get a prominent primary button; others get secondary.
    private var isDestructiveTone: Bool { tone == .destructive }

    var body: some View {
        HStack(spacing: Space.s3) {
            // Leading: favicon/category tile (40pt)
            FaviconView(urlString: item.urlField?.value,
                        category: item.category,
                        size: 40, title: item.title)

            // Name + reason row
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)

                HStack(spacing: 4) {
                    VaultIcon(reasonIcon, size: 12)
                        .foregroundStyle(toneColor)
                    Text(reasonLabel)
                        .vaultType(.footnote)
                        .foregroundStyle(toneColor)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: Space.s2)

            // Update action button — the visible capsule stays compact; an
            // invisible frame pads the actual hit area to Metric.hitMin so a
            // near-miss opens Edit, not the row's own onOpen tap (below).
            Button {
                onEdit(item)
            } label: {
                Text("Update")
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
            .frame(minHeight: Metric.hitMin)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: Metric.rowHeight)
        .contentShape(.rect)
        // Whole row opens detail; the Update button intercepts its own taps.
        .onTapGesture { onOpen(item) }
        .overlay(alignment: .bottom) {
            if showDivider {
                // Inset divider aligned with text column (after 16 + 40 + 12 = 68 pt).
                Rectangle()
                    .fill(Color(rgb: env.theme.active.separator))
                    .frame(height: 0.5)
                    .padding(.leading, Space.s4 + 40 + Space.s3)
            }
        }
    }
}
