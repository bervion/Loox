import SwiftUI

/// Home header: the Loox wordmark on the left + glass action cluster on the right
/// (search · add · settings). The Space switcher now lives in the "All" section title.
///
/// Composes `VaultScreenHeader` so the overlay positioning, padding, and glass
/// logic all live in one shared place.
struct HomeHeaderBar: View {
    /// Called with the chosen item category when the user picks from the Add menu.
    let onAdd: () -> Void
    let onSettings: () -> Void

    @Environment(AppEnvironment.self) private var env

    private var notificationCount: Int {
        env.inviteInboxCoordinator.pendingInvites.count
            + env.approvalCoordinator.pendingOwnerRequests.count
            // Outgoing shares the recipient finished accepting — the ceremony
            // now waits on the owner, so the state is actionable, not pending.
            // No overlap with the request count: requests only exist on active
            // (grant-published) shares, which readyForCeremony excludes.
            + env.sharingStore.awaitingCeremonyCount
    }

    var body: some View {
        VaultScreenHeader(
            leading: {
                // Brand wordmark instead of the old folder-switcher title (no glass pill;
                // only the right cluster receives the glass treatment).
                BrandLogoMark(size: 20, shadowRadius: 0, shadowY: 0)
                    .frame(minHeight: Metric.hitMin, alignment: .leading)
                    .accessibilityLabel(Text("Loox"))
            },
            trailing: {
                HeaderActionCluster {
                    // Notifications — pending share invitations + approval
                    // requests (V7). Badge = actionable count; the bell is a
                    // NavigationLink because the header lives inside Home's stack.
                    NavigationLink(value: NotificationsRoute()) {
                        PolarisIcon(Icons.notification, size: Metric.iconUtility)
                            .themedForeground()
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                            .overlay(alignment: .topTrailing) {
                                if notificationCount > 0 {
                                    Text(verbatim: notificationCount > 9 ? "9+" : "\(notificationCount)")
                                        .vaultType(.caption)
                                        .fontWeight(.bold)
                                        // WCAG-derived on-color for the destructive-tinted
                                        // badge (not a decorative quick-action tile — the
                                        // white exemption doesn't cover this one).
                                        .foregroundStyle(Color(rgb: env.theme.active.onDestructive))
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(env.theme.active.color(.destructive),
                                                    in: Circle())
                                        .offset(x: -4, y: 6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Notifications"))


                    // Add — opens the item-type picker sheet.
                    Button(action: onAdd) {
                        // Frame + contentShape inside the label so the full 44pt
                        // area triggers it, not just the 24pt glyph.
                        PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                            .themedForeground()
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Add Item"))

                    // Settings — direct, no "more" indirection
                    HeaderIconButton(
                        Icons.settings,
                        accessibilityLabel: "Settings"
                    ) {
                        onSettings()
                    }
                }
            }
        )
    }
}

// MARK: - Space picker sheet

/// Space picker for Home. Lets the user pick "All Spaces" (nil) or a specific folder to
/// filter the Home feed, plus create/manage spaces. Presented from the "All" section title.
struct HomeFolderPickerSheet: View {
    @Binding var selectedFolderId: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var creatingSpace = false

    private var accent: Color { Color(rgb: env.theme.active.accent) }

    var body: some View {
        VaultSheetScaffold(
            title: "Spaces",
            trailing: {
                Button { creatingSpace = true } label: {
                    PolarisIcon(Icons.add, size: 18)
                }
                .accessibilityLabel(Text("Create New Space"))
            }
        ) {
            List {
                // Spaces — All Spaces + every folder, with item counts.
                Section {
                    spaceRow(name: Text("All Spaces"),
                             count: env.repository.allItems(folder: nil).count,
                             selected: selectedFolderId == nil) {
                        tile(Icons.inventory, fill: VaultColors.fill,
                             iconColor: env.theme.active.color(.iconSecondary))
                    } action: { select(nil) }

                    ForEach(env.repository.activePersonaSpaces) { folder in
                        spaceRow(name: Text(verbatim: folder.name),
                                 count: env.repository.itemCount(for: folder.id),
                                 selected: selectedFolderId == folder.id) {
                            FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                        } action: { select(folder.id) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                // Management — create a space, or jump to the Items tab to manage them.
                Section {
                    managementRow(title: Text("Create New Space"),
                                  tint: accent, showChevron: false) {
                        tile(Icons.addCircle, fill: accent.opacity(0.14), iconColor: accent)
                    } action: { creatingSpace = true }

                    managementRow(title: Text("Manage Spaces & Members"),
                                  tint: nil, showChevron: true) {
                        tile(Icons.settings, fill: VaultColors.fill,
                             iconColor: env.theme.active.color(.iconSecondary))
                    } action: { openManagement() }
                }
                .listRowBackground(VaultColors.surface)
            }
            .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
        }
    }

    private func select(_ id: String?) {
        selectedFolderId = id
        dismiss()
    }

    /// Dismiss and switch to the Items tab — the surface that manages all spaces.
    private func openManagement() {
        dismiss()
        NotificationCenter.default.post(name: .vaultSwitchToItems, object: nil)
    }

    // MARK: Rows

    @ViewBuilder
    private func spaceRow<Leading: View>(
        name: Text, count: Int, selected: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                name.themedForeground()
                Spacer(minLength: Space.s2)
                Text("\(count)").themedForeground(.secondary)
                if selected {
                    PolarisIcon(Icons.checkCircle, size: 20).foregroundStyle(accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func managementRow<Leading: View>(
        title: Text, tint: Color?, showChevron: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                if let tint {
                    title.foregroundStyle(tint)
                } else {
                    title.themedForeground()
                }
                Spacer()
                if showChevron {
                    PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 30pt rounded leading tile with a centred Polaris icon. Radius matches
    /// `FolderBadge`'s size-relative formula (`size * 0.28`) so this pseudo-row's
    /// tile stays visually consistent with the real Space tiles in the same list.
    private func tile(_ icon: String, fill: Color, iconColor: Color) -> some View {
        let size: CGFloat = 30
        return RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(PolarisIcon(icon, size: 17).foregroundStyle(iconColor))
    }
}
