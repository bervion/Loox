import Foundation

/// The operations a Relay Principal can authorize. The raw tag byte
/// domain-separates transcripts, so one kind's signature can never verify as
/// another's.
nonisolated enum RelayCommandKind: UInt8, Sendable, Equatable {
    case createAlias = 1
    case disableAlias = 2
    case rotateDestination = 3
    case deleteAlias = 4
    case disableAll = 5
    case rotatePrincipal = 6
}

/// A relay operation authorized by the current principal epoch. This is the
/// PRINCIPAL-authorization layer only — App Attest device admission (INV-R02) is
/// a separate layer added at network time; the two are never folded together.
///
/// Which optionals are set is kind-dependent (documented, not type-enforced —
/// KISS): createAlias/disableAlias/deleteAlias → aliasID; rotateDestination →
/// aliasID + destination; disableAll → none; rotatePrincipal → newPublicKey.
/// The transcript encodes whatever is set, deterministically (flag-gated).
nonisolated struct RelayCommand: Sendable, Equatable {
    var principalID: Data
    var epoch: UInt64
    /// Single-use anti-replay value (the backend consumes it authoritatively).
    var nonce: Data
    var issuedAtUnixMs: Int64
    var kind: RelayCommandKind
    var aliasID: String?
    var destination: String?
    var newPublicKey: Data?

    init(principalID: Data, epoch: UInt64, nonce: Data, issuedAtUnixMs: Int64,
         kind: RelayCommandKind, aliasID: String? = nil, destination: String? = nil,
         newPublicKey: Data? = nil) {
        self.principalID = principalID
        self.epoch = epoch
        self.nonce = nonce
        self.issuedAtUnixMs = issuedAtUnixMs
        self.kind = kind
        self.aliasID = aliasID
        self.destination = destination
        self.newPublicKey = newPublicKey
    }
}
