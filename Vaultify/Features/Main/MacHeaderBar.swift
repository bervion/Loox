#if os(macOS)
import SwiftUI

/// The Mac shell's toolbar search field — installed as a `.principal` item in the
/// system unified toolbar, so search shares one row with the traffic lights, the
/// native sidebar toggle, and the New Item button (the reference layout).
/// Suggestions render from `MacRootView` as an overlay under the toolbar.
struct MacToolbarSearchField: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var searchQuery: String
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
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
                        // Mac is pointer-driven (no 44pt thumb-target rule), but a bare
                        // 12pt glyph is still too fussy to click precisely — pad the hit
                        // box out to the toolbar-icon optical size without growing the
                        // visible glyph.
                        .contentShape(Rectangle().inset(by: -(Metric.iconUtility - 12) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(height: 28)
        // Wide, flexible field: the principal toolbar slot grants what the window allows.
        .frame(minWidth: 280, idealWidth: 560, maxWidth: 720)
        .background(Color(rgb: env.theme.active.controlBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        // Esc clears + defocuses the search, mirroring the native field.
        .onKeyPress(.escape) {
            searchQuery = ""
            searchFocus.wrappedValue = false
            return .handled
        }
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
                    // Same pointer-target padding as the search field's clear button —
                    // click box grows, visible glyph stays 16pt.
                    .contentShape(Rectangle().inset(by: -(Metric.iconUtility - 16) / 2))
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
                            // Title + subtitle stack on two lines — real layout, not an
                            // em-dash glue character, per the copy standard.
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).fontWeight(.semibold).lineLimit(1)
                                if let subtitle = item.subtitle {
                                    Text(verbatim: subtitle)
                                        .vaultType(.footnote).themedForeground(.secondary).lineLimit(1)
                                }
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
