import SwiftUI
import Foundation

/// One field in the item-detail card, 1Password-style: tap anywhere to copy
/// (the row flashes the accent color and shows "Copied"), with a per-field "•••"
/// menu (Copy / Reveal / Open) and, for passwords, a strength badge.
struct DetailFieldRow: View {
    let field: DynamicField
    /// The owning item's category — only used to scope the Card Number field's
    /// grouped-display + brand-badge + digits-only-copy treatment to genuine `.card`
    /// items. Defaults to `.custom` (never matches), so every other caller is unaffected.
    var category: ItemCategory = .custom
    /// The item's 2FA secret, surfaced as a floating code in the Large Type viewer.
    var totpSecret: String? = nil
    var onChange: (DynamicField) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onUsed: () -> Void = {}
    /// Shared projections (V1.2): hide mutation affordances entirely —
    /// a "Protect…" that Face-IDs and then silently does nothing is worse
    /// than its absence. Copy/reveal/large-type stay.
    var readOnly = false
    /// Action-bound device-owner re-auth before REVEAL or COPY of this value
    /// (capability resolver `revealAuthorization == .reauthenticate` — SSH
    /// private keys, API tokens). Concealing never needs authorization.
    var requiresReauth = false
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false
    @State private var revealed = false
    @State private var concealTask: Task<Void, Never>?
    @State private var showLargeType = false
    @State private var showProtect = false

    private var theme: AppTheme { env.theme.active }
    private var isSecret: Bool { field.protected || field.kind.isSecret }

    /// Whether this is the card template's Card Number field — the one field that gets
    /// digit grouping + a brand badge on the detail screen.
    private var isCardNumber: Bool {
        category == .card && field.kind == .monospace && field.label == "Card Number"
    }

