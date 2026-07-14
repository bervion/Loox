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

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section {
                ForEach(options.indices, id: \.self) { index in
                    row(options[index])
                }
            } footer: {
                if let footer { Text(footer) }
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(Text(title))
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: Option) -> some View {
        Button {
            guard option.value != selection else { return }
            selection = option.value
            Haptics.tap()
        } label: {
            HStack {
                Text(option.label).themedForeground(.primary)
                Spacer()
                if option.value == selection {
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
