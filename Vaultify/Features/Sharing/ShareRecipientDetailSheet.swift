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
    /// Device scope of the LIVE grant — preserved on republish so a capability
    /// edit never silently downgrades single-device to multi.
    @State private var editingDeviceScope: DeviceScope = .multi
    /// Passkey hand-over awaiting the irreversibility confirmation (INV-08).
    @State private var pendingHandOver: (id: String, capability: FieldCapability)?

    private var item: VaultItem? { env.repository.item(id: share.itemId) }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: share.zoneName) }

    /// This item's passkeys (same repository source + RP rule as the detail
    /// screen and the create sheet).
    private var itemPasskeys: [PasskeyInfo] {
        guard let item else { return [] }
        return env.repository.passkeys.filter { item.matchesRelyingParty($0.relyingParty) }
    }

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
            Button("Revoke access", role: .destructive) { Task { await revoke() } }
        } message: {
            Text("They can't request codes anymore. Values that were already shared stay on their device.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .confirmationDialog("Hand over this passkey?", isPresented: Binding(
            get: { pendingHandOver != nil }, set: { if !$0 { pendingHandOver = nil } }),
            titleVisibility: .visible) {
            Button("Hand over: can't be taken back", role: .destructive) {
                if let pending = pendingHandOver { capabilities?[pending.id] = pending.capability }
                pendingHandOver = nil
            }
        } message: {
            Text("They'll be able to use it without asking you, on their own device. Revoking later only stops updates; a key already handed over can't be pulled back.")
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
                else { Text("Send update now").frame(maxWidth: .infinity) }
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
                ForEach(itemPasskeys) { passkey in
                    PasskeyCapabilityRow(passkey: passkey, capability: passkeyBinding(for: passkey),
                                         requestHandOver: { proposed in
                                             pendingHandOver = (PasskeySlot.slotId(
                                                 credentialID: passkey.credentialID), proposed)
                                         })
                }
                Button {
                    Task { await applyCapabilities() }
                } label: {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Apply changes").frame(maxWidth: .infinity) }
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
                Text("Revoke access").frame(maxWidth: .infinity)
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

    private func passkeyBinding(for passkey: PasskeyInfo) -> Binding<FieldCapability> {
        let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
        return Binding(get: { capabilities?[slot] ?? .passkey(.none) },
                       set: { capabilities?[slot] = $0 })
    }

    // MARK: Actions

    /// Seed the capability editor from the LIVE grant (never a local guess).
    private func loadGrant() async {
        guard share.fingerprintConfirmed, let item,
              let grant = try? await env.approvalShare.fetchGrantFresh(
                  zoneID: zoneID, forItemId: item.id,
                  nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
        else { return }
        loadedGrant = grant
        // Preserve the live grant's device scope on any republish (INV-04).
        editingDeviceScope = grant.allowedDeviceKeyBindings.isEmpty ? .multi : .single
        var seeded: [String: FieldCapability] = [:]
        for field in item.fields {
            seeded[field.id] = grant.capabilities[field.id]
                ?? (field.kind == .totp ? .totp(.none) : .value(.none))
        }
        for passkey in itemPasskeys {
            let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
            seeded[slot] = grant.capabilities[slot] ?? .passkey(.none)
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
                itemId: item.id,
                title: item.title.isEmpty ? appString("Shared item") : item.title,
                websiteHost: item.urlField?.value.isEmpty == false
                    ? URL(string: item.urlField!.value)?.host : nil,
                displayFields: Self.displayFields(for: item),
                zoneID: zoneID, nowUnixMs: nowUnixMs)
            try await env.approvalShare.republishSharedValues(
                itemId: item.id, values: Self.currentValues(for: item),
                zoneID: zoneID, nowUnixMs: nowUnixMs)
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
            // Re-seal to the recipient's CURRENT identity/devices. The shared
            // composer assembles fields + passkeys + device scope exactly like
            // the create ceremony and preserves this share's device scope — the
            // edit path can no longer drop passkeys or widen single→multi.
            let profile = try await env.approvalShare.fetchParticipantProfile(zoneID: zoneID)
            _ = try await SharedGrantComposer.publish(
                service: env.approvalShare, store: env.store, item: item,
                capabilities: capabilities, itemPasskeys: itemPasskeys,
                vaultKey: env.session.vaultKey,
                profile: SharedGrantComposer.RecipientProfile(
                    participantPubKey: profile.participantPubKey,
                    deviceSigningKeys: profile.deviceSigningKeys,
                    deviceHPKEDirectory: profile.deviceHPKEDirectory),
                deviceScope: editingDeviceScope, epoch: grant.epoch + 1,
                zoneID: zoneID, nowUnixMs: nowUnixMs)
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
