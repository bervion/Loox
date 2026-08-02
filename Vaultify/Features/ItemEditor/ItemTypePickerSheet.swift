import SwiftUI

/// Reusable "what do you want to add" bottom sheet: a plain canvas with the
/// dots ring fronting the vault mark, a search field, up to three recently
/// used templates, then the template registry grouped by family — a duotone
/// glyph, a title, and a short description per row. Presented from Home,
/// Security, and the sidebar.
///
/// The close control lives in the nav-bar toolbar (same as the item editor), so
/// iOS 26 renders it as the standard circular liquid-glass X; the toolbar
/// background is hidden so the canvas reads full-bleed behind it.
struct ItemTypePickerSheet: View {
    /// Called with the editor target for the chosen template; the sheet
    /// dismisses itself first, so the caller can present the editor from the
    /// sheet's `onDismiss`.
    let onSelect: (EditorTarget) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Recently used template kinds (raw IDs, newest first, max three).
    private static let recentsKey = "picker.recentTemplateKinds"

    private var recents: [ItemTemplateDefinition] {
        (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [])
            .compactMap { ItemTemplateRegistry.definition(for: ItemKindID($0)) }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Registry templates matching the query (against the LOCALIZED title and
    /// blurb plus the raw kind, so "ssh", "api" and Vietnamese titles all hit).
    private func matches(_ template: ItemTemplateDefinition) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        let needle = trimmedQuery.lowercased()
        return appString(String.LocalizationValue(template.title)).lowercased().contains(needle)
            || appString(String.LocalizationValue(template.blurb)).lowercased().contains(needle)
            || template.kindID.rawValue.lowercased().contains(needle)
            || template.title.lowercased().contains(needle)
    }

    /// Stable family order for the grouped list.
    private static let familyOrder: [TemplateFamily] = [.common, .developer, .personal, .finance, .files]

    private var groupedTemplates: [(family: TemplateFamily, templates: [ItemTemplateDefinition])] {
        Self.familyOrder.compactMap { family in
            let templates = ItemTemplateRegistry.all.filter { $0.family == family && matches($0) }
            return templates.isEmpty ? nil : (family, templates)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Plain canvas (near-black in dark) — Apple-Account-sheet idiom.
                Color(rgb: env.theme.active.background).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Space.s5) {
                        LooxDotsAvatar(size: 104, revealsOnAppear: true, centerIcon: "dt_vault")
                            .padding(.top, Space.s4)

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("New item")
                                .vaultType(.screenTitle)
                                .themedForeground(.primary)
                            Text("Choose the kind of item to add to your vault.")
                                .vaultType(.subhead)
                                .themedForeground(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.gutter)

                        searchField
                            .padding(.horizontal, Space.gutter)

                        if trimmedQuery.isEmpty, !recents.isEmpty {
                            templateGroup(title: "Recent", templates: Array(recents.prefix(3)))
                        }

                        ForEach(groupedTemplates, id: \.family) { group in
                            templateGroup(title: familyTitle(group.family),
                                          templates: group.templates)
                        }

                        if groupedTemplates.isEmpty {
                            Text("No item types match your search")
                                .vaultType(.subhead)
                                .themedForeground(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Space.s6)
                        }
                    }
                    .padding(.bottom, Space.s8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .platformNavigationBarTitleDisplayMode(.inline)
            .platformHiddenNavigationBarBackground()
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    // Icon-only toolbar button → iOS 26 gives it the circular
                    // liquid-glass close treatment automatically (matches the editor).
                    Button { dismiss() } label: {
                        VaultIcon(Icons.close, size: Metric.iconInline)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .platformPresentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: Space.s2) {
            VaultIcon(Icons.search, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            TextField("Search item types", text: $query)
                .vaultType(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.controlMedium)
        .background(Color(rgb: env.theme.active.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func familyTitle(_ family: TemplateFamily) -> LocalizedStringKey {
        switch family {
        case .common: "Common"
        case .developer: "Developer"
        case .personal: "Personal"
        case .finance: "Finance"
        case .files: "Files"
        }
    }

    private func templateGroup(title: LocalizedStringKey,
                               templates: [ItemTemplateDefinition]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.horizontal, Space.s2)
            VStack(spacing: Space.s3) {
                ForEach(templates, id: \.kindID) { template in
                    typeRow(template)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    private func select(_ template: ItemTemplateDefinition) {
        var recent = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        recent.removeAll { $0 == template.kindID.rawValue }
        recent.insert(template.kindID.rawValue, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(3)), forKey: Self.recentsKey)
        onSelect(.newFromTemplate(template))
        dismiss()
    }

    private func typeRow(_ template: ItemTemplateDefinition) -> some View {
        Button {
            select(template)
        } label: {
            // Outer row centers the chevron vertically; the inner group top-aligns
            // the glyph to the title line.
            HStack(alignment: .center, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s3) {
                    // Brand blue duotone glyph, aligned to the title's top line.
                    VaultIcon(template.avatarIcon, size: 28)
                        .foregroundStyle(Color.looxBlue)
                        .frame(width: Metric.controlSmall, alignment: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(template.title))
                            .vaultType(.headline)
                            .themedForeground(.primary)
                        Text(LocalizedStringKey(template.blurb))
                            .vaultType(.subhead)
                            .themedForeground(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                VaultIcon(Icons.chevronRight, size: 14)
                    .themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
