import Foundation

/// A vault record whose sealed payload failed to open this session.
///
/// The repository never silently skips a record: every failure is captured
/// here (record ID and error class only — NEVER decrypted content or error
/// descriptions, which can embed payload fragments) so the UI can show an
/// honest recovery state instead of a mysteriously missing item. The original
/// ciphertext stays untouched in the store; a later build, key fix, or sync
/// repair can still recover it.
nonisolated struct QuarantinedRecord: Identifiable, Equatable, Sendable {
    /// Coarse failure class. Deliberately small: distinguishing corruption from
    /// an unsupported-newer payload from a transient key failure is what the
    /// recovery UI needs — anything finer risks leaking payload detail.
    enum FailureClass: String, Sendable {
        /// AEAD open failed — wrong key epoch or corrupt ciphertext.
        case decryptFailed
        /// Decrypted fine but the JSON payload did not decode — usually a
        /// record written by a newer, incompatible build.
        case decodeFailed
    }

    let id: String
    let failure: FailureClass
    /// Record-level plaintext timestamp; safe to surface.
    let updatedAt: Date
}
