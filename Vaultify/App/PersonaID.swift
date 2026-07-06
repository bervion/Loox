import Foundation

/// Identifies the identity a per-identity preference belongs to.
///
/// Personas are not a first-class model yet, so device-local preferences that
/// will eventually be keyed per identity use a single shared bucket for now.
/// When personas arrive, call sites pass the active persona's id instead of
/// `placeholder`; the storage shape (a `[personaID: value]` map) is unchanged,
/// so no migration is needed.
enum PersonaID {
    /// The single-bucket key used until real personas exist.
    static let placeholder = "__default__"
}
