import SwiftUI

/// Reusable generator UI (password / passphrase / PIN). Owns a header toolbar
/// group: a "regenerate" button always, plus a "use" (checkmark) button when
/// `onUse` is set (item-editor integration). The value is copied by tapping the
/// output row; there is no separate Copy button.
struct PasswordGeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password, passphrase, pin
        var id: String { rawValue }
        var title: LocalizedStringResource {
            let base: LocalizedStringResource
            switch self {
            case .password:   base = "Password"
            case .passphrase: base = "Passphrase"
            case .pin:        base = "PIN"
            }
            return base.inAppLocalized
        }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Latest generated value, owned by the parent sheet so its header buttons can read it.
    @Binding var output: String
    /// When set, a checkmark header button feeds the value back and dismisses.
    var onUse: ((String) -> Void)? = nil

    @State private var mode: Mode = .password
    @State private var pwd = PasswordOptions()
    @State private var phrase = PassphraseOptions()
    @State private var pin = PinOptions()
    /// Brief "copied" flash on the value row after a tap-to-copy.
    @State private var copied = false

    private var theme: AppTheme { env.theme.active }

    var body: some View {
        Form {
            Section { outputCard }
            .listRowBackground(VaultColors.surface)

            Section("Options") {
                // Generator type is a dropdown at the top of the options, so the
                // whole configuration lives in one place. A `Menu` (not a
                // `.menu` Picker) is used so the label is a plain tappable row —
                // the Picker menu style could steal focus and raise the keyboard.
                Menu {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(mode.title).themedForeground(.secondary)
                        PolarisIcon(Icons.chevronDown, size: 14)
                            .themedForeground(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                // Plain row menu (own chevron already drawn) — macOS would otherwise
                // draw a bordered pull-down button around the whole row.
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)

                switch mode {
                case .password:   passwordControls
                case .passphrase: passphraseControls
                case .pin:        pinControls
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        // The main shell's toast sits behind this sheet, so show the shared overlay
        // again here (same component the shell/onboarding use — no reinventing it).
        .overlay(alignment: .bottom) { CopyToastOverlay() }
        .animation(.vault(.spring(duration: 0.3), reduceMotion: reduceMotion),
                   value: env.clipboard.recentCopyLabel)
        .onAppear {
            if output.isEmpty { regenerate() }
            // Warm the diceware word list off the main thread. Its lazy `static let`
            // otherwise parses ~7.7k lines on first passphrase generation — which,
            // if that happens mid-drag, stalls the slider. Password mode never
            // touches it, hence only passphrase felt laggy.
            Task.detached(priority: .utility) { _ = DicewareWordList.words.count }
        }
        .onChange(of: pwd) { regenerate() }
        .onChange(of: phrase) { regenerate() }
        .onChange(of: pin) { regenerate() }
        .onChange(of: mode) { regenerate() }
        .toolbar {
            // Trailing action cluster, styled like the Home header: reuse
            // HeaderIconButton (44pt hit target, utility-sized glyph, themed) in a
            // tight HStack. iOS 26 groups the single toolbar item into one glass
            // pill. `checkCircle` reads bolder than a bare check for the confirm.
            ToolbarItem(placement: .platformPrimaryAction) {
                HStack(spacing: 0) {
                    HeaderIconButton(Icons.replay, accessibilityLabel: "Regenerate") {
                        Haptics.tap(); regenerate()
                    }
                    if onUse != nil {
                        HeaderIconButton(Icons.checkCircle, role: .accent,
                                         accessibilityLabel: "Use Password") {
                            Haptics.tap(); onUse?(output); dismiss()
                        }
                        .disabled(output.isEmpty)
                    }
                }
            }
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Tap the value to copy: the row flashes the accent color and shows
            // "Copied", mirroring the item-detail rows. Single-line + trailing
            // ellipsis keeps the height stable while the length slider changes.
            // No `.textSelection(.enabled)`: in a Form it can grab first responder
            // when the type Menu dismisses and raise the keyboard.
            Button { copy() } label: {
                HStack(spacing: Space.s2) {
                    valueText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Clipboard glyph morphs to the check variant while copied,
                    // then reverts with the `copied` state (~1.2s) — shared primitive
                    // so the copy affordance matches item detail's rows 1:1.
                    CopyMorphIcon(copied: copied, size: 18)
                        .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.iconSecondary))
                }
                .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.primary))
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(copied ? theme.color(.accent) : Color.clear)
                .vaultCornerRadius(Radius.md)
                // Outlined box normally; the border is hidden under the accent
                // flash while copied.
                .overlay {
                    if !copied {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Color(rgb: theme.separator), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.18), value: copied)

            // PINs are intentionally short/simple — a strength meter is noise there.
            if mode != .pin {
                PasswordStrengthMeter(password: output)
            }
        }
    }

    @ViewBuilder private var valueText: some View {
        Group {
            if copied {
                Text("Copied")
            } else {
                // Digit/letter/symbol color-coding — same "readable password"
                // scheme as the Large Type viewer.
                Text(SecretColoring.attributed(output, theme: theme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.vaultCode(.title3, weight: .medium))
        .monospacedDigit()
    }

    @ViewBuilder private var passwordControls: some View {
        countSlider("Length", value: $pwd.length, range: 8...64)
        Toggle("Uppercase (A–Z)", isOn: $pwd.uppercase)
        Toggle("Lowercase (a–z)", isOn: $pwd.lowercase)
        Toggle("Digits (0–9)", isOn: $pwd.digits)
        Toggle("Symbols (!@#…)", isOn: $pwd.symbols)
        Toggle("Avoid ambiguous", isOn: $pwd.avoidAmbiguous)
    }

    @ViewBuilder private var passphraseControls: some View {
        countSlider("Words", value: $phrase.wordCount, range: 3...10)
        Picker("Separator", selection: $phrase.separator) {
            Text("Hyphen").tag("-")
            Text("Period").tag(".")
            Text("Space").tag(" ")
            Text("Underscore").tag("_")
        }
        Toggle("Capitalize", isOn: $phrase.capitalize)
        Toggle("Include number", isOn: $phrase.includeNumber)
    }

    @ViewBuilder private var pinControls: some View {
        countSlider("Length", value: $pin.length, range: 4...12)
    }

    /// Labeled drag-to-set slider with throttled haptics, shared by every mode.
    /// Ticks only on an actual integer change (light haptic while dragging, no
    /// redundant regenerate) and a firm "commit" tap on release.
    @ViewBuilder
    private func countSlider(_ title: LocalizedStringKey, value: Binding<Int>,
                             range: ClosedRange<Int>) -> some View {
        VStack(spacing: Space.s2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)").font(.vaultCode()).monospacedDigit()
                    .themedForeground(.secondary)
            }
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { newValue in
                                   let v = Int(newValue.rounded())
                                   guard v != value.wrappedValue else { return }
                                   Haptics.selectionTick()
                                   value.wrappedValue = v
                               }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1,
                onEditingChanged: { editing in
                    if editing { Haptics.prepareSelection() } else { Haptics.tap() }
                }
            )
            .tint(VaultColors.accent)
        }
    }

    private func regenerate() {
        switch mode {
        case .password:   output = PasswordGenerator.generate(pwd)
        case .passphrase: output = PasswordGenerator.passphrase(phrase)
        case .pin:        output = PasswordGenerator.pin(pin)
        }
    }

    private func copy() {
        guard !copied, !output.isEmpty else { return }
        env.clipboard.copy(output, label: "Password")
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { copied = false }
        }
    }
}
