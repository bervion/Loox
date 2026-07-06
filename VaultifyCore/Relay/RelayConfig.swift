import Foundation

/// Constants for the email-relay control plane (client side). The relay backend
/// does not exist yet; these fix the domain-separation strings + storage keys so
/// the future worker can be cross-checked against frozen parity vectors.
nonisolated enum RelayConfig {
    /// Domain separator for the principal-id fingerprint (never reused elsewhere).
    static let principalMagic = "LOOX-RELAY-PRINCIPAL-V1"
    /// Domain separator + version for signed relay commands.
    static let commandMagic = "LOOX-RELAY-AUTHZ-V1"

    /// Keychain fast-cache account for the sealed principal escrow envelope.
    static let escrowKeychainAccount = "relay_principal_escrow_cache_v1"
    /// CloudKit singleton record for the Vault-Key-sealed principal escrow.
    static let escrowRecordType = "RelayPrincipalEscrow"
    static let escrowRecordName = "relay-principal-escrow"
}
