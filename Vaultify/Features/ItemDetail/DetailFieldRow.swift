import SwiftUI
import Foundation

/// One field in the item-detail card, 1Password-style: tap anywhere to copy
/// (the row flashes the accent color and shows "Copied"), with a per-field "•••"
/// menu (Copy / Reveal / Open) and, for passwords, a strength badge.
struct DetailFieldRow: View {
    let field: DynamicField
    /// The item's 2FA secret, surfaced as a floating code in the Large Type viewer.
    var totpSecret: String? = nil
    var onChange: (DynamicField) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onUsed: () -> Void = {}
    /// Shared projections (V1.2): hide mutation affordances entirely —
    /// a "Protect…" that Face-IDs and then silently does nothing is worse
    /// than its absence. Copy/reveal/large-type stay.
    var readOnly = false
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    /// Recognizes when this field's value is one of the active persona's
    /// private-email aliases (INV-R03) — drives the PRIVATE badge + forwards-to
    /// line convention shared with the Editor.
    private var privateEmailMatch: PrivateEmailMatch? {
        PrivateEmailMatch.resolve(kind: field.kind, value: field.value, repository: env.repository)
    }

    private var normalBody: some View {
        let match = privateEmailMatch
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    fieldLabelText(field.label)
                        .vaultType(.caption).fontWeight(.medium)
                        .foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85) : theme.color(.accent))
                    if match != nil {
                        PrivateEmailBadge(onAccentBackground: copied)
                    }
                }
                valueView
                // Value already renders alias text (Controlled Reveal doesn't
                // apply here — the field isn't secret) — copy() below still
                // always copies `field.value`, i.e. the alias, never the
                // forwards-to destination shown on this line.
                if let match, !copied {
                    PrivateEmailForwardsToLine(match: match, showsStatusText: false)
                }
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
        .platformFullScreenCover(isPresented: $showLargeType) {
            // For a TOTP field, drive the grid live from the secret + show a header ring.
            LargeTypeView(text: copyValue, totpSecret: totpSecret,
                          liveTOTPSecret: field.kind == .totp ? field.value : nil)
        }
        .sheet(isPresented: $showProtect) {
            ProtectFieldSheet(field: field, onProtected: onChange)
        }
    }

    @ViewBuilder private var valueView: some View {
        if copied {
            Text(copiedFeedbackText).vaultType(.body)
        } else {
            switch field.kind {
            case .totp:
                TOTPCodeView(secret: field.value)
            case .url:
                // Website → SF, scheme greyed, domain/path in accent, tail-truncated.
                Text(urlColored(field.value)).vaultType(.body)
                    .lineLimit(1).truncationMode(.tail)
            default:
                // Secret values use MonoLisa; free-text notes stay SF. Notes
                // and revealed secrets wrap to multiple lines; other values
                // (username, etc.) stay single-line. Alias addresses are long
                // (local part + relay domain) — a smaller mono size shows them
                // whole instead of an ugly middle-cut.
                let valueFont: Font = field.kind == .multiline ? VaultType.body.font
                    : (privateEmailMatch != nil ? .vaultCode(.footnote) : .vaultCode())
                if isSecret {
                    // Controlled Reveal: glyphs resolve in place left-to-right
                    // instead of a whole-field crossfade between two views.
                    // `.textSelection` takes a concrete (non-uniform) type per
                    // branch, so the enabled/disabled cases can't share a ternary.
                    if revealed {
                        GlyphResolveText(text: field.value, isRevealed: revealed, font: valueFont)
                            .textSelection(.enabled)
                    } else {
                        GlyphResolveText(text: field.value, isRevealed: revealed, font: valueFont)
                            .textSelection(.disabled)
                    }
                } else {
                    Text(field.value)
                        .font(valueFont)
                        .lineLimit(field.kind == .multiline ? nil : 1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Always the short "Copied" — the auto-clear detail made the label long
    /// enough to wrap the row's value line, which reads as a layout glitch at
    /// the exact moment of feedback. The clear behavior itself is unchanged.
    private var copiedFeedbackText: String {
        appString("Copied")
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 10) {
            if !copied, field.kind == .password, !field.value.isEmpty {
                strengthBadge
            }
            if field.kind == .totp {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CountdownRing(remaining: TOTPGenerator.secondsRemaining(date: context.date),
                                  period: 30, onAccent: copied)
                }
            }
            // Copy feedback glyph: clipboard morphs to clipboard-check on copy —
            // an at-a-glance affordance in addition to the row's accent flash.
            CopyMorphIcon(copied: copied)
                .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.secondary))
            menu
        }
    }

    private var strengthBadge: some View {
        let strength = PasswordStrength.evaluate(field.value)
        return HStack(spacing: 5) {
            Text(strength.title).vaultType(.subhead).foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85) : theme.color(.secondary))
            Circle().fill(VaultColors.strength(strength)).frame(width: 9, height: 9)
        }
    }

    private var menu: some View {
        Menu {
            Button { copy() } label: { Label("Copy", image: Icons.copy) }
            Button { showLargeType = true } label: { Label("Large Type", image: "ic_text") }
            // TOTP renders its code live — a Reveal toggle is meaningless there.
            if isSecret, field.kind != .totp {
                Button {
                    withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) { revealed.toggle() }
                    if revealed { onUsed() }
                } label: {
                    Label(revealed ? "Conceal" : "Reveal", image: revealed ? Icons.hide : Icons.reveal)
                }
            }
            if field.kind == .url, let url = Self.normalized(field.value) {
                Button { PlatformAppearance.open(url) } label: { Label("Open Website", image: Icons.globe) }
            }
            if !field.value.isEmpty, !readOnly {
                Divider()
                Button { showProtect = true } label: { Label("Protect…", image: Icons.lock) }
            }
        } label: {
            PolarisIcon("ic_menu_horizontal", size: 17)
                .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.secondary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(copied ? theme.color(.onAccent).opacity(0.22) : VaultColors.fill))
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

    /// Color a URL: the `http://` / `https://` scheme in secondary grey, the rest
    /// (domain + path) in accent.
    private func urlColored(_ value: String) -> AttributedString {
        let schemeLength: Int
        let lower = value.lowercased()
        if lower.hasPrefix("https://") { schemeLength = 8 }
        else if lower.hasPrefix("http://") { schemeLength = 7 }
        else { schemeLength = 0 }

        var result = AttributedString()
        if schemeLength > 0 {
            var scheme = AttributedString(String(value.prefix(schemeLength)))
            scheme.foregroundColor = theme.color(.secondary)
            result.append(scheme)
        }
        var rest = AttributedString(String(value.dropFirst(schemeLength)))
        rest.foregroundColor = theme.color(.accent)
        result.append(rest)
        return result
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
