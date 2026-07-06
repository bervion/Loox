import Foundation

/// The public projection of a Relay Principal the backend pins: a stable
/// `principalID` with a rotating `signingPublicKey` + monotonic `epoch`. A
/// rotate command signed by epoch N advances the backend to N+1 (CAS); commands
/// under a superseded epoch are rejected. Carries no private material.
nonisolated struct RelayPrincipalState: Codable, Sendable, Equatable {
    var principalID: Data
    var epoch: UInt64
    var signingPublicKey: Data
}
