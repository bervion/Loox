import SwiftUI

/// A destination for the feature rather than a notification inbox. Historical
/// rows describe local attempts and can neither replay nor inspect a session.
struct SendToBrowserScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showChooser = false
    @State private var pendingSelection: MemberItemSelection?
    @State private var selection: MemberItemSelection?

    private var exposureVisible: Bool {
        QuickViewExposureProvider.entryVisible(manifestExposure: env.capabilities.quickViewExposure)
    }
    private var createState: CapabilityAvailability { env.capabilities.availability(.quickView, operation: .create) }
    private var eligibleItems: [VaultItem] {
        MemberFeatureProjection.eligibleItems(env.repository.memberOwnedItems, needsSnapshotFields: true)
    }
    private var attempts: [QuickViewHistoryRow] {
        MemberFeatureProjection.browserAttempts(env.quickViewHistory.rows, ownedItems: env.repository.memberOwnedItems)
    }

    var body: some View {
        List {
            Section {
                Text("Open the Loox viewer in your browser, then scan its QR code or enter its code. You choose which fields to send.")
                    .vaultType(.callout).themedForeground(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: QuickViewConfig.apiBase.appending(path: "v1/quick-view/open").absoluteString)
                    .vaultType(.footnote).themedForeground(.secondaryBody)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let persona = env.repository.activePersona {
                    LabeledContent {
                        Text(verbatim: persona.displayName).themedForeground(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: { Text("Profile").themedForeground(.secondaryBody) }
                    .vaultType(.subhead)
                }
                if !exposureVisible {
                    Text("Send to Browser is not available for this app version yet.")
                        .vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let message = MemberFeatureAvailability.message(createState) {
                    Text(verbatim: message).vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                } else if eligibleItems.isEmpty {
                    Text("Save an item with readable fields before sending it to a browser.")
                        .vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(VaultColors.surface)
            Section {
                if attempts.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("No browser attempts on this device").vaultType(.headline).themedForeground()
                        Text("Completed, cancelled, and failed attempts appear here after you use this feature.")
                            .vaultType(.callout).themedForeground(.secondaryBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Space.s3)
                }
                ForEach(attempts) { row in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(verbatim: env.repository.memberOwnedItems.first { $0.id == row.itemID }?.title ?? "")
                            .vaultType(.body).themedForeground()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(resultTitle(row.result).inAppLocalized).vaultType(.subhead).themedForeground(.secondaryBody)
                        Text(verbatim: row.timestamp.formatted(
                            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(appResourceLocale)))
                            .vaultType(.footnote).themedForeground(.secondaryBody)
                    }
                    .frame(minHeight: Metric.hitMin, alignment: .leading)
                }
            } header: { Text("Recent attempts") } footer: {
                Text("History is stored on this device. It does not show browser activity or retain the fields, codes, or session keys you sent.").themedForeground(.secondaryBody)
                    .vaultType(.footnote)
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(Text("Send to Browser"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if exposureVisible && createState == .available && !eligibleItems.isEmpty {
                Button { showChooser = true } label: { Text("Send to Browser").frame(maxWidth: .infinity) }
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
            if let item = env.repository.memberOwnedItems.first(where: { $0.id == selected.id }) {
                QuickViewEntryChooserSheet(itemID: selected.id,
                                           defaultSelectedFieldIDs: LooxLinkEnvelope.defaultSelectedFieldIDs(of: item),
                                           ownerPersonaID: selected.personaID)
            }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in
            showChooser = false; pendingSelection = nil; selection = nil
        }
        .task { await CapabilityHealthProbe.probe(.quickView, store: env.capabilities) }
    }

    private func presentSelection() {
        defer { pendingSelection = nil }
        guard let pendingSelection, exposureVisible, createState == .available,
              env.repository.memberCanUseItem(pendingSelection.id, personaID: pendingSelection.personaID,
                                               needsSnapshotFields: true) else { return }
        selection = pendingSelection
    }

    private func resultTitle(_ result: QuickViewHistoryResult) -> LocalizedStringResource {
        switch result {
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}
