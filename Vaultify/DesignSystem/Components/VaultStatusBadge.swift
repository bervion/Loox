import SwiftUI

/// Shared status language across sharing / sync / alias flows:
/// green = active or waiting on *you*, orange = waiting on *them*,
/// accent = actionable, gray = disabled/paused.
enum VaultStatusKind {
    case active, pending, action, disabled

    var role: ThemeRole {
        switch self {
        case .active: return .success
        case .pending: return .warning
        case .action: return .accent
        case .disabled: return .disabled
        }
    }
}

/// Small colored dot conveying a `VaultStatusKind` next to a row title.
struct StatusDot: View {
    let role: ThemeRole
    var size: CGFloat = 8

    init(kind: VaultStatusKind, size: CGFloat = 8) {
        self.init(role: kind.role, size: size)
    }

    /// A state scale of its own (a private email alias reads "not yet live"
    /// as `secondary`, not `disabled`).
    init(role: ThemeRole, size: CGFloat = 8) {
        self.role = role
        self.size = size
    }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Circle()
            .fill(env.theme.active.color(role))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Pill badge: soft-tinted capsule with a status dot and a short label
/// ("Pending", "Active", "3 waiting", …). Caller supplies the localized label.
struct VaultStatusBadge: View {
    let kind: VaultStatusKind
    let label: LocalizedStringKey

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let tint = env.theme.active.color(kind.role)
        HStack(spacing: Space.s1) {
            StatusDot(kind: kind, size: 6)
            Text(label)
                .vaultType(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s1)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
