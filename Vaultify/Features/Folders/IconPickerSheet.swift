import SwiftUI

/// The shared icon picker for Spaces and item avatars — a searchable, sectioned library.
///
/// One component for both so the two stay one visual language; the flat unsearchable grid it
/// replaces could not carry a catalog this size.
struct IconPickerSheet: View {
    /// Currently stored icon name, so the picker can mark it. May be a legacy value.
    let selected: String?
    let onPick: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Wide enough for the 44pt tile plus breathing room, adaptive so iPad and Mac fill the sheet.
    private let columns = [GridItem(.adaptive(minimum: 56), spacing: Space.s3)]

    /// The selection is compared in canonical form: the stored value can be a legacy name
    /// (`dt_folder`) while the catalog offers the SF token, and both must mark the same tile.
    private var selectedCanonical: String? { selected.map(IconResolver.canonical) }

    private var results: [CatalogIcon] { IconCatalog.search(query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VaultSheetScaffold(title: "Choose icon",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    if isSearching {
                        if results.isEmpty {
                            noResults
                        } else {
                            LazyVGrid(columns: columns, spacing: Space.s3) {
                                ForEach(results) { tile($0) }
                            }
                            .padding(.horizontal, Space.gutter)
                            .padding(.vertical, Space.s3)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: Space.s5, pinnedViews: .sectionHeaders) {
                            ForEach(IconCatalog.sections) { section in
                                Section {
                                    LazyVGrid(columns: columns, spacing: Space.s3) {
                                        ForEach(section.icons) { tile($0) }
                                    }
                                    .padding(.horizontal, Space.gutter)
                                } header: {
                                    Text(section.title)
                                        .vaultType(.sectionLabel)
                                        .themedForeground(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, Space.gutter)
                                        .padding(.vertical, Space.s2)
                                        .background(Color(rgb: env.theme.active.groupedBackground))
                                }
                            }
                        }
                        .padding(.vertical, Space.s3)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.s2) {
            VaultIcon(Icons.search, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            TextField("Search icons", text: $query)
                .vaultType(.body)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
                .themedForeground(.primary)
            if isSearching {
                Button { query = "" } label: {
                    VaultIcon(Icons.closeCircle, size: Metric.iconInline)
                        .themedForeground(.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(Color(rgb: env.theme.active.controlBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.s3)
    }

    private var noResults: some View {
        Text("No icons match that search")
            .vaultType(.subhead)
            .themedForeground(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s8)
            .padding(.horizontal, Space.gutter)
    }

    private func tile(_ icon: CatalogIcon) -> some View {
        let isSelected = selectedCanonical == IconResolver.canonical(icon.name)
        return Button {
            onPick(icon.name)
            dismiss()
        } label: {
            VaultIcon(icon.name, size: Metric.iconUtility)
                .themedForeground(isSelected ? .accent : .iconPrimary)
                .frame(width: Metric.iconPickerTile, height: Metric.iconPickerTile)
                .background(isSelected ? env.theme.active.color(.accentSoft) : VaultColors.fill,
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(env.theme.active.color(.accent), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: icon.name))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
