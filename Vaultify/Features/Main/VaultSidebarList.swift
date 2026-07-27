import SwiftUI

/// The iPad sidebar list: the identity card, the Vault sections (mirroring the iPhone
/// tabs), Quick Actions, a Spaces (folders) section, and Settings at the foot.
/// Selection drives the split view's detail column.
///
/// Quick Actions live HERE at regular width — Home drops its own quick-action grid
/// while a sidebar is on screen and shows it again in compact multitasking, where
/// there is no sidebar to carry them (see `HomeScreen.sectionView`).
///
/// Row icons are white-filled SF Symbols on a tinted rounded badge
/// (`SettingsIconBadge`), the iPad Settings idiom. This is a sidebar-only grant
/// (owner 260727) — the tab bar and every other surface keep the Polaris set.
struct VaultSidebarList: View {
    @Environment(AppEnvironment.self) private var env
    // Optional binding: `List(selection:)` single-selection expects `SelectionValue?`.
    @Binding var selection: UIStateStore.SidebarSelection?

    /// Live counts + quick-action triggers, owned by `VaultSidebarView` (which holds
    /// the sheets and recomputes the audit off the render path).
    let watchtowerIssueCount: Int
    let totpCount: Int
    let onAddItem: () -> Void
    let onGeneratePassword: () -> Void
    let onOpenTotpCodes: () -> Void

    var body: some View {
        List(selection: $selection) {
            // Identity card at the very top — the iPad-Settings idiom (avatar + name +
            // subtitle). Selecting it opens Profile in the detail column; Home drops its
            // own identity card at regular width.
            Section {
                VaultSidebarProfileCard(isSelected: selection == .profile) {
                    selection = .profile
                }
                // The card IS the row's surface, so the list must paint nothing behind
                // it, and its insets replace the standard row insets.
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Space.s2, leading: Space.s2,
                                          bottom: Space.s2, trailing: Space.s2))
                .listRowSeparator(.hidden)
            }

            Section {
                // No Search row: the sidebar's own search field (iPad-Settings
                // idiom) IS the search entry at regular width.
                ForEach(VaultTab.allCases.filter { $0 != .search }) { tab in
                    Label {
                        Text(tab.accessibilityLabel)
                    } icon: {
                        SettingsIconBadge(systemName: Self.symbol(for: tab), tint: Self.tint(for: tab))
                    }
                    // Security carries the open-issue count Home's quick-action tile used
                    // to show. `.badge(0)` renders nothing, so a clean vault stays quiet.
                    .badge(tab == .watchtower ? watchtowerIssueCount : 0)
                    .tag(UIStateStore.SidebarSelection.section(tab))
                }
            } header: {
                Text(LocalizedStringResource("Vault").inAppLocalized)
            }

            Section {
                // Security is deliberately absent: it is already a first-class
                // destination one section above, and repeating it here would give the
                // same target two rows.
                actionRow("Add Item", symbol: "plus",
                          tint: SettingsBadgeTint.orange, action: onAddItem)
                actionRow("Generate Password", symbol: "key.fill",
                          tint: SettingsBadgeTint.teal, action: onGeneratePassword)
                actionRow("2FA Codes", symbol: "123.rectangle.fill",
                          tint: SettingsBadgeTint.purple, count: totpCount, action: onOpenTotpCodes)
            } header: {
                Text(LocalizedStringResource("Quick Actions").inAppLocalized)
            }

            if !env.repository.folders.isEmpty {
                Section {
                    ForEach(env.repository.folders) { folder in
                        Label {
                            Text(verbatim: folder.name)
                        } icon: {
                            // A Space keeps its OWN chosen Polaris glyph — a user-picked
                            // icon has no honest SF equivalent — but wears the same
                            // white-on-tint badge as every other sidebar row, in the
                            // Space's own colour.
                            SettingsIconBadge(icon: folder.iconAsset, tint: folder.color.tint)
                        }
                        .tag(UIStateStore.SidebarSelection.space(folder.id))
                    }
                } header: {
                    Text(LocalizedStringResource("Spaces").inAppLocalized)
                }
            }

            // Settings closes the sidebar, the way it does in the system's own
            // sidebars: a destination, not an action, so it opens in the detail column.
            Section {
                Label {
                    Text(LocalizedStringResource("Settings").inAppLocalized)
                } icon: {
                    SettingsIconBadge(systemName: "gearshape.fill", tint: SettingsBadgeTint.gray)
                }
                .tag(UIStateStore.SidebarSelection.settings)
            }
        }
        // System sidebar appearance — Liquid Glass on iOS 26, translucent
        // sidebar material earlier — never a custom-painted list.
        .listStyle(.sidebar)
    }

    /// A Quick Action row: a button, not a selection tag, since it presents a sheet
    /// rather than swapping the detail column. `.plain` keeps its label reading like
    /// the destination rows instead of picking up the system button tint.
    private func actionRow(
        _ title: LocalizedStringResource,
        symbol: String,
        tint: Color,
        count: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title.inAppLocalized)
            } icon: {
                SettingsIconBadge(systemName: symbol, tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .badge(count)
    }

    // MARK: Per-section badge identities

    /// SF Symbol per Vault section. Sidebar-only (see the type doc); the tab bar
    /// keeps `VaultTab.icon`'s Polaris assets.
    private static func symbol(for tab: VaultTab) -> String {
        switch tab {
        case .home: return "house.fill"
        case .items: return "square.grid.2x2.fill"
        case .watchtower: return "checkmark.shield.fill"
        case .search: return "magnifyingglass"
        }
    }

    /// Fixed badge hues, distinct within the sidebar and stable across accent
    /// changes — these are identities, not state colours (see `SettingsBadgeTint`).
    private static func tint(for tab: VaultTab) -> Color {
        switch tab {
        case .home: return SettingsBadgeTint.blue
        case .items: return SettingsBadgeTint.indigo
        case .watchtower: return SettingsBadgeTint.green
        case .search: return SettingsBadgeTint.gray
        }
    }
}