    private var copyValue: String {
        if field.kind == .totp { return TOTPGenerator.code(forStoredValue: field.value) ?? field.value }
        // Defensive: storage is written digits-only by `CardNumberFieldEditor`, but a
        // legacy value (typed before this feature existed) could still hold spaces.
        if isCardNumber { return PaymentCard.digitsOnly(field.value) }
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

    /// Notes opt out of tap-to-copy: a long note is for READING (and its links
    /// for tapping) — accidental flashes on every touch made it unusable.
    /// Copy stays one step away in the row menu.
    private var tapCopies: Bool { field.kind != .multiline }

    private var normalBody: some View {
        let match = privateEmailMatch
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    fieldLabelText(field.label)
                        .vaultType(.caption).fontWeight(.medium)
                        .foregroundStyle(copied ? VaultColors.copyFlashText.opacity(0.85) : theme.color(.accentText))
                    if match != nil {
                        PrivateEmailBadge(onAccentBackground: copied)
                    }
                    // Shown regardless of reveal state — the network name doesn't leak
                    // the secret, and it's useful even while the value stays masked.
                    if isCardNumber, let brand = PaymentCard.brand(for: field.value) {
                        CardBrandBadge(brand: brand, onAccentBackground: copied)
                    }
                }
                valueView
                // Value already renders alias text (Controlled Reveal doesn't
                // apply here — the field isn't secret) — copy() below still
                // always copies `field.value`, i.e. the alias, never the
                // forwards-to destination shown on this line. Transparent (not
                // removed) during the flash so the row height never jumps.
                if let match {
                    PrivateEmailForwardsToLine(match: match)
                        .opacity(copied ? 0 : 1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(copied ? VaultColors.copyFlash : Color.clear)
        .foregroundStyle(copied ? VaultColors.copyFlashText : theme.color(.primary))
        .contentShape(.rect)
        .onTapGesture { if tapCopies { copy() } }
        // Reveal is one-shot: it expires on backgrounding and navigation away
        // (vault lock tears the screen down, which lands in onDisappear too).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { conceal() }
        }
        .onDisappear { conceal() }
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

    /// The value keeps its layout during the copy flash — it turns transparent
    /// and "Copied" overlays it, so multi-line fields never collapse and the
    /// row height stays rock steady through the animation.
    @ViewBuilder private var valueView: some View {
        valueContent
            .opacity(copied ? 0 : 1)
            .overlay(alignment: .topLeading) {
                if copied {
                    // Own-size layout: the overlay must not inherit the value's
                    // width, or a short value truncates "Copied" to "Co…".
                    Text(copiedFeedbackText).vaultType(.body)
                        .foregroundStyle(VaultColors.copyFlashText)
                        .fixedSize()
                }
            }
    }

    /// Secret policy is resolved BEFORE presentation kind (`DetailValuePresentation`),
    /// so a protected multiline value can never fall through to the Markdown branch.
    private var presentation: DetailValuePresentation {
        .resolve(kind: field.kind, isProtected: field.protected, isCardNumber: isCardNumber)
    }

    @ViewBuilder private var valueContent: some View {
        switch presentation {
        case .totpCode:
            TOTPCodeView(secret: field.value)
        case .url:
            // Website → SF, scheme greyed, domain/path in accent, tail-truncated.
            Text(urlColored(field.value)).vaultType(.body)
                .lineLimit(1).truncationMode(.tail)
        case .markdownNote:
            // Notes render their Markdown (headings, lists, emphasis, links).
            MarkdownNoteText(text: field.value)
        case .protectedMultiline:
            // SSH private keys, recovery codes: fixed mask until explicit reveal.
            // The mask has constant geometry (never derived from the value) so it
            // leaks neither content nor length; revealed content is plain
            // selectable monospace — secrets are not Markdown.
            if revealed {
                Text(field.value)
                    .font(.vaultCode())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(verbatim: String(repeating: "•", count: 12))
                    .font(.vaultCode())
                    .foregroundStyle(theme.color(.secondary))
                    .accessibilityLabel(Text("Hidden value"))
            }
        case .cardNumber:
            // Grouped display only — storage (`field.value`) stays digits-only;
            // `GlyphResolveText` resolves the FORMATTED string so a revealed card
            // number reads in its real 4-4-4-4 (or Amex 4-6-5) grouping.
            let formatted = PaymentCard.formattedForDisplay(field.value)
            if revealed {
                GlyphResolveText(text: formatted, isRevealed: revealed, font: .vaultCode())
                    .textSelection(.enabled)
            } else {
                GlyphResolveText(text: formatted, isRevealed: revealed, font: .vaultCode())
                    .textSelection(.disabled)
            }
        case .secretGlyphs:
            // Controlled Reveal: glyphs resolve in place left-to-right
            // instead of a whole-field crossfade between two views.
            // `.textSelection` takes a concrete (non-uniform) type per
            // branch, so the enabled/disabled cases can't share a ternary.
            // Digit/letter/symbol colour-coding, same scheme as the generator and the
            // Large Type viewer — a revealed password is read character by character.
            // `vaultCode` for its TABULAR digits, so a revealed value does not
            // shift width as it resolves.
            if revealed {
                GlyphResolveText(text: field.value, isRevealed: revealed,
                                 font: .vaultCode(), colorized: true)
                    .textSelection(.enabled)
            } else {
                GlyphResolveText(text: field.value, isRevealed: revealed,
                                 font: .vaultCode(), colorized: true)
                    .textSelection(.disabled)
                    .accessibilityLabel(Text("Hidden value"))
            }
        case .plainText:
            Text(field.value)
                .font(VaultType.body.font)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    /// Always the short "Copied" — the auto-clear detail made the label long
    /// enough to wrap the row's value line, which reads as a layout glitch at
    /// the exact moment of feedback. The clear behavior itself is unchanged.
    private var copiedFeedbackText: String {
        appString("Copied")
    }

    /// No standalone copy glyph — the whole row copies on tap and the flash is
    /// the feedback; the menu keeps an explicit Copy. The badge stays mounted
    /// during the flash so the trailing cluster never shifts. Notes carry no
    /// menu at all: they're for reading and text selection, and their value
    /// lives in the editor.
    @ViewBuilder private var trailing: some View {
        HStack(spacing: 10) {
            if field.kind == .password, !field.value.isEmpty {
                PasswordStrengthRing(password: field.value, onAccent: copied)
            }
            if field.kind == .totp {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    // Honor the otpauth period so the ring matches the code's
                    // actual window (a 60s code hardcoded to 30 double-cycles).
                    let period = TOTPGenerator.period(forStoredValue: field.value)
                    CountdownRing(remaining: TOTPGenerator.secondsRemaining(period: period, date: context.date),
                                  period: period, onAccent: copied)
                }
            }
            // Plain notes carry no menu (reading surface); a protected multiline
            // secret NEEDS one — the menu is its only reveal and copy path.
            if presentation != .markdownNote {
                // A read-out sitting flush against the menu reads as one blob; the rule tells
                // the eye where the value ends and the control begins.
                if showsActionDivider { RowActionDivider(onAccent: copied) }
                menu
            }
        }
    }

    /// Only rows that actually show something before the menu need separating from it.
    private var showsActionDivider: Bool {
        (field.kind == .password && !field.value.isEmpty) || field.kind == .totp
    }

    private var menu: some View {
        Menu {
            Button { copy() } label: { Label { Text("Copy") } icon: { VaultIcon(Icons.copy) } }
            // Large Type renders the raw value full-screen — for a multiline
            // secret that would bypass the mask entirely, so it is absent there.
            if presentation != .protectedMultiline {
                Button { authorizeThen { showLargeType = true } } label: {
                    Label { Text("Large Type") } icon: { VaultIcon(Icons.text) }
                }
            }
            // TOTP renders its code live — a Reveal toggle is meaningless there.
            if isSecret, field.kind != .totp {
                Button {
                    if revealed {
                        conceal()
                    } else {
                        authorizeThen {
                            withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) { revealed = true }
                            onUsed()
                            scheduleConcealTimeout()
                        }
                    }
                } label: {
                    Label { Text(revealed ? "Conceal" : "Reveal") } icon: { VaultIcon(revealed ? Icons.hide : Icons.reveal) }
                }
            }
            if field.kind == .url, let url = Self.normalized(field.value) {
                Button { PlatformAppearance.open(url) } label: { Label { Text("Open Website") } icon: { VaultIcon(Icons.globe) } }
            }
            // An identity's email stays unprotectable (owner decision 260728):
            // Profile, QuickType, and share surfaces all present that address,
            // and a sealed one would render as ciphertext noise everywhere.
            if !field.value.isEmpty, !readOnly,
               !(category == .identity && field.kind == .email) {
                Divider()
                Button { showProtect = true } label: { Label { Text("Protect…") } icon: { VaultIcon(Icons.lock) } }
            }
        } label: {
            VaultIcon(Icons.moreHorizontal, size: 17)
                // Icon-rank primary on the grey well: a row's overflow control should
                // read as dark dots in a chip, not as another grey glyph among the
                // secondary metadata beside it.
                .foregroundStyle(copied ? VaultColors.copyFlashText : theme.color(.iconPrimary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(copied ? VaultColors.copyFlashText.opacity(0.22) : VaultColors.fill))
                // Invisible padded hit area: the visual circle stays 30pt, the
                // tappable region meets the 44pt minimum (rule 6). The negative
                // trailing padding cancels the hit frame's invisible slice so the
                // VISIBLE circle sits at the row inset, not 7pt further in.
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .contentShape(Rectangle())
                .padding(.trailing, -(Metric.hitMin - 30) / 2)
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
        rest.foregroundColor = theme.color(.accentText)
        result.append(rest)
        return result
    }

    /// Collapse a live reveal and cancel its expiry timer.
    private func conceal() {
        concealTask?.cancel()
        concealTask = nil
        revealed = false
    }

    /// A reveal is action-bound, not a persistent state: it expires on its own
    /// after a short window even if the user stays on the screen.
    private func scheduleConcealTimeout() {
        concealTask?.cancel()
        guard revealed else { concealTask = nil; return }
        concealTask = Task {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { revealed = false }
        }
    }

    /// Runs `action` directly, or behind an action-bound device-owner re-auth
    /// prompt when this field's policy demands one. A failed or cancelled
    /// prompt performs nothing.
    private func authorizeThen(_ action: @escaping @MainActor () -> Void) {
        guard requiresReauth else { action(); return }
        Task {
            do {
                try await env.session.requireBiometrics(reason: appString("Confirm it’s you"))
                action()
            } catch {
                Haptics.warning()
            }
        }
    }

    private func copy() {
        guard !copied, !field.value.isEmpty else { return }
        authorizeThen {
            env.clipboard.copy(copyValue, label: field.label, sensitive: isSecret || field.kind == .totp)
            onUsed()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.3)) { copied = false }
            }
        }
    }

    static func normalized(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.contains("://") ? URL(string: trimmed) : URL(string: "https://\(trimmed)")
    }
}
