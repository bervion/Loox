import SwiftUI

/// Editable row for one dynamic field: label, value (kind-appropriate keyboard),
/// a type/protection menu, and a generate action for password fields.
struct EditorFieldRow: View {
    @Binding var field: DynamicField
    var onScanTOTP: () -> Void = {}
    /// The owning item's category — only used to scope the card-specific editors (Card
    /// Number/Expiry/Security Code/PIN) below to genuine `.card` items, via label+kind
    /// match. Defaults to `.custom` (never matches those labels) so every existing call
    /// site that doesn't pass it explicitly (Login's Credentials/Custom sections) is
    /// unaffected.
    var category: ItemCategory = .custom
    /// The card's Card Number value (if any), so the Security Code editor can resolve the
    /// CVV length from the sibling field's brand (Amex: 4 digits, else 3).
    var siblingCardNumber: String? = nil
    @FocusState private var valueFocused: Bool
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    #else
    // macOS has no `editMode` environment (no list edit mode) → never "editing".
    private var isEditing: Bool { false }
    #endif

    var body: some View {
        // The field's kind is fixed at creation (chosen from the Add Field popup) — no
        // in-row type switcher or type icon. Just the (editable) label + the value.
        VStack(alignment: .leading, spacing: 6) {
            TextField("Label", text: localizedLabel)
                .vaultType(.caption)
                .themedForeground(.secondary)
                .platformAutocapitalization(.words)
            valueEditor
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var valueEditor: some View {
        if field.isExtraProtected {
            HStack(spacing: 6) {
                PolarisIcon(Icons.lockFill, size: 14).themedForeground(.secondary)
                Text("Protected. Manage in the item view").vaultType(.caption).themedForeground(.secondary)
            }
        } else {
            kindEditor
        }
    }

    @ViewBuilder private var kindEditor: some View {
        switch field.kind {
        // A protected multiline value (SSH Private Key, Recovery Codes) gets its own
        // masked-editing treatment (Controlled Reveal) — checked before the plain
        // `.multiline` case below so non-protected multiline fields (Note, Address,
        // Public Key) keep the always-visible editor.
        case .multiline where field.protected:
            MaskedMultilineFieldEditor(value: $field.value, placeholder: valuePlaceholder)
        case .multiline:
            TextField(valuePlaceholder, text: $field.value, axis: .vertical)
                .lineLimit(2...6)
        case .date:
            DateFieldEditor(value: $field.value)
        // Card-specific editors, scoped to genuine `.card` items via label+kind match
        // (template labels are stable English source strings — see `ItemCategory` — but
        // the label row is user-editable and DISPLAYS a translation, so a label that got
        // rewritten as its VI translation must still match; see `CardTemplateLabel`).
        // Checked before the generic `protected` case below so Card Number/Security Code
        // (both `.monospace`, `protected: true`) get the card-aware treatment instead.
        case .monospace where category == .card && CardTemplateLabel.matches(field.label, english: "Card Number"):
            CardNumberFieldEditor(value: $field.value)
        case .text where category == .card && CardTemplateLabel.matches(field.label, english: "Expiry"):
            ExpiryFieldEditor(value: $field.value)
        case .monospace where category == .card && CardTemplateLabel.matches(field.label, english: "Security Code"):
            CardCodeFieldEditor(value: $field.value, maxLength: cvvLength, placeholder: valuePlaceholder)
        case .number where category == .card && CardTemplateLabel.matches(field.label, english: "PIN"):
            CardCodeFieldEditor(value: $field.value, maxLength: 6, placeholder: valuePlaceholder)
        // Any `protected` single-line value (password/TOTP, plus template fields sealed at rest
        // like Card Number, Security Code, ID Number) shares the same controlled-reveal
        // treatment: masked bullets when unfocused, MonoLisa plaintext only while the user is
        // actively typing. Storage encryption without matching on-screen masking would leave a
        // sensitive value visible the whole time it's being edited — this generalizes the
        // password/TOTP-only masking that existed before to every `protected` kind.
        case _ where field.protected:
            HStack {
                // One persistent TextField keeps the keyboard focus stable (swapping
                // TextField↔SecureField drops first responder). It shows plaintext only while
                // focused; when blurred a bullet overlay masks the value. No reveal toggle.
                ZStack(alignment: .leading) {
                    TextField(valuePlaceholder, text: $field.value)
                        .focused($valueFocused)
                        // MonoLisa for a typed secret value; SF for the empty
                        // placeholder and for TOTP secrets.
                        .font(field.value.isEmpty || field.kind == .totp ? VaultType.body.font : .vaultCode())
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .opacity(showsPlaintext ? 1 : 0)
                    if !showsPlaintext {
                        // Fixed 16 bullets, identical for password + TOTP, matching the detail
                        // view's SpoilerText (same count + `.vaultCode()` size) so the mask is
                        // consistent and never leaks the real length.
                        Text(maskedValue)
                            .font(.vaultCode())
                            .themedForeground(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { valueFocused = true }
                            .accessibilityHidden(true)
                    }
                }
                // Hide the scan-QR button while reordering (edit mode). Large glyph + a full
                // 44pt hit target so it's easy to tap.
                if field.kind == .totp && !isEditing {
                    Button(action: onScanTOTP) {
                        PolarisIcon(Icons.scanCode, size: 26)
                            .foregroundStyle(Color.accentColor)
                            // Trailing-align the glyph inside the 44pt hit target so it sits at
                            // the row's right edge (lined up with the passkey glyph below), while
                            // the tap area still extends left.
                            .frame(width: Metric.hitMin, height: Metric.hitMin, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Publish this field's frame (only while the password field is focused) so the
            // editor can float the "generate" bubble over the whole table at this anchor.
            // Drawing it at Form level escapes the row-cell clipping an in-row overlay hits.
            .anchorPreference(key: GenerateChipAnchorKey.self, value: .bounds) { anchor in
                field.kind == .password && valueFocused
                    ? GenerateChipAnchor(fieldID: field.id, bounds: anchor) : nil
            }
        case .fileRef:
            HStack(spacing: 8) {
                PolarisIcon(AttachmentMeta.decode(field.value)?.iconAsset ?? "ic_attachment", size: 18)
                    .foregroundStyle(Color.accentColor)
                Text(AttachmentMeta.decode(field.value)?.name ?? "Attachment").vaultType(.body).lineLimit(1)
                Spacer()
                if let meta = AttachmentMeta.decode(field.value) {
                    Text(meta.sizeText).vaultType(.caption).themedForeground(.secondary)
                }
            }
        default:
            TextField(valuePlaceholder, text: $field.value)
                .vaultType(.body)
                .platformKeyboardType(keyboardType)
                .platformAutocapitalization(autocapitalization)
                .autocorrectionDisabled(noAutocorrect)
        }
    }

    /// Shows the label localized to the in-app language (known template labels resolve via
    /// the catalog; custom labels pass through). Editing writes the typed text back verbatim,
    /// so storage keeps the stable English source until the user customizes it.
    private var localizedLabel: Binding<String> {
        Binding(
            get: { appLabel(field.label) },
            set: { field.label = $0 }
        )
    }

    /// Plaintext shows only while the secret field is being edited. Empty fields stay plain so
    /// the placeholder is visible and the row is tappable to start typing.
    private var showsPlaintext: Bool { valueFocused || field.value.isEmpty }

    /// Bullet-masked rendering shown when the secret field isn't focused. Capped so a long
    /// secret can't overflow the row.
    private var maskedValue: String { String(repeating: "•", count: 16) }

    /// Security Code (CVV) length resolved from the sibling Card Number's detected brand
    /// (Amex: 4 digits, everything else including an unresolved brand: 3).
    private var cvvLength: Int {
        siblingCardNumber.flatMap { PaymentCard.brand(for: $0)?.cvvLength } ?? 4
    }

    /// Field-specific value placeholder (e.g. password → "Enter password") instead of a
    /// generic "Value", so the empty field hints what to type.
    private var valuePlaceholder: LocalizedStringKey {
        switch field.kind {
        case .password: return "Enter password"
        case .username: return "Enter username"
        case .url: return "Enter website"
        case .email: return "Enter email"
        case .totp: return "Enter key or scan QR"
        case .number: return "Enter number"
        default: return "Enter value"
        }
    }

    private var keyboardType: PlatformKeyboardType {
        switch field.kind {
        case .email: return .emailAddress
        case .url: return .url
        case .number: return .numberPad
        default: return .default
        }
    }

    private var autocapitalization: PlatformAutocapitalization {
        switch field.kind {
        case .email, .url, .username, .monospace: return .never
        default: return .sentences
        }
    }

    private var noAutocorrect: Bool {
        switch field.kind {
        case .email, .url, .username, .monospace, .number: return true
        default: return false
        }
    }
}

// MARK: - Floating generate bubble (drawn at Form level via preference anchor)

/// The password field's frame + id, published while it's focused so the editor can float the
/// generate bubble at this anchor (over the table, not clipped by the row cell).
struct GenerateChipAnchor: Equatable {
    let fieldID: String
    let bounds: Anchor<CGRect>
}

struct GenerateChipAnchorKey: PreferenceKey {
    static let defaultValue: GenerateChipAnchor? = nil
    static func reduce(value: inout GenerateChipAnchor?, nextValue: () -> GenerateChipAnchor?) {
        value = nextValue() ?? value
    }
}

/// Floating Liquid Glass "generate" bubble. Tight icon↔text spacing. Foreground is the accent
/// in light mode, but a neutral (primary/white) in dark mode — the accent blue sinks into the
/// translucent glass on dark, whereas white reads cleanly.
struct GenerateChip: View {
    let action: () -> Void
    @Environment(AppEnvironment.self) private var env

    private var foreground: Color {
        let theme = env.theme.active
        return theme.isDark ? Color(rgb: theme.primaryText) : Color(rgb: theme.accent)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PolarisIcon(Icons.magic, size: 13)
                Text("Generate strong password")
                    .vaultType(.caption).fontWeight(.semibold)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .modifier(GenerateChipSurface())
            // Whole capsule (incl. padding) is the tap target — not just the text glyphs.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .elevation(.level2)
    }
}

/// Liquid Glass capsule surface for the floating generate chip. Project glass guard
/// (`#if compiler(>=6.2)` + `#available` + Reduce-Transparency). Neutral hairline (not accent)
/// so the chip outline stays clean in both light and dark. Fallback: material capsule.
private struct GenerateChipSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = Capsule()
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        #else
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        #endif
    }
}

/// Matches a stored card-template field label against its stable English source AND that
/// source's catalog translation in every language the app ships. The editor's label row is
/// a user-editable `TextField` whose getter shows the TRANSLATION — one keystroke in it (or
/// any writeback) persists the translated string, and an exact-English match would then
/// silently drop the whole card treatment (grouping, MM/YY, digit caps).
nonisolated enum CardTemplateLabel {
    /// Languages the string catalog ships. A new app language must be added here so a
    /// label saved as that language's translation keeps matching.
    private static let locales = [Locale(identifier: "en"), Locale(identifier: "vi")]

    static func matches(_ stored: String, english: String) -> Bool {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        if trimmed == english { return true }
        return locales.contains { locale in
            var resource = LocalizedStringResource(String.LocalizationValue(stringLiteral: english))
            resource.locale = locale
            return String(localized: resource) == trimmed
        }
    }
}
