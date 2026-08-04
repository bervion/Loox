import Foundation

/// The user's answer to the onboarding iCloud Sync question.
///
/// `.notAnswered` is the starting state on purpose: nothing is preselected, and nothing
/// may leave the device until the user says yes. Onboarding used to flip
/// `iCloudSyncEnabled` on straight after vault creation, which put the first CloudKit
/// write on a three-second debounce during the name step — before any choice existed.
nonisolated enum SyncConsent: String, Equatable, CaseIterable, Sendable {
    case notAnswered
    case declined
    case granted

    /// The ONE question every onboarding CloudKit call must ask first. Only an explicit
    /// yes may put anything on the network; "not answered" is not "probably fine".
    var allowsCloudEgress: Bool { self == .granted }
}

/// Progress of the single upload the cross-device recovery promise depends on.
///
/// The recovery envelope is the recovery-KEK-wrapped Vault Key. Until it is on iCloud,
/// an Emergency Kit cannot rebuild anything on a device that does not already hold the
/// vault, no matter how carefully the user kept the printed page.
nonisolated enum RecoveryEnvelopeUpload: Equatable, Sendable {
    case notStarted
    case uploading
    case uploaded
    /// Carries the already-localized reason so the UI can name what went wrong.
    case failed(String)
}

/// What a printed Emergency Kit can actually do, and why.
///
/// The kit is not an offline backup. The recovery key unwraps the Vault Key held in this
/// installation's key bundle, or the copy of that envelope that reached iCloud. With
/// neither present the key decrypts nothing, so the honest scope turns on exactly one
/// fact: did the recovery envelope upload succeed before the incident.
nonisolated enum EmergencyKitScope: String, Equatable, CaseIterable, Sendable {
    /// Sync off, or the envelope never landed. The kit resets the master password on
    /// this installation only, and only while its vault and key bundle still exist.
    case thisInstallationOnly
    /// Sync on and the envelope confirmed on iCloud. A new device signed in to the same
    /// iCloud account can restore with the kit.
    case crossDevice

    static func resolve(consent: SyncConsent, upload: RecoveryEnvelopeUpload) -> EmergencyKitScope {
        consent.allowsCloudEgress && upload == .uploaded ? .crossDevice : .thisInstallationOnly
    }
}

/// Drives the onboarding sync question: records the answer, applies it to the settings
/// store, and — when the answer is yes — AWAITS the first recovery-envelope push so the
/// screen can say whether cross-device recovery is actually live.
///
/// Collaborators are passed per call rather than injected at init so a SwiftUI view can
/// hold this in `@State` without capturing its environment, and so tests can drive the
/// whole state machine with no CloudKit and no settings store.
@MainActor @Observable final class SyncConsentController {
    private(set) var consent: SyncConsent = .notAnswered
    private(set) var upload: RecoveryEnvelopeUpload = .notStarted

    /// What the Emergency Kit generated on this screen can honestly claim right now.
    var scope: EmergencyKitScope { EmergencyKitScope.resolve(consent: consent, upload: upload) }

    var isUploading: Bool { upload == .uploading }

    /// Failure reason, or nil while the upload is fine or was never asked for.
    var uploadFailure: String? {
        if case .failed(let reason) = upload { return reason }
        return nil
    }

    /// Keep everything local. Writes the flag off explicitly rather than relying on the
    /// default, so a user who changes their mind twice ends where they last chose.
    func decline(apply: @MainActor (Bool) -> Void) {
        consent = .declined
        upload = .notStarted
        apply(false)
    }

    /// Turn sync on and wait for the recovery envelope to land. Silent best-effort here
    /// is what let the product claim cross-device recovery it had not delivered.
    func grant(apply: @MainActor (Bool) -> Void, push: @MainActor () async throws -> Void) async {
        consent = .granted
        apply(true)
        await runPush(push)
    }

    /// Re-run the upload after a failure. Never uploads without a granted consent, so a
    /// stale retry cannot resurrect egress the user turned back off.
    func retry(push: @MainActor () async throws -> Void) async {
        guard consent.allowsCloudEgress else { return }
        await runPush(push)
    }

    private func runPush(_ push: @MainActor () async throws -> Void) async {
        upload = .uploading
        do {
            try await push()
            upload = .uploaded
        } catch {
            upload = .failed(error.localizedDescription)
        }
    }
}
