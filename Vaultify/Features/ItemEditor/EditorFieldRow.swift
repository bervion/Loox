import SwiftUI

/// Editable row for one dynamic field: label, value (kind-appropriate keyboard),
/// a type/protection menu, and a generate action for password fields.
struct EditorFieldRow: View {
    @Binding var field: DynamicField
    let onGenerate: () -> Void
    var onScanTOTP: () -> Void = {}
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Label", text: $field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    PolarisIcon(field.kind.iconAsset, size: 18).foregroundStyle(.secondary)
                }
            }
            valueEditor
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var valueEditor: some View {
        if field.isExtraProtected {
            HStack(spacing: 6) {
                PolarisIcon(Icons.lockFill, size: 14).foregroundStyle(.secondary)
                Text("Protected — manage in the item view").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            kindEditor
        }
    }

    @ViewBuilder private var kindEditor: some View {
        switch field.kind {
        case .multiline:
            TextField("Value", text: $field.value, axis: .vertical)
                .lineLimit(2...6)
        case .password, .totp:
            HStack {
                Group {
                    if reveal { TextField("Value", text: $field.value) }
                    else { SecureField("Value", text: $field.value) }
                }
                .font(.vaultMono())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { reveal.toggle() } label: {
                    PolarisIcon(reveal ? Icons.hide : Icons.reveal, size: 18).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if field.kind == .password {
                    Button(action: onGenerate) {
                        PolarisIcon(Icons.magic, size: 18).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                if field.kind == .totp {
                    Button(action: onScanTOTP) {
                        PolarisIcon(Icons.camera, size: 18).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .fileRef:
            HStack(spacing: 8) {
                PolarisIcon(AttachmentMeta.decode(field.value)?.iconAsset ?? "ic_attachment", size: 18)
                    .foregroundStyle(Color.accentColor)
                Text(AttachmentMeta.decode(field.value)?.name ?? "Attachment").font(.subheadline).lineLimit(1)
                Spacer()
                if let meta = AttachmentMeta.decode(field.value) {
                    Text(meta.sizeText).font(.caption).foregroundStyle(.secondary)
                }
            }
        default:
            TextField("Value", text: $field.value)
                .font(field.kind.isMonospaced ? .vaultMono() : .body)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(noAutocorrect)
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
