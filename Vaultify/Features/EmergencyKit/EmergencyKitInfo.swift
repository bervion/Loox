import Foundation

/// Everything printed on a Loox Emergency Kit. Assembled at generation time from the
/// onboarding profile (or a stored identity) plus the freshly-shown recovery key.
///
/// Security model (see also `RecoveryKey`): the recovery key is an INDEPENDENT unlock
/// path — with the vault available (downloaded from iCloud) it restores access WITHOUT
/// the master password. So the kit is a sensitive credential in its own right; the PDF
/// says so plainly rather than implying a password is also required.
struct EmergencyKitInfo {
    /// The grouped recovery key (e.g. `A1B2-C3D4-…`) — the "Secret Key" of the kit.
    var recoveryKey: String
    /// Display name for the "Created for …" footer. Empty → the line is omitted.
    var ownerName: String
    /// The email the user gave at setup — reminds which iCloud account holds the synced
    /// vault the recovery key restores. Empty → the row is omitted.
    var iCloudAccount: String
    var createdAt: Date

    /// Where to reach for help, printed under the instructions. Placeholder until a real
    /// support address is decided — single source so it is trivial to change.
    var supportContact: String = "support@looxpassword.com"

    /// QR "Setup Code" payload — the recovery key exactly as displayed. A new device scans
    /// it on the "Use Recovery Key" screen instead of typing. The key alone decrypts nothing
    /// without the synced vault, so this matches the safety of the manual-entry path.
    var qrPayload: String { recoveryKey }

    /// File name offered by the exporter (the `.pdf` extension is added by the exporter).
    var suggestedFilename: String { "Loox Emergency Kit" }

    /// Localized "Created for {name} on {date}." — omits the name clause when unknown.
    var createdLine: String {
        let date = createdAt.formatted(date: .abbreviated, time: .omitted)
        let name = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? String(format: appString("Created on %@."), date)
            : String(format: appString("Created for %@ on %@."), name, date)
    }
}
