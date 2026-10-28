import SwiftUI

/// Resolves whether a login field's value is one of the ACTIVE persona's email
/// aliases, and if so its forwarding destination + verification state. The
/// single recognition point for the private-email treatment shared by Item
/// Detail (badge + forwards-to line) and the Editor (status dot). Persona-scoped
/// (INV-R03): only ever looks at the active persona's own aliases. NOT
/// `nonisolated` — `VaultRepository` is MainActor-isolated (project default),
/// and this resolver only ever runs synchronously from SwiftUI view bodies.
struct PrivateEmailMatch: Equatable {
    let alias: EmailAlias
    let destination: String?
    let verified: Bool

    /// Exact match against the literal address the app ever writes into a
    /// field (`localPart@domain`) — independent of the relay-enabled flag or
    /// the alias's live status, so a paused/disabled alias is still recognized
    /// (its address doesn't change when paused).
    static func resolve(kind: FieldKind, value: String, repository: VaultRepository) -> PrivateEmailMatch? {
        guard kind == .email || kind == .username, !value.isEmpty,
              let persona = repository.activePersona else { return nil }
        guard let alias = repository.aliases(forPersona: persona.id).first(where: {
            $0.resolvedAddress?.caseInsensitiveCompare(value) == .orderedSame
        }) else { return nil }
        let destination = repository.resolvedDestination(for: alias)
        let verified = destination.flatMap { dest in
            repository.forwardingInboxes.first { $0.email.caseInsensitiveCompare(dest) == .orderedSame }
        }?.verificationStatus == .verified
        return PrivateEmailMatch(alias: alias, destination: destination, verified: verified)
    }

    /// The alias's forwarding state as a dot colour. Green only while it
    /// forwards to a verified inbox, so a paused alias never reads as live.
    var statusRole: ThemeRole {
        switch alias.status {
        case .active: return verified ? .success : .warning
        case .paused, .disabled: return .warning
        case .draft, .reserved: return .secondary
        }
    }

    /// `statusRole` in words: what VoiceOver reads for the status dot.
    var statusLabel: String {
        switch alias.status {
        case .active: return verified ? appString("Active") : appString("Pending verification")
        case .paused, .disabled: return appString("Paused")
        case .draft, .reserved: return appString("Not yet active")
        }
    }
}

/// Small "PRIVATE" pill next to a recognized alias field's label.
struct PrivateEmailBadge: View {
    /// True while the host row is mid tap-to-copy flash (accent background) —
    /// the pill switches to a legible on-accent tint instead of its own fill.
    var onAccentBackground = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        // Deliberately BELOW the vaultType scale: this is badge chrome, the
        // smallest text in the app — caption read as loud and clumsy next to a
        // field label (user feedback). SF, not mono.
        Text("PRIVATE")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onAccentBackground ? theme.color(.onAccent) : theme.color(.accent))
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 1)
            .background(onAccentBackground ? theme.color(.onAccent).opacity(0.22) : theme.color(.accentSoft),
                       in: Capsule())
    }
}

/// Item Detail's "FORWARDS TO {real email}" secondary line with a status dot.
/// Paused/draft states render a muted dot (`PrivateEmailMatch.statusRole`), so
/// a paused alias never renders as if it were still forwarding.
struct PrivateEmailForwardsToLine: View {
    let match: PrivateEmailMatch
    var onAccentBackground = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        // Single line always: the caps label and the status never wrap (the VI
        // label "CHUYỂN TIẾP ĐẾN" broke onto two lines when the email pushed it) —
        // only the destination email compresses, truncating its tail.
        HStack(spacing: 5) {
            // lineLimit(1) without fixedSize: the label may truncate under
            // extreme pressure but can never wrap onto two lines NOR force the
            // row wider than the screen (a rigid label here once pushed the
            // whole detail layout past the gutters).
            Text("FORWARDS TO").vaultType(.caption).fontWeight(.medium)
                .lineLimit(1)
            if let destination = match.destination {
                Text(verbatim: destination).vaultType(.caption)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(-1)
            }
            // Not `StatusDot`: that one is hidden from VoiceOver, and here the
            // dot is the only place the state is said.
            Circle().fill(theme.color(match.statusRole)).frame(width: 6, height: 6)
                .accessibilityLabel(Text(verbatim: match.statusLabel))
            Spacer(minLength: 0)
        }
        .foregroundStyle(onAccentBackground ? theme.color(.onAccent).opacity(0.85) : theme.color(.secondary))
    }
}
