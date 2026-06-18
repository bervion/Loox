import SwiftUI
import UIKit

/// One field in the item-detail card, 1Password-style: tap anywhere to copy
/// (the row flashes the accent color and shows "Copied"), with a per-field "•••"
/// menu (Copy / Reveal / Open) and, for passwords, a strength badge.
struct DetailFieldRow: View {
    let field: DynamicField
    var onChange: (DynamicField) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onUsed: () -> Void = {}
    @Environment(AppEnvironment.self) private var env
    @State private var copied = false
    @State private var revealed = false
    @State private var showLargeType = false
    @State private var showProtect = false

    private var theme: AppTheme { env.theme.active }
    private var isSecret: Bool { field.protected || field.kind.isSecret }

    private var copyValue: String {
        if field.kind == .totp { return TOTPGenerator.code(forStoredValue: field.value) ?? field.value }
        return field.value
    }

    var body: some View {
        if field.isExtraProtected {
            ProtectedFieldRow(field: field, onChange: onChange, onUsed: onUsed)
        } else if field.kind == .fileRef {
            AttachmentFieldRow(field: field, onRemove: onRemove)
        } else {
            normalBody
        }
    }

    private var normalBody: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                fieldLabelText(field.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85) : theme.color(.accent))
                valueView
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(copied ? theme.color(.accent) : Color.clear)
        .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.primary))
        .contentShape(.rect)
        .onTapGesture { copy() }
        .animation(.easeOut(duration: 0.18), value: copied)
        .fullScreenCover(isPresented: $showLargeType) {
            LargeTypeView(text: copyValue)
        }
        .sheet(isPresented: $showProtect) {
            ProtectFieldSheet(field: field, onProtected: onChange)
        }
    }

    @ViewBuilder private var valueView: some View {
        if copied {
            Text("Copied").font(.body)
        } else {
            switch field.kind {
            case .totp:
                TOTPCodeView(secret: field.value)
            case .url:
                Text(field.value).font(.body).foregroundStyle(theme.color(.accent))
                    .lineLimit(1).truncationMode(.middle)
            default:
                if isSecret && !revealed {
                    SpoilerText(text: field.value)
                } else {
                    Text(field.value)
                        .font(.body)
                        .lineLimit(field.kind == .multiline ? nil : 1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 10) {
            if !copied, field.kind == .password, !field.value.isEmpty {
                strengthBadge
            }
            if field.kind == .totp {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CountdownRing(remaining: TOTPGenerator.secondsRemaining(date: context.date), period: 30)
                }
            }
            menu
        }
    }

    private var strengthBadge: some View {
        let strength = PasswordStrength.evaluate(field.value)
        return HStack(spacing: 5) {
            Text(strength.title).font(.subheadline).foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85) : theme.color(.secondary))
            Circle().fill(VaultColors.strength(strength)).frame(width: 9, height: 9)
        }
    }

    private var menu: some View {
        Menu {
            Button { copy() } label: { Label("Copy", image: Icons.copy) }
            Button { showLargeType = true } label: { Label("Large Type", image: "ic_text") }
            if isSecret {
                Button {
                    withAnimation { revealed.toggle() }
                    if revealed { onUsed() }
                } label: {
                    Label(revealed ? "Conceal" : "Reveal", image: revealed ? Icons.hide : Icons.reveal)
                }
            }
            if field.kind == .url, let url = Self.normalized(field.value) {
                Button { UIApplication.shared.open(url) } label: { Label("Open Website", image: Icons.globe) }
            }
            if !field.value.isEmpty {
                Divider()
                Button { showProtect = true } label: { Label("Protect…", image: Icons.lock) }
            }
        } label: {
            PolarisIcon("ic_menu_horizontal", size: 17)
                .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.secondary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(copied ? theme.color(.onAccent).opacity(0.22) : VaultColors.fill))
        }
    }

    private func copy() {
        guard !copied, !field.value.isEmpty else { return }
        env.clipboard.copy(copyValue, label: field.label, sensitive: isSecret || field.kind == .totp)
        onUsed()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { copied = false }
        }
    }

    static func normalized(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.contains("://") ? URL(string: trimmed) : URL(string: "https://\(trimmed)")
    }
}
