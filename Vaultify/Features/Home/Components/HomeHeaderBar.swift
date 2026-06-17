import SwiftUI

/// Floating Home header bar: two Liquid-Glass capsule pills that overlay the
/// scroll content so the glass blurs whatever scrolls beneath them.
///
/// Left pill  — folder switcher (dot · name · chevron)
/// Right pill — action cluster: search · add (menu) · more (menu → Settings)
///
/// Glass rendering follows the same guard pattern used by VaultTabBarBackground:
///   #if compiler(>=6.2)  ← keeps pre-Xcode-26 CI runners from seeing the symbol
///   if #available(iOS 26, *), !reduceTransparency { glassEffect }
///   else { .regularMaterial fallback }
struct HomeHeaderBar: View {
    /// nil = "All Spaces" (no folder filter).
    @Binding var selectedFolderId: String?
    /// Called with the chosen item category when the user picks from the Add menu.
    let onAddCategory: (ItemCategory) -> Void
    let onSettings: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var showFolderPicker = false

    private var selectedFolder: Folder? {
        guard let id = selectedFolderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    private var folderDisplayName: String {
        selectedFolder?.name ?? appString("All Spaces")
    }

    private var folderDotColor: Color {
        selectedFolder?.color.tint ?? env.theme.active.color(.iconSecondary)
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            // ── Left pill: folder switcher ───────────────────────────────
            Button {
                showFolderPicker = true
            } label: {
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(folderDotColor)
                        .frame(width: 10, height: 10)

                    Text(folderDisplayName)
                        .vaultType(.screenTitle)
                        .themedForeground()
                        .lineLimit(1)

                    PolarisIcon(Icons.chevronDown, size: 15)
                        .themedForeground(.secondary)
                }
                .padding(.horizontal, Space.s3)
                .frame(height: Metric.hitMin)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .headerGlassCapsule()

            Spacer()

            // ── Right pill: search · add · more ─────────────────────────
            HStack(spacing: 0) {
                // Search — switches to the Search tab
                Button {
                    NotificationCenter.default.post(name: .vaultSwitchToSearch, object: nil)
                } label: {
                    PolarisIcon(Icons.search, size: Metric.iconUtility)
                        .themedForeground()
                }
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .accessibilityLabel(Text("Search"))

                // Add — menu to choose item type
                Menu {
                    ForEach(ItemCategory.allCases) { category in
                        Button {
                            onAddCategory(category)
                        } label: {
                            Label {
                                Text(category.title)
                            } icon: {
                                PolarisIcon(category.iconAsset)
                            }
                        }
                    }
                } label: {
                    PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                        .themedForeground()
                }
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .accessibilityLabel(Text("Add Item"))

                // More — Settings entry (extensible for future items)
                Menu {
                    Button {
                        onSettings()
                    } label: {
                        Label {
                            Text("Settings")
                        } icon: {
                            PolarisIcon(Icons.settings)
                        }
                    }
                } label: {
                    PolarisIcon(Icons.moreHorizontal, size: Metric.iconUtility)
                        .themedForeground()
                }
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .accessibilityLabel(Text("More options"))
            }
            .headerGlassCapsule()
        }
        .padding(.horizontal, Space.gutter)
        // Vertical padding gives the pills breathing room and space for shadow bleed.
        .padding(.vertical, Space.s2)
        .sheet(isPresented: $showFolderPicker) {
            HomeFolderPickerSheet(selectedFolderId: $selectedFolderId)
        }
    }
}

// MARK: - Header glass capsule modifier

/// Renders the receiver as a floating Liquid-Glass capsule (control layer only).
/// Replicates the same #if / #available / reduceTransparency guard used in
/// VaultTabBarBackground so the pre-Xcode-26 CI runner build is never broken.
private struct HeaderGlassCapsule: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *), !reduceTransparency {
            // Liquid Glass: interactive so touch response matches the tab bar.
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let fill: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(Color(rgb: env.theme.active.surfaceFloatingSolid))
            : AnyShapeStyle(.regularMaterial)
        return content
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5))
            .elevation(.level2)
    }
}

private extension View {
    func headerGlassCapsule() -> some View { modifier(HeaderGlassCapsule()) }
}

// MARK: - Folder picker sheet (unchanged)

/// Lightweight folder picker for the Home header. Lets the user pick "All
/// Spaces" (nil) or a specific folder to filter the Home feed.
private struct HomeFolderPickerSheet: View {
    @Binding var selectedFolderId: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    folderRow(
                        name: Text("All Spaces"),
                        badge: nil,
                        selected: selectedFolderId == nil
                    ) { select(nil) }
                }
                .listRowBackground(VaultColors.surface)

                if !env.repository.folders.isEmpty {
                    Section {
                        ForEach(env.repository.folders) { folder in
                            folderRow(
                                name: Text(folder.name),
                                badge: FolderBadge(icon: folder.iconAsset,
                                                   color: folder.color,
                                                   size: 30),
                                selected: selectedFolderId == folder.id
                            ) { select(folder.id) }
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
            .themedFormBackground()
            .navigationTitle(Text("Spaces"))
            .themedColorScheme()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func select(_ id: String?) {
        selectedFolderId = id
        dismiss()
    }

    @ViewBuilder
    private func folderRow(name: Text,
                           badge: FolderBadge?,
                           selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let badge {
                    badge
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VaultColors.fill)
                        .frame(width: 30, height: 30)
                }
                name.themedForeground()
                Spacer()
                if selected {
                    PolarisIcon(Icons.check, size: 18)
                        .foregroundStyle(Color(rgb: env.theme.active.accent))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
