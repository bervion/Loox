import SwiftUI

/// Editor for the card template's "Expiry" field: payment-standard MM/YY typing (Stripe/
/// Wallet style — deliberately not a date wheel).
///
/// ONE persistent `TextField` per mode, and the mode is decided ONCE on appear — never from
/// the value mid-session. The previous version picked its branch from
/// `matchesKnownPattern(value)` on every render, so the very first typed digit ("1" matches
/// no pattern) swapped the view identity: focus died, the keyboard dismissed, and the field
/// was stuck on the unformatted branch. Mirrors `DateFieldEditor`'s round-trip intent: a
/// stored value that already looks like an expiry (or an empty new field) gets the
/// formatted numeric-keypad editor; an unrecognized legacy value stays a plain text field
/// for the whole session so it's never silently mangled.
struct ExpiryFieldEditor: View {
    @Binding var value: String

    /// Local mirror of the field text. Formatting happens in `onChange` (assign-back
    /// re-enters once, then formatted == new stops it) — the reformat-via-Binding-getter
    /// pattern drops mid-keystroke updates on iOS 17+.
    @State private var text = ""
    /// Decided once on appear; `nil` = not yet decided (first render).
    @State private var useFormatted: Bool?

    var body: some View {
        Group {
            if useFormatted ?? true {
                TextField("MM/YY", text: $text)
                    .vaultType(.body)
                    .platformKeyboardType(.numberPad)
                    .onChange(of: text) { old, new in
                        // `new == value` means text was just synced FROM storage (the
                        // onAppear seed, the reformat re-entry, or a scan fill) — running
                        // autoFormat there would mangle a stored MM/YYYY on mere open.
                        // Only user edits (text diverging from storage) format.
                        guard new != value else { return }
                        let formatted = CardExpiryFormat.autoFormat(new, previous: old)
                        if formatted != new { text = formatted }
                        value = formatted
                    }
                    // External write (camera scan fill) while the editor is mounted.
                    .onChange(of: value) { _, new in
                        if new != text { text = new }
                    }
            } else {
                TextField("Enter value", text: $value)
                    .vaultType(.body)
            }
        }
        .onAppear {
            if useFormatted == nil {
                useFormatted = CardExpiryFormat.matchesKnownPattern(value)
                text = value
            }
        }
    }
}
