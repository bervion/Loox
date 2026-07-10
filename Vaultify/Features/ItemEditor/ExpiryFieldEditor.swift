import SwiftUI

/// Editor for the card template's "Expiry" field: payment-standard MM/YY typing (Stripe/
/// Wallet style — deliberately not a date wheel). Mirrors `DateFieldEditor`'s round-trip
/// strategy: a stored value that already matches a common expiry shape (MM/YY, MM/YYYY,
/// MM-YY) gets the formatted numeric-keypad editor; anything else (or empty, for new
/// fields) falls back to a plain text field so an unrecognized existing value is never
/// silently mangled.
struct ExpiryFieldEditor: View {
    @Binding var value: String

    var body: some View {
        if CardExpiryFormat.matchesKnownPattern(value) {
            TextField("MM/YY", text: formattedBinding)
                .vaultType(.body)
                .platformKeyboardType(.numberPad)
        } else {
            TextField("Enter value", text: $value)
                .vaultType(.body)
        }
    }

    private var formattedBinding: Binding<String> {
        Binding(
            get: { value },
            set: { value = CardExpiryFormat.autoFormat($0) }
        )
    }
}
