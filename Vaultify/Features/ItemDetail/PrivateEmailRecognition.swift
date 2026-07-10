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
            "\($0.localPart)@\($0.emailDomain)".caseInsensitiveCompare(value) == .orderedSame
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
        Text("PRIVATE")
            .vaultType(.caption).fontWeight(.bold)
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
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        HStack(spacing: 5) {
            Text("FORWARDS TO").vaultType(.caption).fontWeight(.medium)
            if let destination = match.destination {
                Text(verbatim: destination).vaultType(.caption).lineLimit(1).truncationMode(.middle)
            }
            Circle().fill(dotColor(theme)).frame(width: 6, height: 6)
            Text(statusText).vaultType(.caption)
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
