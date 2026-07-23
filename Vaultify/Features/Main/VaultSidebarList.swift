import SwiftUI

/// The iPad/Mac sidebar list: the four Vault sections (mirroring the iPhone tabs) +
/// a Spaces (folders) section + a Profile row. Selection drives the split view's
/// detail column. Polaris icons + localized labels; no hardcoded visual constants.
struct VaultSidebarList: View {
    @Environment(AppEnvironment.self) private var env
    // Optional binding: `List(selection:)` single-selection expects `SelectionValue?`.
    @Binding var selection: UIStateStore.SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            // Persona avatar row at the very top — the iPad-Settings idiom
            // (avatar + name + subtitle). Selecting it opens Profile in the
            // detail column; Home drops its own identity card at regular width.
            Section {
                // A LABEL, not a free HStack: the label's icon column shares the
                // system alignment guide with the section rows below, so the
                // avatar's leading edge and the row's side insets match them.
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: PersonaDisplay.name(env))
                            .vaultType(.headline).themedForeground().lineLimit(1)
                        Text(verbatim: PersonaDisplay.subtitle(env))
                            .vaultType(.caption).themedForeground(.secondary).lineLimit(1)
                    }
                } icon: {
                    PersonaAvatarView(size: 40)
                }
                .padding(.vertical, Space.s1)
                .tag(UIStateStore.SidebarSelection.profile)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: "\(PersonaDisplay.name(env)), \(PersonaDisplay.subtitle(env))"))
            }

            Section {
                // No Search row: the sidebar's own search field (iPad-Settings
                // idiom) IS the search entry at regular width.
                ForEach(VaultTab.allCases.filter { $0 != .search }) { tab in
                    Label { Text(tab.accessibilityLabel) } icon: { PolarisIcon(tab.icon) }
                        .tag(UIStateStore.SidebarSelection.section(tab))
                }
            } header: {
                Text("Vault")
            }

            if !env.repository.folders.isEmpty {
                Section {
                    ForEach(env.repository.folders) { folder in
                        Label { Text(folder.name) } icon: { PolarisIcon(folder.iconAsset) }
                            .tag(UIStateStore.SidebarSelection.space(folder.id))
                    }
                } header: {
                    Text("Spaces")
                }
            }
        }
        // System sidebar appearance — Liquid Glass on iOS 26, translucent
        // sidebar material earlier — never a custom-painted list.
        .listStyle(.sidebar)
    }
}
