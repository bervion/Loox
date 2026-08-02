import Foundation
import SwiftData

/// Read-only, metadata-scoped vault access for the Safari web extension.
///
/// SECURITY INVARIANT: everything returned by this type crosses the native→JS
/// bridge. List queries surface metadata only — titles, usernames, card brand
/// plus last-4. Secrets (passwords, TOTP, full card numbers, any `protected`
/// or Level-2 field value) never leave this file's decrypt scope.
/// `copyableValue` releases exactly one field value, and only for whitelisted
/// non-secret kinds on unprotected fields — enforced here, natively, so the
/// popup hiding a button is never the security boundary.
nonisolated enum WebExtensionReader {

    struct LoginSummary: Sendable, Equatable {
        let id: String
        let title: String
        let username: String
    }

    struct IdentitySummary: Sendable, Equatable {
        let id: String
        let title: String
    }

    struct CardSummary: Sendable, Equatable {
        let id: String
        let title: String
        let brand: String
        let last4: String
    }

    struct ItemLists: Sendable {
        var logins: [LoginSummary]
        var identities: [IdentitySummary]
        var cards: [CardSummary]
    }

    enum ReadError: Error, Equatable { case itemNotFound, forbidden }

    /// Field kinds whose values may be released for copy. Everything else —
    /// secret kinds (`FieldKind.isSecret`) and any field flagged protected or
    /// Level-2 — is rejected with `.forbidden`.
    static let copyableKinds: Set<FieldKind> = [.username, .email, .text]

    /// Items relevant to the popup for one https host: logins scoped to the
    /// host via the strict matcher below; identities and cards are global
    /// lists (they carry no website field, so host scoping does not apply).
    @MainActor
    static func itemsMatching(host: String, store: VaultStore, key: SecureBytes) -> ItemLists {
        var lists = ItemLists(logins: [], identities: [], cards: [])
        for record in liveRecords(in: store) {
            guard let item = decrypt(record, key: key) else { continue }
            // The resolver is the single authority: identity/card templates
            // claim their fill surface, login-capable templates claim the
            // host-scoped listing, and everything else (developer secrets,
            // unknown kinds) is invisible to the extension.
            let capabilities = ItemCapabilityResolver.capabilities(for: item)
            if capabilities.identityFill {
                lists.identities.append(IdentitySummary(id: item.id, title: item.title))
            } else if capabilities.cardFill {
                lists.cards.append(cardSummary(for: item))
            } else if capabilities.safariLoginListing {
                guard item.passwordField != nil,
                      hostMatches(host, item: item) else { continue }
                let username = VaultReader.username(from: item) ?? ""
                lists.logins.append(LoginSummary(id: item.id, title: item.title,
                                                 username: username))
            }
        }
        lists.logins.sort { byTitle($0.title, $1.title) }
        lists.identities.sort { byTitle($0.title, $1.title) }
        lists.cards.sort { byTitle($0.title, $1.title) }
        return lists
    }

    /// The single value released for an explicit copy action. Throws
    /// `.forbidden` for any non-whitelisted kind or protected/Level-2 field;
    /// `.itemNotFound` when the item or a non-empty field of `kind` is absent.
    @MainActor
    static func copyableValue(itemId: String, kind: FieldKind,
                              store: VaultStore, key: SecureBytes) throws -> String {
        guard copyableKinds.contains(kind), !kind.isSecret else { throw ReadError.forbidden }
        guard let record = liveRecords(in: store).first(where: { $0.id == itemId }),
              let item = decrypt(record, key: key) else { throw ReadError.itemNotFound }
        let candidates = item.fields.filter { $0.kind == kind && !$0.isEmpty }
        guard !candidates.isEmpty else { throw ReadError.itemNotFound }
        guard let field = candidates.first(where: { releasable($0) }) else {
            throw ReadError.forbidden
        }
        return field.value
    }

    /// Strict host relevance for the popup list: exact host or a dot-boundary
    /// subdomain relationship (either direction). Deliberately NOT the OS
    /// AutoFill matcher, whose trailing substring clause would let a lookalike
    /// host such as `evilgoogle.com` surface the `google.com` login — a popup
    /// listing on such a page both leaks the username into extension JS and
    /// lends the phishing page legitimacy. Mirrors the conservative shape of
    /// `matchesRelyingParty`.
    static func hostMatches(_ host: String, item: VaultItem) -> Bool {
        item.autofillHosts.contains { HostMatch.related(host, $0) }
    }

    // MARK: - Internals

    /// A field value may be released only when it is unprotected, not sealed
    /// under a Level-2 code, and not carrying an opaque SecretGuard payload.
    private static func releasable(_ field: DynamicField) -> Bool {
        !field.protected && field.guard2 != true && !SecretGuard.isProtected(field.value)
    }

    @MainActor
    private static func liveRecords(in store: VaultStore) -> [ItemRecord] {
        store.allRecords().filter {
            $0.trashedAt == nil && $0.deletedAt == nil && $0.archived == false
        }
    }

    /// Brand + last-4 masking. The full number stays inside this function; a
    /// Level-2-sealed number is skipped entirely (undecryptable here) and the
    /// summary degrades to title-only.
    private static func cardSummary(for item: VaultItem) -> CardSummary {
        let number = cardNumberValue(of: item)
        // SecretGuard check on the RAW value: a sealed payload is a tagged
        // base64 blob whose stray digits must not surface as brand or last-4.
        guard !SecretGuard.isProtected(number) else {
            return CardSummary(id: item.id, title: item.title, brand: "", last4: "")
        }
        let digits = PaymentCard.digitsOnly(number)
        let brand = PaymentCard.brand(for: digits)?.displayName ?? ""
        let last4 = digits.count >= 4 ? String(digits.suffix(4)) : ""
        return CardSummary(id: item.id, title: item.title, brand: brand, last4: last4)
    }

    /// The card's PAN field: the template's stable English "Card Number" label
    /// first; otherwise the first monospace field long enough to be a PAN —
    /// the length floor keeps a 4-digit security code (Amex CID) from ever
    /// being mistaken for the number and leaking its digits as "last-4".
    /// Internal (not private) because the fill-payload path reuses the same
    /// PAN resolution when releasing the number for an authorized card fill.
    static func cardNumberValue(of item: VaultItem) -> String {
        let candidates = item.fields.filter { $0.kind == .monospace && $0.guard2 != true }
        if let labelled = candidates.first(where: { $0.label == "Card Number" }) {
            return labelled.value
        }
        let panLike = candidates.first { PaymentCard.digitsOnly($0.value).count >= 8 }
        return panLike?.value ?? ""
    }

    private static func byTitle(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    /// Minimal decrypt for listing/matching: id, category, title, fields,
    /// plus the semantic identity the capability resolver keys off.
    private static func decrypt(_ record: ItemRecord, key: SecureBytes) -> VaultItem? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        var item = VaultItem(id: record.id, category: secret.category,
                             title: secret.title, fields: secret.fields)
        item.unknownCategoryRaw = secret.unknownCategoryRaw
        item.semantics = secret.semantics
        return item
    }
}
