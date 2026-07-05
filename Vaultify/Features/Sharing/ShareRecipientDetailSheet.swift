import CloudKit
import SwiftUI

/// Owner-side management for ONE recipient of an item: who/status/since,
/// update mode (automatic on every edit vs. manual push), per-field
/// capability editing on the LIVE share (e.g. hide the password later but
/// keep TOTP + username — republishes the grant with a bumped epoch), and
/// revocation scoped to exactly this person.
struct ShareRecipientDetailSheet: View {
    let share: ItemShareRecord
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var confirmRevoke = false
    @State private var errorMessage: String?
    @State private var busy = false
    /// Loaded from the live grant; nil while fetching (capability editor hidden).
    @State private var capabilities: [String: FieldCapability]?
    @State private var loadedGrant: AccessGrant?
    @State private var statusNote: String?

    private var item: VaultItem? { env.repository.item(id: share.itemId) }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: share.zoneName) }

    var body: some View {
        VaultSheetScaffold(title: "Share Details") {
            Form {
                infoSection
                if share.fingerprintConfirmed {
                    updateModeSection
                    capabilitySection
                }
                revokeSection
            }
        }
        .task { await loadGrant() }
        .confirmationDialog("Revoke access?", isPresented: $confirmRevoke,
                            titleVisibility: .visible) {
            Button("Revoke Access", role: .destructive) { Task { await revoke() } }
        } message: {
            Text("They can't request codes anymore. Values that were already shared stay on their device.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var infoSection: some View {
        Section {
            LabeledContent("Recipient") {
                Text(verbatim: share.recipientLabel)
                    .themedForeground(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("Status") {
                Text(share.fingerprintConfirmed ? "Active" : "Pending")
                    .themedForeground(share.fingerprintConfirmed ? .success : .secondary)
            }
            LabeledContent("Shared") {
                Text(Date(timeIntervalSince1970: Double(share.createdAtUnixMs) / 1000)
                    .formatted(date: .abbreviated, time: .shortened))
                    .themedForeground(.secondary)
            }
            if let statusNote {
                Text(verbatim: statusNote)
                    .vaultType(.footnote).themedForeground(.success)
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private var updateModeSection: some View {
        Section {
            Toggle("Update automatically", isOn: Binding(
                get: { share.isAutoUpdate },
                set: { enabled in
                    var updated = share
                    updated.autoUpdate = enabled
                    env.sharingStore.upsert(updated)
                }))
            Button {
                Task { await sendUpdateNow() }
            } label: {
                if busy { ProgressView().frame(maxWidth: .infinity) }
                else { Text("Send Update Now").frame(maxWidth: .infinity) }
            }
            .disabled(busy)
        } footer: {
            Text("When automatic updates are off, your edits reach this person only when you tap Send Update Now.")
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private var capabilitySection: some View {
        if let item, capabilities != nil {
            Section {
                ForEach(item.fields) { field in
                    FieldCapabilityRow(field: field, capability: binding(for: field))
                }
                Button {
                    Task { await applyCapabilities() }
                } label: {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Apply Changes").frame(maxWidth: .infinity) }
                }
                .disabled(busy)
            } header: {
                Text("What they can use")
            } footer: {
                Text("Turning a field off removes it from their device on their next refresh. Values they already saw can't be taken back.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private var revokeSection: some View {
        Section {
            Button(role: .destructive) {
                confirmRevoke = true
            } label: {
                Text("Revoke Access").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .disabled(busy)
        }
        .listRowBackground(VaultColors.surface)
    }

    private func binding(for field: DynamicField) -> Binding<FieldCapability> {
        Binding(
            get: { capabilities?[field.id] ?? (field.kind == .totp ? .totp(.none) : .value(.none)) },
            set: { capabilities?[field.id] = $0 })
    }

    // MARK: Actions

    /// Seed the capability editor from the LIVE grant (never a local guess).
    private func loadGrant() async {
        guard share.fingerprintConfirmed,
              let grant = try? await env.approvalShare.fetchGrantFresh(zoneID: zoneID),
              let item else { return }
        loadedGrant = grant
        var seeded: [String: FieldCapability] = [:]
        for field in item.fields {
            seeded[field.id] = grant.capabilities[field.id]
                ?? (field.kind == .totp ? .totp(.none) : .value(.none))
        }
        capabilities = seeded
    }

    /// Manual propagation: current values + display metadata, this zone only.
    private func sendUpdateNow() async {
        guard let item else { return }
        busy = true
        defer { busy = false }
        do {
            let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
            try await env.approvalShare.republishDisplayEnvelope(
                title: item.title.isEmpty ? appString("Shared item") : item.title,
                websiteHost: item.urlField?.value.isEmpty == false
                    ? URL(string: item.urlField!.value)?.host : nil,
                displayFields: Self.displayFields(for: item),
                zoneID: zoneID, nowUnixMs: nowUnixMs)
            try await env.approvalShare.republishSharedValues(
                values: Self.currentValues(for: item), zoneID: zoneID)
            statusNote = appString("Update sent.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Republish the grant with the edited capabilities (epoch bump): removed
    /// fields' blobs are deleted server-side; the recipient's projection and
    /// AutoFill cache follow on their next push-driven refresh.
    private func applyCapabilities() async {
        guard let item, let grant = loadedGrant, let capabilities else { return }
        busy = true
        defer { busy = false }
        do {
            let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sharedValues: [String: Data] = Dictionary(uniqueKeysWithValues:
                item.fields.compactMap { field in
                    guard capabilities[field.id]?.isSharedValue == true,
                          !field.isExtraProtected else { return nil }
                    return (field.id, Data(field.value.utf8))
                })
            _ = try await env.approvalShare.publishGrant(
                itemId: item.id,
                capabilities: capabilities,
                sharedValues: sharedValues,
                displayTitle: item.title.isEmpty ? appString("Shared item") : item.title,
                displayWebsiteHost: item.urlField?.value.isEmpty == false
                    ? URL(string: item.urlField!.value)?.host : nil,
                displayFields: Self.displayFields(for: item, capabilities: capabilities),
                participantPubKey: grant.participantPubKey,
                pinnedDeviceSigningKeys: grant.pinnedDeviceSigningKeys,
                epoch: grant.epoch + 1, zoneID: zoneID, nowUnixMs: nowUnixMs)
            statusNote = appString("Access updated.")
            await loadGrant()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke() async {
        busy = true
        defer { busy = false }
        do {
            try await env.approvalShare.revoke(zoneName: share.zoneName,
                                               inviteRecordName: share.inviteRecordName)
            if let dropRecordName = share.dropRecordName {
                await env.inviteLinks.deleteInvite(recordName: dropRecordName)
            }
            env.sharingStore.remove(zoneName: share.zoneName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Helpers

    /// Meta for the sealed display envelope. With `capabilities` present only
    /// granted fields are described; otherwise every shareable field (the
    /// manual-update path can't know per-share grants without a fetch).
    private static func displayFields(for item: VaultItem,
                                      capabilities: [String: FieldCapability]? = nil)
        -> [String: SharedDisplayEnvelope.FieldMeta] {
        Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            if field.isExtraProtected { return nil }
            if let capabilities,
               !(capabilities[field.id]?.isSharedValue == true
                 || capabilities[field.id]?.isAskEachTimeTOTP == true) { return nil }
            return (field.id, SharedDisplayEnvelope.FieldMeta(label: field.label,
                                                              kind: field.kind.rawValue))
        })
    }

    private static func currentValues(for item: VaultItem) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            field.isExtraProtected || field.value.isEmpty
                ? nil : (field.id, Data(field.value.utf8))
        })
    }
}
