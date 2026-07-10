import SwiftUI

/// Editor for the card template's "Card Number" field: same Controlled-Reveal treatment as
/// every other `protected` single-line field in `EditorFieldRow` (masked bullets when
/// unfocused, MonoLisa plaintext while typing) — plus the card-specific additions: a numeric
/// keypad, brand-aware digit grouping as-you-type, a trailing brand badge, and a subtle Luhn
/// warning that never blocks saving. Storage (`value`) always holds digits only; the space
/// grouping is display-only.
struct CardNumberFieldEditor: View {
    @Binding var value: String
    @FocusState private var focused: Bool

    private var digits: String { PaymentCard.digitsOnly(value) }
    private var brand: CardBrand? { PaymentCard.brand(for: digits) }
    private var showsPlaintext: Bool { focused || value.isEmpty }

    /// Only flagged once the digit count reaches the resolved brand's minimum real-world
    /// PAN length (or 16 when the brand is unresolved) — a partial number never warns.
    private var showsLuhnHint: Bool {
        guard !digits.isEmpty else { return false }
        let minLength = brand?.minDigits ?? 16
        return digits.count >= minLength && !PaymentCard.isLuhnValid(digits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("Enter card number", text: formattedBinding)
                        .focused($focused)
                        .font(value.isEmpty ? VaultType.body.font : .vaultCode())
                        .platformKeyboardType(.numberPad)
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .opacity(showsPlaintext ? 1 : 0)
                    if !showsPlaintext {
                        Text(String(repeating: "•", count: 16))
                            .font(.vaultCode())
                            .themedForeground(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { focused = true }
                            .accessibilityHidden(true)
                    }
                }
                // Shown regardless of focus/mask state — the network name doesn't leak the
                // secret, and knowing it (VISA vs AMEX) is useful even while concealed.
                if let brand {
                    CardBrandBadge(brand: brand)
                }
            }
            if showsLuhnHint {
                Text("Check the card number")
                    .vaultType(.caption)
                    .themedForeground(.secondary)
            }
        }
    }

    /// Displays the brand-grouped, spaced representation while editing; writes back
    /// digits-only (capped to the resolved brand's max length) into storage on every
    /// keystroke — a simple "reformat on change" approach, acceptable for a plain `TextField`.
    private var formattedBinding: Binding<String> {
        Binding(
            get: { PaymentCard.formattedForInput(value) },
            set: { value = PaymentCard.normalizedForStorage($0) }
        )
    }
}

/// TEXT-only network badge (no logo assets — third-party marks are trademarked). Mirrors
/// `PrivateEmailBadge`'s capsule chrome so both "recognized value" badges read consistently.
struct CardBrandBadge: View {
    let brand: CardBrand
    /// True while the host row is mid tap-to-copy flash (accent background) — matches
    /// `PrivateEmailBadge`'s on-accent tint swap.
    var onAccentBackground = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        Text(brand.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onAccentBackground ? theme.color(.onAccent) : theme.color(.accent))
            .lineLimit(1)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 1)
            .background(onAccentBackground ? theme.color(.onAccent).opacity(0.22) : theme.color(.accentSoft),
                       in: Capsule())
    }
}
