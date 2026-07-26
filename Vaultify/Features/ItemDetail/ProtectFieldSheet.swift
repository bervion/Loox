import SwiftUI

/// Seal a plaintext field under second-layer protection — with the app-wide
/// Extra Password or a per-field custom code. Names the field being protected,
/// explains the two options as selectable cards, and offers inline Extra
/// Password setup instead of dead-ending into a Settings scavenger hunt.
struct ProtectFieldSheet: View {
    let field: DynamicField
    let onProtected: (DynamicField) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scheme: SecretGuard.Scheme = .level2
    @State private var level2Password = ""
    @State private var customCode = ""
    @State private var confirmCode = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showLevel2Setup = false

    private var hasLevel2: Bool { env.session.hasLevel2 }
    private var level2Unlocked: Bool { env.session.level2Key != nil }

    private var canProtect: Bool {
        if busy { return false }
        switch scheme {
        case .level2: return hasLevel2 && (level2Unlocked || !level2Password.isEmpty)
        case .custom: return customCode.count >= 4 && customCode == confirmCode
        }
    }

    var body: some View {
        VaultSheetScaffold(title: "Protect Field", trailing: {
            Button("Protect") { Task { await protect() } }.disabled(!canProtect)
        }) {
            Form {
                // WHAT is being protected — the old sheet never said.
                Section {
                    HStack(spacing: Space.s3) {
                        PolarisIcon(Icons.lockFill, size: Metric.iconInline)
                            .themedForeground(.iconSecondary)
                        fieldLabelText(field.label)
                            .vaultType(.headline)
                    }
                } footer: {
                    if field.kind == .totp {
                        Text("Protecting this code stops its live codes, AutoFill, and sharing until protection is removed.")
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Protect with") {
                    optionCard(.level2,
                               title: "Extra Password",
                               subtitle: hasLevel2
                                   ? "One password for all protected fields. Unlocks once per session."
                                   : "Not set up yet")
                    optionCard(.custom,
                               title: "Custom code",
                               subtitle: "A code just for this field. Asked every time you reveal it.")
                }
                .listRowBackground(VaultColors.surface)

                schemeInputs

                if let error { Text(verbatim: error).foregroundStyle(VaultColors.strengthWeak) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
        // Inline first-time setup: the redesigned Extra Password screen in a
        // sheet — on return the card flips to ready and Protect goes live.
        .sheet(isPresented: $showLevel2Setup) {
            NavigationStack {
                Level2SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLevel2Setup = false }
                        }
                    }
            }
        }
    }

    /// A selectable option row: radio ring + title/subtitle, with an inline
    /// "Set Up" affordance while the Extra Password doesn't exist yet.
    private func optionCard(_ value: SecretGuard.Scheme,
                            title: LocalizedStringKey,
                            subtitle: LocalizedStringKey) -> some View {
        let selected = scheme == value
        let accent = env.theme.active.color(.accent)
        return Button {
            withAnimation(.vault(Motion.spring, reduceMotion: reduceMotion)) { scheme = value }
            Haptics.tap()
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .stroke(selected ? accent : Color(rgb: env.theme.active.separatorOpaque),
                                lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(accent).frame(width: 12, height: 12)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).vaultType(.body)
                    Text(subtitle).vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if value == .level2 && !hasLevel2 {
                    Button("Set Up") { showLevel2Setup = true }
                        .vaultType(.callout)
                        .buttonStyle(.borderless)
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, Space.s1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var schemeInputs: some View {
        if scheme == .level2 {
            if hasLevel2 && !level2Unlocked {
                Section {
                    RevealableSecureField(title: "Extra Password", text: $level2Password)
                        .listRowInsets(.init())
                } footer: {
                    Text("Enter it once to unlock extra protection for this session.")
                }
                .listRowBackground(VaultColors.surface)
            } else if hasLevel2 {
                Section {
                    Text("This field will be protected with your Extra Password.")
                        .vaultType(.footnote).themedForeground(.secondary)
                }
                .listRowBackground(VaultColors.surface)
            }
        } else {
            Section {
                RevealableSecureField(title: "Code", text: $customCode).listRowInsets(.init())
                RevealableSecureField(title: "Confirm code", text: $confirmCode).listRowInsets(.init())
            } footer: {
                Text("Only this code can reveal the field. If you forget it, the field cannot be recovered.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func protect() async {
        busy = true; error = nil
        do {
            let sealed: String
            switch scheme {
            case .level2:
                if !level2Unlocked { try await env.session.unlockLevel2(password: level2Password) }
                guard let key = env.session.level2Key else { throw AuthError.locked }
                sealed = try SecretGuard.sealLevel2(field.value, l2Key: key.bytes)
            case .custom:
                sealed = try await SecretGuard.sealCustom(field.value, code: customCode)
            }
            var updated = field
            updated.value = sealed
            updated.guard2 = true
            onProtected(updated)
            Haptics.success()
            dismiss()
        } catch {
            self.error = (error as? AuthError)?.errorDescription ?? appString("Couldn’t protect this field.")
            Haptics.error()
        }
        busy = false
    }
}
