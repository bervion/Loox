import SwiftUI

/// Reusable generator UI (password + passphrase). When `onUse` is set it shows
/// a "Use" action (editor integration); otherwise it's copy-only (Generator tab).
struct PasswordGeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password, passphrase
        var id: String { rawValue }
        var title: LocalizedStringResource {
            let base: LocalizedStringResource = self == .password ? "Password" : "Passphrase"
            return base.inAppLocalized
        }
    }

    @Environment(AppEnvironment.self) private var env
    /// Latest generated value, owned by the parent sheet so its header "Use" button can read it.
    @Binding var output: String

    @State private var mode: Mode = .password
    @State private var pwd = PasswordOptions()
    @State private var phrase = PassphraseOptions()

    var body: some View {
        Form {
            Section { outputCard }
            .listRowBackground(VaultColors.surface)

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(VaultColors.surface)

            if mode == .password { passwordControls } else { passphraseControls }
        }
        .themedFormBackground()
        // Local copy toast — the main shell's toast sits behind this sheet, so show our own.
        .overlay(alignment: .bottom) { copyToast }
        .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
        .onAppear { if output.isEmpty { regenerate() } }
        .onChange(of: pwd) { regenerate() }
        .onChange(of: phrase) { regenerate() }
        .onChange(of: mode) { regenerate() }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(output)
                .font(.vaultCode(.title3, weight: .medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            PasswordStrengthMeter(password: output)
            HStack {
                Button { env.clipboard.copy(output, label: "Password") } label: {
                    HStack(spacing: 5) {
                        PolarisIcon(Icons.copy, size: 16)
                        Text("Copy")
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button { regenerate() } label: {
                    HStack(spacing: 5) {
                        PolarisIcon(Icons.refresh, size: 16)
                        Text("Regenerate")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, Space.s1)
    }

    /// Transient "copied" toast shown over the generator sheet.
    @ViewBuilder private var copyToast: some View {
        if let label = env.clipboard.recentCopyLabel {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                    .foregroundStyle(env.theme.active.color(.success))
                Text(appString("Copied \(label)")).vaultType(.subhead).fontWeight(.medium)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(.regularMaterial, in: Capsule())
            .elevation(.level2)
            .padding(.bottom, Space.s6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var passwordControls: some View {
        Section("Options") {
            // Drag-to-set length (easier than tapping a stepper repeatedly).
            VStack(spacing: Space.s2) {
                HStack {
                    Text("Length")
                    Spacer()
                    Text("\(pwd.length)").font(.vaultCode()).monospacedDigit()
                        .themedForeground(.secondary)
                }
                Slider(
                    value: Binding(get: { Double(pwd.length) },
                                   set: { pwd.length = Int($0.rounded()) }),
                    in: 8...64, step: 1
                )
                .tint(VaultColors.accent)
            }
            Toggle("Uppercase (A–Z)", isOn: $pwd.uppercase)
            Toggle("Lowercase (a–z)", isOn: $pwd.lowercase)
            Toggle("Digits (0–9)", isOn: $pwd.digits)
            Toggle("Symbols (!@#…)", isOn: $pwd.symbols)
            Toggle("Avoid ambiguous", isOn: $pwd.avoidAmbiguous)
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private var passphraseControls: some View {
        Section("Options") {
            // Drag-to-set word count.
            VStack(spacing: Space.s2) {
                HStack {
                    Text("Words")
                    Spacer()
                    Text("\(phrase.wordCount)").font(.vaultCode()).monospacedDigit()
                        .themedForeground(.secondary)
                }
                Slider(
                    value: Binding(get: { Double(phrase.wordCount) },
                                   set: { phrase.wordCount = Int($0.rounded()) }),
                    in: 3...10, step: 1
                )
                .tint(VaultColors.accent)
            }
            Picker("Separator", selection: $phrase.separator) {
                Text("Hyphen").tag("-")
                Text("Period").tag(".")
                Text("Space").tag(" ")
                Text("Underscore").tag("_")
            }
            Toggle("Capitalize", isOn: $phrase.capitalize)
            Toggle("Include number", isOn: $phrase.includeNumber)
        }
        .listRowBackground(VaultColors.surface)
    }

    private func regenerate() {
        output = mode == .password
            ? PasswordGenerator.generate(pwd)
            : PasswordGenerator.passphrase(phrase)
        Haptics.tap()
    }
}
