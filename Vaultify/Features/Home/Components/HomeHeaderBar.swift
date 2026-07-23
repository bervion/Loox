import SwiftUI

/// Home header: the Loox wordmark on the left + glass action cluster on the right
/// (search · add · settings). The Space switcher now lives in the "All" section title.
///
/// Composes `VaultScreenHeader` so the overlay positioning, padding, and glass
/// logic all live in one shared place.
struct HomeHeaderBar: View {
    /// Drives the in-place Home layout editor: the edit button flips it on, the standalone
    /// Done button flips it off. Owned by `HomeScreen`.
    @Binding var isEditingLayout: Bool
    /// Called with the chosen item category when the user picks from the Add menu.
    let onAdd: () -> Void
    /// Opens Notifications through the compact-iOS navigator (native slide over the tab
    /// bar) rather than a SwiftUI push, so the tab bar doesn't reveal late on back.
    let onNotifications: () -> Void
    let onSettings: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                // Edit button (normal mode only) — replaces the old brand wordmark and opens
                // the layout editor. In edit mode the leading clears; the standalone Done
                // button on the far right is how you leave.
                if !isEditingLayout {
                    HeaderActionCluster {
                        // Text "Edit"/"Sửa" affordance (replaces the old brand wordmark, then
                        // the pencil icon). Its own key so the shared "Edit" string is untouched.
                        Button {
                            withAnimation(editModeAnimation) { isEditingLayout = true }
                        } label: {
                            Text(LocalizedStringResource("home.customize.action", defaultValue: "Edit").inAppLocalized)
                                .vaultType(.body)
                                .themedForeground()
                                .padding(.horizontal, Space.s3)
                                .frame(minHeight: Metric.hitMin)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Customize Home"))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            },
            trailing: {
                // The quick-action cluster stays visible in edit mode too; only the Done
                // button is added, OUTSIDE the cluster at the far right (its own button).
                HStack(spacing: Space.s2) {
                    HeaderActionCluster {
                        // Notifications — pending share invitations + approval requests (V7).
                        // A Button routed through the navigator (like Settings), NOT a
                        // NavigationLink: the SwiftUI push hid the tab bar via a toolbar modifier
                        // that reveals late on pop; the navigator slide covers it cleanly.
                        Button(action: onNotifications) {
                            PolarisIcon(Icons.notification, size: Metric.iconUtility)
                                .themedForeground()
                                .frame(width: Metric.hitMin, height: Metric.hitMin)
                                .contentShape(.rect)
                                .overlay(alignment: .topTrailing) {
                                    if notificationCount > 0 {
                                        Text(verbatim: notificationCount > 9 ? "9+" : "\(notificationCount)")
                                            .vaultType(.caption)
                                            .fontWeight(.bold)
                                            // WCAG-derived on-color for the destructive-tinted badge.
                                            .foregroundStyle(Color(rgb: env.theme.active.onDestructive))
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(env.theme.active.color(.destructive), in: Circle())
                                            .offset(x: -4, y: 6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Notifications"))

                        // Add — opens the item-type picker sheet.
                        Button(action: onAdd) {
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
                            accessibilityLabel: "Settings",
                            accessibilityIdentifier: "home.settings"
                        ) {
                            onSettings()
                        }
                    }

                    if isEditingLayout {
                        doneButton
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
            }
        )
    }

    /// The edit-mode transition — the app's low-bounce spring, collapsed to instant under
    /// Reduce Motion. Drives both the header choreography and Home's content cross-fade.
    private var editModeAnimation: Animation? {
        // A short plain fade, not a spring: the toggle cross-fades two heavy
        // resident layers, and the springy scale read as a hitch (owner 260723).
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// Done — the native iOS Liquid-Glass button (iOS 26+) with a white check, sitting
    /// outside the action cluster. Falls back to a solid accent circle on earlier OSes or
    /// under Reduce Transparency.
    @ViewBuilder private var doneButton: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *), !reduceTransparency {
            Button {
                withAnimation(editModeAnimation) { isEditingLayout = false }
            } label: {
                // Fixed 44pt glass circle so its trailing edge lands on Space.gutter exactly
                // like the action cluster — `.glassProminent`'s intrinsic padding sat wider.
                // White check per product decision — reads on the accent-tinted glass.
                PolarisIcon(Icons.check, size: Metric.iconUtility)
                    .foregroundStyle(.white)
                    .frame(width: Metric.hitMin, height: Metric.hitMin)
                    .glassEffect(.regular.tint(env.theme.active.color(.accent)).interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Done"))
        } else {
            solidDoneButton
        }
        #else
        solidDoneButton
        #endif
    }

    /// Pre-iOS-26 / Reduce-Transparency fallback: a solid accent circle with a white check.
    private var solidDoneButton: some View {
        Button {
            withAnimation(editModeAnimation) { isEditingLayout = false }
        } label: {
            PolarisIcon(Icons.check, size: Metric.iconUtility)
                .foregroundStyle(.white)
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .background(Circle().fill(env.theme.active.color(.accent)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Done"))
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
