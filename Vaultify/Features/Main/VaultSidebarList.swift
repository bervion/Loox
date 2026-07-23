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
            Section {
                ForEach(VaultTab.allCases) { tab in
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

            Section {
                Label { Text("Profile") } icon: { PolarisIcon(Icons.person) }
                    .tag(UIStateStore.SidebarSelection.profile)
            }
        }
        // System sidebar appearance — Liquid Glass on iOS 26, translucent
        // sidebar material earlier — never a custom-painted list.
        .listStyle(.sidebar)
    }
}
