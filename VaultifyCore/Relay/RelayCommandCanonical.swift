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
    static let magicV2 = "LOOX-RELAY-AUTHZ-V2"
    static let versionV2: UInt8 = 2

    /// V1 layout — FROZEN, byte-for-byte the shipped worker contract; it
    /// cannot express a domain choice (`domainID` is ignored here), which is
    /// why namespace-bearing commands must sign V2 instead.
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

    /// V2 layout (relay-authz-v2-contract.md, frozen vectors
    /// `relay-authz-command-vectors-v2.json`): V1 base + optString(domainID)
    /// directly after aliasID. Transcript presence must equal wire presence —
    /// the signature is what enforces the namespace the server acts on.
    static func transcriptV2(_ cmd: RelayCommand) -> Data {
        var w = CanonicalWriter()
        w.raw(Data(magicV2.utf8))
        w.byte(versionV2)
        w.byte(cmd.kind.rawValue)
        w.blob(cmd.principalID)
        w.u64(cmd.epoch)
        w.blob(cmd.nonce)
        w.i64(cmd.issuedAtUnixMs)
        w.optionalString(cmd.aliasID)
        w.optionalString(cmd.domainID)
        w.optionalString(cmd.destination)
        w.optionalBlob(cmd.newPublicKey)
        return w.data
    }

    static func sign(_ cmd: RelayCommand,
                     using identity: RelayPrincipalIdentity) throws -> (transcript: Data, signature: Data) {
        let bytes = transcript(cmd)
        return (bytes, try identity.signature(for: bytes))
    }

    static func signV2(_ cmd: RelayCommand,
                       using identity: RelayPrincipalIdentity) throws -> (transcript: Data, signature: Data) {
        let bytes = transcriptV2(cmd)
        return (bytes, try identity.signature(for: bytes))
    }

    static func verify(_ cmd: RelayCommand, signature: Data, x963PublicKey: Data) -> Bool {
        RelayPrincipalIdentity.verify(transcript(cmd), signature: signature, x963PublicKey: x963PublicKey)
    }

    static func verifyV2(_ cmd: RelayCommand, signature: Data, x963PublicKey: Data) -> Bool {
        RelayPrincipalIdentity.verify(transcriptV2(cmd), signature: signature, x963PublicKey: x963PublicKey)
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
