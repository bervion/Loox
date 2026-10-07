import Foundation

/// Constants for the live email-relay control plane (client side).
nonisolated enum RelayConfig {
    /// Domain separator for the principal-id fingerprint (never reused elsewhere).
    static let principalMagic = "LOOX-RELAY-PRINCIPAL-V1"
    /// Domain separator + version for signed relay commands.
    static let commandMagic = "LOOX-RELAY-AUTHZ-V1"

    /// Relay control API. Staging's control plane also runs, but mail ingress is
    /// prod-only (one catch-all per zone) — so DEBUG talks to prod too; the
    /// staging URL is kept for targeted API tests. Vault relay records are not
    /// environment-scoped, so app installs must not switch their API backend.
    static let apiBaseURL = URL(string: "https://api-relay.looxpassword.com")!
    static let stagingAPIBaseURL = URL(string: "https://api-relay-staging.looxpassword.com")!
    /// Shared vault relay records are bound to production on Debug and Release.
    static let environment = "production"
    /// The alias mail domain: an alias is `<local-part>@relay.looxpassword.com`.
    static let emailDomain = "relay.looxpassword.com"

    /// Relay App Attest admission (INV-R02). When enabled, protected mutations
    /// register the device key with loox-relay and carry a per-command assertion.
    /// The server runs `ASSERTION_MODE=required` (go-live 2026-07-07): a mutation
    /// without a valid assertion is rejected (401). `attestationRequired = true`
    /// keeps the client in lockstep — a failed assertion hard-fails locally with
    /// a clear error instead of a server round-trip that 401s anyway.
    static let attestationEnabled = true
    static let attestationRequired = true

    /// Destination ownership routing (DEC-DST-01). Server is at
    /// `DESTINATION_VERIFICATION_MODE=required`, so `rotateDestination` binds the
    /// inbox's opaque verified destination_id instead of the raw email; an
    /// unverified inbox is refused locally (mirrors the server 403 / ingress 550).
    /// Was false during the shadow window — flipped in lockstep with the server.
    static let destinationRoutingRequiresVerification = true

    /// Keychain fast-cache account for the sealed principal escrow envelope.
    static let escrowKeychainAccount = "relay_principal_escrow_cache_v1"
    /// CloudKit singleton record for the Vault-Key-sealed principal escrow.
    static let escrowRecordType = "RelayPrincipalEscrow"
    static let escrowRecordName = "relay-principal-escrow"
}
