import Foundation

/// Deterministic, versioned byte encoding for a signed `RelayCommand`. The
/// transcript is a one-way signing input (the command fields travel separately
/// as JSON to the worker); it is never decoded. The worker re-derives these exact
/// bytes to verify — the frozen parity vectors are the byte-for-byte contract.
///
/// INV-R02: the signature this produces is the PRINCIPAL layer only. App Attest
/// admission is a distinct layer added at network time (P4B); do not merge them.
nonisolated enum RelayCommandCanonical {
    static let magic = RelayConfig.commandMagic   // "LOOX-RELAY-AUTHZ-V1"
    static let version: UInt8 = 1

    /// Layout (all length-prefixed except the leading magic/version/tag):
    /// `magic` (raw) ‖ `version` ‖ `kind` ‖ blob(principalID) ‖ u64(epoch) ‖
    /// blob(nonce) ‖ i64(issuedAtUnixMs) ‖ optionalString(aliasID) ‖
    /// optionalString(destination) ‖ optionalBlob(newPublicKey).
    /// Each optional is a 0/1 flag byte then (if 1) the length-prefixed value.
    static func transcript(_ cmd: RelayCommand) -> Data {
        var w = CanonicalWriter()
        w.raw(Data(magic.utf8))
        w.byte(version)
        w.byte(cmd.kind.rawValue)
        w.blob(cmd.principalID)
        w.u64(cmd.epoch)
        w.blob(cmd.nonce)
        w.i64(cmd.issuedAtUnixMs)
        w.optionalString(cmd.aliasID)
        w.optionalString(cmd.destination)
        w.optionalBlob(cmd.newPublicKey)
        return w.data
    }

    static func sign(_ cmd: RelayCommand,
                     using identity: RelayPrincipalIdentity) throws -> (transcript: Data, signature: Data) {
        let bytes = transcript(cmd)
        return (bytes, try identity.signature(for: bytes))
    }

    static func verify(_ cmd: RelayCommand, signature: Data, x963PublicKey: Data) -> Bool {
        RelayPrincipalIdentity.verify(transcript(cmd), signature: signature, x963PublicKey: x963PublicKey)
    }
}

private extension CanonicalWriter {
    mutating func optionalString(_ value: String?) {
        if let value { byte(1); string(value) } else { byte(0) }
    }
    mutating func optionalBlob(_ value: Data?) {
        if let value { byte(1); blob(value) } else { byte(0) }
    }
}
