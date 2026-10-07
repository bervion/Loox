import SwiftUI

/// Local, persona-scoped management. A historical record intentionally has
/// no working URL: the fragment key leaves memory with the creation sheet.
struct ShareLinksScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showChooser = false
    @State private var pendingSelection: MemberItemSelection?
    @State private var selection: MemberItemSelection?

    private var records: [LooxLinkRecord] {
        MemberFeatureProjection.links(env.looxLinks.records.records, ownedItems: env.repository.memberOwnedItems)
    }
    private var createState: CapabilityAvailability { env.capabilities.availability(.shareLink, operation: .create) }
    private var eligibleItems: [VaultItem] {
        MemberFeatureProjection.eligibleItems(env.repository.memberOwnedItems, needsSnapshotFields: true)
    }

    var body: some View {
        List {
            Section {
                Text("Share selected fields with an encrypted link that expires automatically.")
                    .vaultType(.callout).themedForeground(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
                if let persona = env.repository.activePersona {
                    LabeledContent {
                        Text(verbatim: persona.displayName).themedForeground(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: { Text("Profile").themedForeground(.secondaryBody) }
                    .vaultType(.subhead)
                }
                if let message = MemberFeatureAvailability.message(createState) {
                    Text(verbatim: message).vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                } else if eligibleItems.isEmpty {
                    Text("Save an item with readable fields before creating a link.")
                        .vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                if records.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("No links on this device").vaultType(.headline).themedForeground()
                        Text("Create a link to share one of this profile's saved items.")
                            .vaultType(.callout).themedForeground(.secondaryBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Space.s3)
                }
                ForEach(records) { record in
                    NavigationLink {
                        ShareLinkRecordScreen(shareID: record.shareId, personaID: env.repository.activePersona?.id)
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text(verbatim: env.repository.memberOwnedItems.first { $0.id == record.itemId }?.title ?? "")
                                .vaultType(.body).themedForeground()
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Expires \(record.expiresAt.formatted(Date.RelativeFormatStyle(presentation: .named).locale(appResourceLocale)))")
                                .vaultType(.footnote).themedForeground(.secondaryBody)
                                .fixedSize(horizontal: false, vertical: true)
                            if record.oneTime { Text("One-time").vaultType(.caption).themedForeground(.secondaryBody) }
                        }
                        .frame(minHeight: Metric.hitMin, alignment: .leading)
                    }
                }
            } header: { Text("Links within their expiry period") } footer: {
                Text("Only links created on this device appear here. This list does not indicate whether a link has been opened. To share again, create a new link.").themedForeground(.secondaryBody)
                    .vaultType(.footnote)
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(Text("Share Links"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if createState == .available && !eligibleItems.isEmpty {
                Button { showChooser = true } label: {
                    Text("Create Link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .padding(Space.gutter)
                .background(Color(rgb: env.theme.active.groupedBackground))
            }
        }
        .sheet(isPresented: $showChooser, onDismiss: presentSelection) {
            MemberItemChooserSheet(title: "Choose an item") { itemID, personaID in
                pendingSelection = MemberItemSelection(id: itemID, personaID: personaID)
            }
        }
        .sheet(item: $selection) { selected in
            VaultSheetScaffold(title: "Create Link") {
                QuickLinkView(itemID: selected.id, ownerPersonaID: selected.personaID)
            }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in
            showChooser = false; pendingSelection = nil; selection = nil
        }
        .task { await CapabilityHealthProbe.probe(.shareLink, store: env.capabilities) }
    }

    private func presentSelection() {
        defer { pendingSelection = nil }
        guard let pendingSelection, createState == .available,
              env.repository.memberCanUseItem(pendingSelection.id, personaID: pendingSelection.personaID,
                                               needsSnapshotFields: true) else { return }
        selection = pendingSelection
    }
}

private struct ShareLinkRecordScreen: View {
    let shareID: String
    let personaID: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRevoke = false
    @State private var revoking = false
    @State private var error: String?

    private var record: LooxLinkRecord? {
        guard env.repository.activePersona?.id == personaID else { return nil }
        return MemberFeatureProjection.links(env.looxLinks.records.records, ownedItems: env.repository.memberOwnedItems)
            .first { $0.shareId == shareID }
    }

    var body: some View {
        List {
            if let record {
                Section {
                    Text(verbatim: env.repository.memberOwnedItems.first { $0.id == record.itemId }?.title ?? "")
                        .vaultType(.headline).themedForeground()
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Created", value: record.createdAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened).locale(appResourceLocale)))
                        .themedForeground(.primary)
                    LabeledContent("Expires", value: record.expiresAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened).locale(appResourceLocale)))
                        .themedForeground(.primary)
                    if record.oneTime { Text("One-time").vaultType(.subhead).themedForeground(.secondaryBody) }
                }
                .listRowBackground(VaultColors.surface)
                Section {
                    NavigationLink { ItemDetailScreen(itemID: record.itemId) } label: { Text("Open item") }
                        .frame(minHeight: Metric.hitMin)
                } footer: {
                    Text("The original link is no longer held by the app. Create a new link if you need to share this item again.").themedForeground(.secondaryBody)
                }
                .listRowBackground(VaultColors.surface)
                if let error {
                    Section { Text(verbatim: error).vaultType(.callout).themedForeground(.destructive) }
                        .listRowBackground(VaultColors.surface)
                }
                if revoking { Section { ProgressView().frame(maxWidth: .infinity) } }
            } else {
                Text("This link is no longer available in this profile.")
                    .vaultType(.body).themedForeground(.secondaryBody)
            }
        }
        .themedFormBackground()
        .navigationTitle(Text("Share Link"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if record != nil {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button("Revoke Link", role: .destructive) { confirmRevoke = true }
                            .disabled(revoking)
                    } label: {
                        VaultIcon(Icons.moreHorizontal, size: Metric.iconUtility)
                            .themedForeground(.iconPrimary)
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                    }.accessibilityLabel(Text("Manage share link"))
                }
            }
        }
        .confirmationDialog("Revoke Link?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revoke Link", role: .destructive) { Task { await revoke() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Anyone who has the link loses access after revocation succeeds.") }
    }

    private func revoke() async {
        guard !revoking, env.session.state == .unlocked, let record else { return }
        revoking = true; error = nil
        defer { revoking = false }
        do {
            try await env.looxLinks.revoke(record)
            dismiss()
        } catch {
            self.error = SharingErrorMessage.text(for: error)
            Haptics.error()
        }
    }
}
