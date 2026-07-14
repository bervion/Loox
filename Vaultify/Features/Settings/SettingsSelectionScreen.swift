import SwiftUI

/// Apple-Settings-style child selection screen: one row per option with a
/// checkmark on the current value. Replaces inline popup pickers on the
/// Settings root — tap the parent row, land here, pick a row.
struct SettingsSelectionScreen<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: LocalizedStringResource
    }

    let title: LocalizedStringResource
    let options: [Option]
    @Binding var selection: Value
    var footer: LocalizedStringResource? = nil
    /// When set, the choice is DEFERRED: tapping a row stages it (checkmark moves)
    /// and a Save button commits it through this closure instead of the binding.
    /// Used for language, which runs a branded switch transition on save rather
    /// than mutating live. When nil, a tap applies immediately (the default).
    var onCommit: ((Value) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    /// Staged choice in deferred mode; nil until the user taps a row.
    @State private var pending: Value?

    /// The row currently shown as chosen: the staged value in deferred mode, the
    /// live selection otherwise.
    private var staged: Value { pending ?? selection }

    /// Resolve a resource against the in-app language (same mechanism as
    /// `appLabel`): pinning `.locale` then `String(localized:)` selects the
    /// chosen language's table, which a bare `Text(resource)` does not.
    private func localized(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = appResourceLocale
        return String(localized: copy)
    }

    var body: some View {
        Form {
            Section {
                ForEach(options.indices, id: \.self) { index in
                    row(options[index])
                }
            } footer: {
                if let footer { Text(verbatim: localized(footer)) }
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(localized(title))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onCommit {
                ToolbarItem(placement: .platformPrimaryAction) {
                    // Filled accent capsule (accent fill · WCAG onAccent text) so it
                    // reads as the primary action; dimmed until a new value is staged.
                    Button { onCommit(staged) } label: {
                        Text("Save")
                            .vaultType(.subhead)
                            .foregroundStyle(env.theme.active.color(.onAccent))
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s1 + 2)
                            .background(env.theme.active.color(.accent), in: Capsule())
                            .opacity(staged == selection ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(staged == selection)
                }
            }
        }
    }

    private func row(_ option: Option) -> some View {
        Button {
            guard option.value != staged else { return }
            if onCommit != nil {
                pending = option.value   // stage; Save commits
            } else {
                selection = option.value // apply immediately
            }
            Haptics.tap()
        } label: {
            HStack {
                Text(verbatim: localized(option.label)).themedForeground(.primary)
                Spacer()
                if option.value == staged {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(env.theme.uiTint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
