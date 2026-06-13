import SwiftUI
import QuickLook

/// Detail row for a `.fileRef` attachment: shows name + type + size; tap to
/// preview (QuickLook, with its built-in share), menu to delete. Bytes are
/// decrypted on demand to a protected temp file.
struct AttachmentFieldRow: View {
    let field: DynamicField
    let onRemove: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var previewURL: URL?
    @State private var error: String?

    private var meta: AttachmentMeta? { AttachmentMeta.decode(field.value) }

    var body: some View {
        HStack(spacing: 12) {
            if let meta {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay(PolarisIcon(meta.iconAsset, size: 22).foregroundStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.name).font(.body).lineLimit(1)
                    Text("\(meta.ext.uppercased()) · \(meta.sizeText)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                menu(meta)
            } else {
                Text("Attachment unavailable").font(.subheadline).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(VaultColors.strengthWeak) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { preview() }
        .quickLookPreview($previewURL)
    }

    private func menu(_ meta: AttachmentMeta) -> some View {
        Menu {
            Button { preview() } label: { Label("Quick Look", image: Icons.reveal) }
            Button(role: .destructive) {
                env.attachmentStore.delete(meta)
                onRemove()
            } label: { Label("Delete Attachment", image: Icons.delete) }
        } label: {
            PolarisIcon("ic_menu_horizontal", size: 17)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
    }

    private func preview() {
        guard let meta else { return }
        do {
            previewURL = try env.attachmentStore.decryptToTemp(meta)
        } catch {
            self.error = appString("Couldn’t open attachment.")
        }
    }
}
