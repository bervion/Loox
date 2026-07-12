import Foundation

/// Fill-payload extraction for the Safari web extension: the values released
/// for ONE explicit, popup-initiated fill of a single identity or card item.
///
/// SECURITY INVARIANT: this is the only read path that may release values of
/// `protected` template fields (card number, security code), and it does so
/// only at fill moment, for exactly one item, and only for the two fillable
/// categories. Level-2 (`guard2`) and SecretGuard-sealed values are never
/// released, and no `password`/`totp` kind value can ever appear in a payload
/// (this command must never become a password exfiltration channel — QuickType
/// owns login fields). Identity values additionally respect the `protected`
/// flag: a field the user chose to protect is not filled.
extension WebExtensionReader {

    /// The only item categories `getFillPayload` will ever serve.
    static let fillableCategories: Set<ItemCategory> = [.identity, .card]

    /// Values for one authorized fill, keyed by the canonical fill keys the
    /// extension's fill engine understands (`fullName`, `givenName`,
    /// `familyName`, `email`, `phone`, `address`, `ccName`, `ccNumber`,
    /// `ccExp`, `ccExpMonth`, `ccExpYear`, `ccCsc`).
    ///
    /// Throws `.forbidden` for a non-fillable category or a category mismatch
    /// between the request and the stored item (an item id learned for an
    /// identity must not unlock card secrets, and vice versa);
    /// `.itemNotFound` when the item is absent, trashed, or undecryptable.
    @MainActor
    static func fillPayload(itemId: String, category: ItemCategory,
                            store: VaultStore, key: SecureBytes) throws -> [String: String] {
        guard fillableCategories.contains(category) else { throw ReadError.forbidden }
        guard let item = decryptItem(id: itemId, store: store, key: key) else {
            throw ReadError.itemNotFound
        }
        guard item.category == category else { throw ReadError.forbidden }
        switch category {
        case .identity: return identityValues(of: item)
        default: return cardValues(of: item)
        }
    }

    // MARK: - Identity

    private static func identityValues(of item: VaultItem) -> [String: String] {
        var values: [String: String] = [:]
        if let name = identityValue(item, kind: .text, label: "Full Name") {
            values["fullName"] = name
            let split = splitFullName(name)
            if !split.given.isEmpty { values["givenName"] = split.given }
            if !split.family.isEmpty { values["familyName"] = split.family }
        }
        if let email = identityValue(item, kind: .email, label: "Email") {
            values["email"] = email
        }
        if let phone = identityValue(item, kind: .phone, label: "Phone") {
            values["phone"] = phone
        }
        // Address is label-strict: falling back to "any multiline" would dump
        // an unrelated note into a street-address input.
        if let address = identityValue(item, kind: .multiline, label: "Address",
                                       labelStrict: true) {
            values["address"] = address
        }
        return values
    }

    /// First releasable identity value of `kind`, preferring the template's
    /// stable English label. Identity fills never release protected values.
    private static func identityValue(_ item: VaultItem, kind: FieldKind,
                                      label: String, labelStrict: Bool = false) -> String? {
        let candidates = item.fields.filter {
            $0.kind == kind && !$0.isEmpty && !$0.protected && releasableForFill($0)
        }
        if let labelled = candidates.first(where: { $0.label == label }) {
            return labelled.value
        }
        return labelStrict ? nil : candidates.first?.value
    }

    /// Splits a display name for `given-name` / `family-name` targets using
    /// the WHATWG autocomplete convention (family name = last token). This is
    /// the Western order; sites asking for Vietnamese-order names usually use
    /// a single full-name field, which receives the unsplit value.
    static func splitFullName(_ fullName: String) -> (given: String, family: String) {
        let tokens = fullName.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else {
            return (fullName.trimmingCharacters(in: .whitespaces), "")
        }
        let family = tokens[tokens.count - 1]
        let given = tokens.dropLast().joined(separator: " ")
        return (given, family)
    }

    // MARK: - Card

    private static func cardValues(of item: VaultItem) -> [String: String] {
        var values: [String: String] = [:]
        if let holder = cardValue(item, kind: .text, label: "Cardholder") {
            values["ccName"] = holder
        }
        // PAN released digits-only: the fill engine regroups per target and a
        // spaced value must never trip a site's server-side digit validation.
        let digits = PaymentCard.digitsOnly(cardNumberValue(of: item))
        if digits.count >= 8, !SecretGuard.isProtected(digits) {
            values["ccNumber"] = digits
        }
        if let expiry = cardValue(item, kind: .text, label: "Expiry"),
           let parts = expiryComponents(from: expiry) {
            values["ccExpMonth"] = parts.month
            values["ccExpYear"] = parts.year4
            values["ccExp"] = "\(parts.month)/\(parts.year4.suffix(2))"
        }
        if let csc = cardValue(item, kind: .monospace, label: "Security Code"),
           (3...4).contains(PaymentCard.digitsOnly(csc).count) {
            values["ccCsc"] = PaymentCard.digitsOnly(csc)
        }
        return values
    }

    /// First releasable card value of `kind` with the template's stable label.
    /// Card fills may release `protected` values (the template protects the
    /// number and security code by design); `guard2`/SecretGuard still block.
    /// Label-strict: card subfields are positional secrets, so a fallback to
    /// "any field of that kind" could release the wrong one (PIN is `.number`
    /// and never matches any of these labels).
    private static func cardValue(_ item: VaultItem, kind: FieldKind,
                                  label: String) -> String? {
        let field = item.fields.first {
            $0.kind == kind && $0.label == label && !$0.isEmpty && releasableForFill($0)
        }
        return field?.value
    }

    /// Month + 4-digit year from any expiry shape this app has ever stored
    /// (MM/YY, MM/YYYY, MM-YY, MM-YYYY, single-digit month tolerated).
    static func expiryComponents(from raw: String) -> (month: String, year4: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(whereSeparator: { $0 == "/" || $0 == "-" })
        guard parts.count == 2,
              parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
              let month = Int(parts[0]), (1...12).contains(month) else { return nil }
        let yearRaw = String(parts[1])
        guard yearRaw.count == 2 || yearRaw.count == 4, let year = Int(yearRaw) else {
            return nil
        }
        let year4 = yearRaw.count == 2 ? String(2000 + year) : yearRaw
        return (String(format: "%02d", month), year4)
    }

    // MARK: - Shared

    /// Hard floor for ANY fill release: never a secret kind, never a Level-2
    /// sealed value, never an opaque SecretGuard payload.
    private static func releasableForFill(_ field: DynamicField) -> Bool {
        field.kind != .password && field.kind != .totp
            && field.guard2 != true && !SecretGuard.isProtected(field.value)
    }

    @MainActor
    private static func decryptItem(id: String, store: VaultStore,
                                    key: SecureBytes) -> VaultItem? {
        let records = store.allRecords().filter {
            $0.trashedAt == nil && $0.deletedAt == nil && $0.archived == false
        }
        guard let record = records.first(where: { $0.id == id }),
              let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        return VaultItem(id: record.id, category: secret.category,
                         title: secret.title, fields: secret.fields)
    }
}
