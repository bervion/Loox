import Foundation

/// Everything printed on a Loox Emergency Kit. Assembled at generation time from the
/// onboarding profile (or a stored identity) plus the freshly-shown recovery key.
///
/// Security model (see also `RecoveryKey`): the recovery key is an INDEPENDENT unlock
/// path — with the vault available (downloaded from iCloud) it restores access WITHOUT
/// the master password. So the kit is a sensitive credential in its own right; the PDF
/// says so plainly rather than implying a password is also required.
///
/// REACH is not the same as the security model. A kit whose recovery envelope never
/// reached iCloud can only reset the master password on the installation that made it —
/// it is not a backup and cannot survive device loss. `scope` carries that fact into the
/// printed page so the instructions can never promise more than the kit can do.
struct EmergencyKitInfo {
    /// The grouped recovery key (e.g. `A1B2-C3D4-…`) — the "Secret Key" of the kit.
    var recoveryKey: String
    /// Display name for the "Created for …" footer. Empty → the line is omitted.
    var ownerName: String
    /// The email the user gave at setup — reminds which iCloud account holds the synced
    /// vault the recovery key restores. Empty → the row is omitted.
    var iCloudAccount: String
    var createdAt: Date
    /// What this kit can actually do, resolved when the page is rendered. Defaults to the
    /// narrower claim on purpose: a caller that forgets to resolve it under-promises
    /// instead of printing a restore path the user does not have.
    var scope: EmergencyKitScope = .thisInstallationOnly

    /// Where to reach for help — printed under the kit instructions and shown on the
    /// About page. Single source, so a future channel change touches one line.
    static let defaultSupportContact = "support@looxpassword.com"
    var supportContact: String = EmergencyKitInfo.defaultSupportContact

    /// QR "Setup Code" payload — the recovery key exactly as displayed. A new device scans
    /// it on the "Use Recovery Key" screen instead of typing. The key alone decrypts nothing
    /// without the synced vault, so this matches the safety of the manual-entry path.
    var qrPayload: String { recoveryKey }

    /// File name offered by the exporter. The `.pdf` extension must be part of the
    /// name: iOS's `fileExporter` does NOT reliably append it from the content type
    /// (an extensionless kit has no UTI — Files/QuickLook can't open it, exactly
    /// when the kit is needed). A name whose extension already matches the export
    /// content type is kept as-is, never doubled.
    var suggestedFilename: String { "Loox Emergency Kit.pdf" }

    /// Localized "Created for {name} on {date}." — omits the name clause when unknown.
    var createdLine: String {
        let date = createdAt.formatted(date: .abbreviated, time: .omitted)
        let name = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? String(format: appString("Created on %@."), date)
            : String(format: appString("Created for %@ on %@."), name, date)
    }
}
