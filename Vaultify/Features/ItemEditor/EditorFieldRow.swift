import SwiftUI

/// Editable row for one dynamic field: label, value (kind-appropriate keyboard),
/// a type/protection menu, and a generate action for password fields.
struct EditorFieldRow: View {
    @Binding var field: DynamicField
    var onScanTOTP: () -> Void = {}
    @State private var reveal = false
    @FocusState private var valueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Label", text: localizedLabel)
                    .font(.caption)
                    .themedForeground(.secondary)
                    .textInputAutocapitalization(.words)
                Spacer()
                Menu {
                    Picker("Type", selection: $field.kind) {
                        ForEach(FieldKind.allCases, id: \.self) { kind in
                            Label { Text(kind.title) } icon: { PolarisIcon(kind.iconAsset) }.tag(kind)
                        }
                    }
                    Toggle(isOn: $field.protected) { Text("Hidden value") }
                } label: {
                    PolarisIcon(field.kind.iconAsset, size: 18).themedForeground(.secondary)
                }
            }
            valueEditor
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var valueEditor: some View {
        if field.isExtraProtected {
            HStack(spacing: 6) {
                PolarisIcon(Icons.lockFill, size: 14).themedForeground(.secondary)
                Text("Protected — manage in the item view").font(.caption).themedForeground(.secondary)
            }
        } else {
            kindEditor
        }
    }

    @ViewBuilder private var kindEditor: some View {
        switch field.kind {
        case .multiline:
            TextField(valuePlaceholder, text: $field.value, axis: .vertical)
                .lineLimit(2...6)
        case .password, .totp:
            HStack {
                Group {
                    if reveal { TextField(valuePlaceholder, text: $field.value) }
                    else { SecureField(valuePlaceholder, text: $field.value) }
                }
                .focused($valueFocused)
                .font(.vaultCode())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { reveal.toggle() } label: {
                    PolarisIcon(reveal ? Icons.hide : Icons.reveal, size: 18).themedForeground(.secondary)
                }
                .buttonStyle(.plain)
                if field.kind == .totp {
                    Button(action: onScanTOTP) {
                        PolarisIcon(Icons.camera, size: 18).foregroundStyle(Color.accentColor)
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
                Text(AttachmentMeta.decode(field.value)?.name ?? "Attachment").font(.subheadline).lineLimit(1)
                Spacer()
                if let meta = AttachmentMeta.decode(field.value) {
                    Text(meta.sizeText).font(.caption).themedForeground(.secondary)
                }
            }
        default:
            TextField(valuePlaceholder, text: $field.value)
                .font(.body)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
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

    private var keyboardType: UIKeyboardType {
        switch field.kind {
        case .email: return .emailAddress
        case .url: return .URL
        case .number: return .numberPad
        default: return .default
        }
    }

    private var autocapitalization: TextInputAutocapitalization {
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
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 7)
            .modifier(GenerateChipSurface())
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
        if #available(iOS 26, *), !reduceTransparency {
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
