import SwiftUI

/// Reusable generator UI (password + passphrase). When `onUse` is set it shows
/// a "Use" action (editor integration); otherwise it's copy-only (Generator tab).
struct PasswordGeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password, passphrase
        var id: String { rawValue }
        var title: LocalizedStringResource { self == .password ? "Password" : "Passphrase" }
    }

    @Environment(AppEnvironment.self) private var env
    var onUse: ((String) -> Void)?

    @State private var mode: Mode = .password
    @State private var output = ""
    @State private var pwd = PasswordOptions()
    @State private var phrase = PassphraseOptions()

    var body: some View {
        Form {
            Section { outputCard }

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode == .password { passwordControls } else { passphraseControls }

            if let onUse {
                Section {
                    Button { onUse(output) } label: {
                        Text("Use Password").frame(maxWidth: .infinity)
                    }
                    .disabled(output.isEmpty)
                }
            }
        }
        .onAppear { if output.isEmpty { regenerate() } }
        .onChange(of: pwd) { regenerate() }
        .onChange(of: phrase) { regenerate() }
        .onChange(of: mode) { regenerate() }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(output)
                .font(.vaultMono(.title3, weight: .medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            PasswordStrengthMeter(password: output)
            HStack {
                Button { env.clipboard.copy(output, label: "Password") } label: {
                    Label("Copy", image: Icons.copy)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button { regenerate() } label: {
                    Label("Regenerate", image: Icons.refresh)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var passwordControls: some View {
        Section("Options") {
            Stepper(value: $pwd.length, in: 8...64) {
                LabeledContent("Length", value: "\(pwd.length)")
            }
            Toggle("Uppercase (A–Z)", isOn: $pwd.uppercase)
            Toggle("Lowercase (a–z)", isOn: $pwd.lowercase)
            Toggle("Digits (0–9)", isOn: $pwd.digits)
            Toggle("Symbols (!@#…)", isOn: $pwd.symbols)
            Toggle("Avoid ambiguous", isOn: $pwd.avoidAmbiguous)
        }
    }

    @ViewBuilder private var passphraseControls: some View {
        Section("Options") {
            Stepper(value: $phrase.wordCount, in: 3...10) {
                LabeledContent("Words", value: "\(phrase.wordCount)")
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
    }

    private func regenerate() {
        output = mode == .password
            ? PasswordGenerator.generate(pwd)
            : PasswordGenerator.passphrase(phrase)
        Haptics.tap()
    }
}
