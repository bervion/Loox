import SwiftUI

/// Resolves whether a login field's value is one of the ACTIVE persona's email
/// aliases, and if so its forwarding destination + verification state. The
/// single recognition point for the "PRIVATE" convention (badge + mono +
/// forwards-to line) shared by Item Detail and the Editor. Persona-scoped
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

/// "FORWARDS TO {real email}" secondary line with a status dot. Paused/draft
/// states render a muted dot (the live "Active" + verified-green case is the
/// only one the mockup drew; this generalizes it to every alias status so a
/// paused alias never renders as if it were still forwarding).
struct PrivateEmailForwardsToLine: View {
    let match: PrivateEmailMatch
    var onAccentBackground = false
    /// Detail keeps the line minimal (dot only — the dot color already carries
    /// the state); the editor spells the status out since that's where the
    /// user manages the alias.
    var showsStatusText = true
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
            Circle().fill(dotColor(theme)).frame(width: 6, height: 6)
                .accessibilityLabel(Text(verbatim: statusText))
            if showsStatusText {
                Text(statusText).vaultType(.caption)
                    .lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(onAccentBackground ? theme.color(.onAccent).opacity(0.85) : theme.color(.secondary))
    }

    private var statusText: String {
        switch match.alias.status {
        case .active:   return match.verified ? appString("Active") : appString("Pending verification")
        case .paused, .disabled: return appString("Paused")
        case .draft, .reserved:  return appString("Not yet active")
        }
    }

    private func dotColor(_ theme: AppTheme) -> Color {
        switch match.alias.status {
        case .active: return match.verified ? theme.color(.success) : theme.color(.warning)
        case .paused, .disabled: return theme.color(.warning)
        case .draft, .reserved: return theme.color(.secondary)
        }
    }
}
