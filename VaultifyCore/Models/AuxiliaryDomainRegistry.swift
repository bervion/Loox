import Foundation

/// What an auxiliary domain may be used for. Auxiliary domains are resource
/// namespaces only (email suffixes, short-link hosts) — they never become API
/// hosts, deep-link hosts, or config endpoints; those stay on the canonical
/// platform domain.
nonisolated enum AuxiliaryDomainCapability: String, Codable, Sendable {
    case privateEmail = "private_email"
    case shortLink = "short_link"
}

/// Lifecycle of an auxiliary domain. Creation gating is separate from the
/// survival of already-issued resources: existing aliases/links on a domain
/// keep working through `createDisabled` and `retiring`; only an explicit
/// backend shutdown policy ends them.
nonisolated enum AuxiliaryDomainLifecycle: String, Codable, Sendable {
    case active
    case createDisabled = "create_disabled"
    case retiring
    case retired

    /// New aliases/short links may be minted on this domain.
    var allowsCreation: Bool { self == .active }
}

/// One trusted auxiliary domain. `emailAddressDomain` and `shortLinkHost` are
/// independent optional roles — a domain may serve either or both.
nonisolated struct AuxiliaryDomainDescriptor: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let emailAddressDomain: String?
    let shortLinkHost: String?
    let capabilities: Set<AuxiliaryDomainCapability>
    let lifecycle: AuxiliaryDomainLifecycle
    let isPrimaryEmailChoice: Bool
    let isPrimaryShortLinkChoice: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case emailAddressDomain = "email_address_domain"
        case shortLinkHost = "short_link_host"
        case capabilities, lifecycle
        case isPrimaryEmailChoice = "is_primary_email_choice"
        case isPrimaryShortLinkChoice = "is_primary_short_link_choice"
    }

    var offersPrivateEmail: Bool {
        capabilities.contains(.privateEmail) && emailAddressDomain != nil
    }
}

/// The set of auxiliary domains this build trusts. Unknown domain IDs coming
/// from anywhere else (sync payloads, future remote config) resolve to nothing
/// — a host never becomes trusted merely because some payload named it.
///
/// Today this is the bundled registry only. The signed remote registry
/// (`LOOX-DOMAIN-REGISTRY-V1`, same P256 trust root as the capability
/// manifest, independent anti-rollback version) replaces `current` once its
/// byte contract is frozen with the backend — until then, shipping a new
/// domain means shipping an app update, which is the safe default.
nonisolated enum AuxiliaryDomainRegistry {

    /// Domain ID stamped on every alias created before domains were explicit,
    /// and the decode fallback for sealed alias blobs missing the field.
    static let legacyEmailDomainID = "relay-main"

    /// Bundled trust set. Exactly one primary per capability among `active`
    /// entries — keep that invariant when editing.
    static let bundled: [AuxiliaryDomainDescriptor] = [
        AuxiliaryDomainDescriptor(
            id: legacyEmailDomainID,
            displayName: "Loox Standard",
            emailAddressDomain: RelayConfig.emailDomain,
            shortLinkHost: nil,
            capabilities: [.privateEmail],
            lifecycle: .active,
            isPrimaryEmailChoice: true,
            isPrimaryShortLinkChoice: false),
    ]

    static var current: [AuxiliaryDomainDescriptor] { bundled }

    static func descriptor(id: String) -> AuxiliaryDomainDescriptor? {
        current.first { $0.id == id }
    }

    /// Domains offered for NEW alias creation (picker contents). One entry →
    /// the picker stays hidden and creation silently uses the default.
    static var creatableEmailDomains: [AuxiliaryDomainDescriptor] {
        current.filter { $0.offersPrivateEmail && $0.lifecycle.allowsCreation }
    }

    /// Default domain for a new alias: the registry's primary email choice,
    /// falling back to legacy so alias creation can never fail on a
    /// misconfigured registry.
    static var defaultEmailDomainID: String {
        creatableEmailDomains.first(where: { $0.isPrimaryEmailChoice })?.id
            ?? legacyEmailDomainID
    }

    /// The mail domain to display/copy for an alias. Unknown or retired IDs
    /// still resolve to their recorded descriptor when present; a completely
    /// unknown ID falls back to the legacy domain so an address is never
    /// rendered blank (the alias's real address is immutable server-side).
    static func emailDomain(forDomainID id: String) -> String {
        descriptor(id: id)?.emailAddressDomain ?? RelayConfig.emailDomain
    }
}
