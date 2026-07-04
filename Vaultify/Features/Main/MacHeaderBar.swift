#if os(macOS)
import SwiftUI

/// The Mac shell's unified header band: spans columns 2+3 (the sidebar keeps its
/// own full-height lane), holding the full-width search field and the prominent
/// New Item button — the reference password-manager layout. Suggestions render
/// from `MacRootView` as an overlay so they can float over both columns.
struct MacHeaderBar: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var searchQuery: String
    var searchFocus: FocusState<Bool>.Binding
    let onToggleSidebar: () -> Void
    let onNewItem: (ItemCategory) -> Void

    var body: some View {
        HStack(spacing: Space.s4) {
            // The system window toolbar (and its toggle) is hidden — re-provide it here.
            Button(action: onToggleSidebar) {
                PolarisIcon(Icons.layoutSection, size: 16).themedForeground(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Toggle Sidebar"))
            searchField
            newItemMenu
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: env.theme.active.background))
    }

    private var searchField: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.search, size: 14).themedForeground(.secondary)
            TextField("Search vault", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused(searchFocus)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    PolarisIcon(Icons.close, size: 12).themedForeground(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Color(rgb: env.theme.active.controlBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        // Esc clears + defocuses the search, mirroring the native field.
        .onKeyPress(.escape) {
            searchQuery = ""
            searchFocus.wrappedValue = false
            return .handled
        }
    }

    private var newItemMenu: some View {
        Menu {
            ForEach(ItemCategory.allCases) { category in
                Button { onNewItem(category) } label: {
                    Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
                }
            }
        } label: {
            Label { Text("New Item") } icon: { PolarisIcon(Icons.add) }
        }
        .buttonStyle(.borderedProminent)
        .tint(env.theme.accentColor)
        .accessibilityLabel(Text("New Item"))
    }
}

/// Column-3 header above the item detail: primary Edit action plus the overflow
/// menu (archive) — replaces the detail screen's toolbar, which is hidden along
/// with the window toolbar on the Mac.
struct MacDetailHeader: View {
    @Environment(AppEnvironment.self) private var env
    let item: VaultItem
    let onEdit: () -> Void
    let onArchiveToggle: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            Spacer(minLength: 0)
            Button(action: onEdit) {
                Label { Text("Edit") } icon: { PolarisIcon(Icons.edit, size: 13) }
            }
            .buttonStyle(.bordered)
            Menu {
                Button(action: onArchiveToggle) {
                    Label(item.archived ? "Unarchive" : "Archive", image: Icons.archive)
                }
            } label: {
                PolarisIcon(Icons.moreHorizontal, size: 16).themedForeground(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text("More"))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(Color(rgb: env.theme.active.background))
    }
}

/// Floating suggestion panel under the header's search field (the dropdown in the
/// reference design): top item hits; selecting one opens it in the detail column.
struct MacSearchSuggestionsPanel: View {
    @Environment(AppEnvironment.self) private var env
    let query: String
    let onSelect: (String) -> Void

    private var hits: [VaultItem] {
        Array(env.repository.search(query.trimmingCharacters(in: .whitespaces)).prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text("No results")
                    .vaultType(.subhead).themedForeground(.secondary)
                    .padding(Space.s4)
            } else {
                ForEach(hits) { item in
                    Button { onSelect(item.id) } label: {
                        HStack(spacing: Space.s3) {
                            ItemThumbnail(title: item.title, category: item.category,
                                          iconAsset: item.iconAsset, size: 22)
                            Text(item.title).fontWeight(.semibold).lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(verbatim: "— \(subtitle)")
                                    .themedForeground(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color(rgb: env.theme.active.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .elevation(.level3)
    }
}
#endif
