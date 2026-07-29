import SwiftUI

/// Editor for the card template's "Card Number" field: same Controlled-Reveal treatment as
/// every other `protected` single-line field in `EditorFieldRow` (masked bullets when
/// unfocused, plaintext while typing) — plus the card-specific additions: a numeric
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

    /// Local mirror of the field text — formatting happens in `onChange` (assign-back
    /// re-enters once, then stops). The previous reformat-via-Binding-getter pattern
    /// dropped mid-keystroke pushes on iOS 17+, so the grouping never appeared on device.
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("Enter card number", text: $text)
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
        .onAppear { text = PaymentCard.formattedForInput(value) }
        .onChange(of: text) { _, new in
            // Equal to the storage projection = text was just synced FROM storage
            // (onAppear seed, reformat re-entry, scan fill) — nothing to format.
            guard new != PaymentCard.formattedForInput(value) else { return }
            let formatted = PaymentCard.formattedForInput(new)
            if formatted != new { text = formatted }
            value = PaymentCard.normalizedForStorage(new)
        }
        // External write (camera scan fill) while the editor is mounted.
        .onChange(of: value) { _, new in
            let formatted = PaymentCard.formattedForInput(new)
            if text != formatted { text = formatted }
        }
    }
}

/// Network badge: a SELF-DRAWN generic mark tile (user-approved 260711) — evocative
/// colours/lettering rendered from our own SVGs in `Assets.xcassets/CardBrands`, never a
/// third-party logo asset (trademark). The tile carries its own background, so it reads on
/// any surface, including the tap-to-copy accent flash.
struct CardBrandBadge: View {
    let brand: CardBrand
    /// True while the host row is mid tap-to-copy flash (accent background). The mark tile
    /// is self-contained, so no tint swap is needed — kept so call sites stay unchanged.
    var onAccentBackground = false

    var body: some View {
        Image(brand.markAssetName)
            .resizable()
            .aspectRatio(48 / 32, contentMode: .fit)
            .frame(height: 22)
            .accessibilityLabel(Text(brand.displayName))
    }
}

extension CardBrand {
    /// Asset-catalog name of the self-drawn mark tile. Lives here (app target), not in
    /// `PaymentCard.swift` — VaultifyCore compiles into the AutoFill extension, which
    /// doesn't bundle the app's asset catalog.
    var markAssetName: String {
        "card_brand_\(rawValue.lowercased())"
    }
}
