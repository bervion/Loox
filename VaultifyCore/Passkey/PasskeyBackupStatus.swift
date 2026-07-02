import Foundation

/// Backup/sync status derived from a passkey's stored WebAuthn authenticator
/// flags (BE = backup eligible, BS = backup state), mirroring how 1Password /
/// iCloud Keychain surface a passkey's portability. Pure logic so it can be
/// unit-tested without a store or UI.
nonisolated enum PasskeyBackupStatus: Equatable {
    /// BE=1, BS=1 — the credential is backed up / syncable.
    case backedUp
    /// BE=1, BS=0 — eligible for backup but not currently backed up.
    case backupEligible
    /// BE=0, or legacy credentials registered before BE/BS support — bound to
    /// this device from the relying party's perspective.
    case deviceBound

    static func evaluate(flags: UInt8?) -> PasskeyBackupStatus {
        guard let flags else { return .deviceBound }
        let backupEligible = flags & WebAuthn.flagBackupEligible != 0
        let backedUp = flags & WebAuthn.flagBackupState != 0
        if backupEligible && backedUp { return .backedUp }
        if backupEligible { return .backupEligible }
        return .deviceBound
    }
}
