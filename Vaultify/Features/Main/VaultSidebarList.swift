import SwiftUI

/// The iPad sidebar list: the identity card, the Vault sections (mirroring the iPhone
/// tabs), Quick Actions, a Spaces (folders) section, and Settings at the foot.
/// Selection drives the split view's detail column.
///
/// Quick Actions live HERE at regular width — Home drops its own quick-action grid
/// while a sidebar is on screen and shows it again in compact multitasking, where
/// there is no sidebar to carry them (see `HomeScreen.sectionView`).
///
/// Row icons are the FILLED Polaris glyphs — the same assets the tab bar shows for an
/// active tab — rendered white on a tinted rounded badge (`SettingsIconBadge`), the iPad
/// Settings idiom. Filled, not outline: an outline glyph goes muddy on a solid tile.
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
                // The card IS the row's surface, so the list must paint nothing behind it.
                // ZERO horizontal inset: the list already indents the row box itself, and
                // that box is exactly where the search field and the selection capsules
                // below sit. Any inset on top of it pushes the card inboard of both, which
                // reads as a misaligned left edge down the sidebar.
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Space.s1, leading: 0,
                                          bottom: Space.s1, trailing: 0))
                .listRowSeparator(.hidden)
            }

            Section {
                // No Search row: the sidebar's own search field (iPad-Settings
                // idiom) IS the search entry at regular width — and, because there
                // is no row to fall back to, its only exit as well. That is why
                // `VaultSidebarView` emits an empty query on a clear instead of
                // swallowing it (see `VaultSidebarView.searchEntry(for:…)`).
                ForEach(VaultTab.allCases.filter { $0 != .search }) { tab in
                    Label {
                        Text(tab.accessibilityLabel)
                    } icon: {
                        // `iconSelected` — the FILLED Polaris variant the tab bar shows for
                        // the active tab. A filled glyph is what reads on a solid badge, and
                        // it keeps sidebar and tab bar visually the same set.
                        SettingsIconBadge(icon: tab.iconSelected, tint: Self.tint(for: tab))
                    }
                    // Security carries the open-issue count Home's quick-action tile used
                    // to show. `.badge(0)` renders nothing, so a clean vault stays quiet.
                    .badge(tab == .watchtower ? watchtowerIssueCount : 0)
                    .tag(UIStateStore.SidebarSelection.section(tab))
                    .tutorialAnchorIfPresent(tab == .watchtower ? TutorialAnchorID.homeSecurity : nil)
                }
            } header: {
                Text(LocalizedStringResource("Vault").inAppLocalized)
            }

            Section {
                // Security is deliberately absent: it is already a first-class
                // destination one section above, and repeating it here would give the
                // same target two rows.
                actionRow("Add Item", icon: Icons.add,
                          tint: SettingsBadgeTint.orange,
                          tutorialAnchorID: TutorialAnchorID.homeAddItem,
                          action: onAddItem)
                actionRow("Generate Password", icon: Icons.key,
                          tint: SettingsBadgeTint.teal, action: onGeneratePassword)
                actionRow("2FA Codes", icon: Icons.clock,
                          tint: SettingsBadgeTint.purple, count: totpCount, action: onOpenTotpCodes)
            } header: {
                Text(LocalizedStringResource("Quick Actions").inAppLocalized)
            }

            if !env.repository.folders.isEmpty {
                Section {
                    ForEach(env.repository.folders) { folder in
                        Label {
                            Text(verbatim: folder.displayName)
                        } icon: {
                            // A Space keeps its OWN chosen Polaris glyph — a user-picked
                            // icon has no honest SF equivalent — but wears the same
                            // white-on-tint badge as every other sidebar row, in the
                            // Space's own colour.
                            SettingsIconBadge(icon: folder.displayIcon, tint: folder.color.tint)
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
                    SettingsIconBadge(icon: Icons.settingsFill, tint: SettingsBadgeTint.gray)
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
        icon: String,
        tint: Color,
        count: Int = 0,
        tutorialAnchorID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title.inAppLocalized)
            } icon: {
                SettingsIconBadge(icon: icon, tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .badge(count)
        // At regular width Quick Actions live here instead of on Home, so the
        // first-run tour spotlights these rows on iPad.
        .tutorialAnchorIfPresent(tutorialAnchorID)
    }

    // MARK: Per-section badge identities

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
