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
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(env.theme.active.color(.accent).opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay(VaultIcon(meta.iconAsset, size: 22).foregroundStyle(env.theme.active.color(.accent)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.name).vaultType(.body).themedForeground().lineLimit(1)
                    Text("\(meta.ext.uppercased()), \(meta.sizeText)").vaultType(.caption).themedForeground(.secondary)
                }
                Spacer(minLength: 8)
                menu(meta)
            } else {
                Text("Attachment unavailable").vaultType(.subhead).themedForeground(.secondary)
            }
            if let error { Text(error).vaultType(.caption).foregroundStyle(VaultColors.strengthWeak) }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { preview() }
        .quickLookPreview($previewURL)
    }

    private func menu(_ meta: AttachmentMeta) -> some View {
        Menu {
            Button { preview() } label: { Label { Text("Quick Look") } icon: { VaultIcon(Icons.reveal) } }
            Button(role: .destructive) {
                env.attachmentStore.delete(meta)
                onRemove()
            } label: { Label { Text("Delete Attachment") } icon: { VaultIcon(Icons.delete) } }
        } label: {
            VaultIcon(Icons.moreHorizontal, size: 17)
                .themedForeground(.iconPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(VaultColors.fill))
                // Invisible padded hit area: the visual circle stays 30pt, the
                // tappable region meets the 44pt minimum (rule 6).
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .contentShape(Rectangle())
        }
        // Plain glyph menu — macOS would otherwise draw a bordered pull-down button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
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
