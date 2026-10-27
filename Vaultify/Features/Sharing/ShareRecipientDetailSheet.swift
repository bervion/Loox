import CloudKit
import SwiftUI

/// Owner-side management for ONE recipient of an item: who/status/since,
/// per-field capability editing on the LIVE share (e.g. hide the password later
/// but keep TOTP + username — republishes the grant with a bumped epoch), the
/// update mode (automatic on every edit vs. manual), and revocation scoped to
/// exactly this person.
///
/// One Apply in the toolbar commits everything pending. There used to be two
/// buttons, "Send update now" (re-seal the item's current values) and "Apply
/// changes" (republish the grant), and the second already did all of the
/// first: it re-seals current values with the grant. Two buttons for one job
/// only made owners guess which one their change needed.
struct ShareRecipientDetailSheet: View {
    let share: ItemShareRecord
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var confirmRevoke = false
    /// Realtime-action offline notice (revoking is only true once iCloud says so).
    @State private var showRevokeOfflineNotice = false
    @State private var errorMessage: String?
    /// A publish or a revoke is in flight.
    @State private var busy = false
    /// Seeded from the live grant; nil while fetching (capability editor hidden).
    @State private var draft: ShareCapabilityDraft?
    @State private var loadedGrant: AccessGrant?
    @State private var statusNote: String?
    /// Device scope of the LIVE grant — preserved on republish so a capability
    /// edit never silently downgrades single-device to multi.
    @State private var editingDeviceScope: DeviceScope = .multi
    /// The hand-over alert (INV-08) is up.
    @State private var confirmHandOver = false
    /// A confirmed hand-over failed to publish; the pick stays parked for a retry.
    @State private var handOverError: String?
    /// The live grant could not be read (offline, throttled). Distinct from
    /// "still loading" so the sheet never implies the share grants nothing.
    @State private var grantUnavailable = false

    /// `draft` seeds the editor without a grant fetch (snapshot rendering).
    init(share: ItemShareRecord, draft: ShareCapabilityDraft? = nil) {
        self.share = share
        _draft = State(initialValue: draft)
    }

    /// The store's current copy of this share. `share` is the snapshot the
    /// presenting screen captured, so it never saw the auto-update toggle flip
    /// or the grant id an Apply publishes.
    private var liveShare: ItemShareRecord {
        env.sharingStore.shares.first { $0.id == share.id } ?? share
    }

    private var item: VaultItem? { env.repository.item(id: share.itemId) }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: share.zoneName) }

    /// This item's passkeys (same repository source + RP rule as the detail
    /// screen and the create sheet).
    private var itemPasskeys: [PasskeyInfo] {
        guard let item else { return [] }
        return env.repository.passkeys.filter { item.matchesRelyingParty($0.relyingParty) }
    }

    /// Covers both modes: with automatic updates off nothing pushes edits,
    /// and with them on a push that failed (offline) is never retried by itself.
    private var hasUnsentItemEdits: Bool {
        guard let item, let grant = loadedGrant else { return false }
        return ShareCapabilityDraft.hasUnsentItemEdits(
            itemUpdatedAt: item.updatedAt,
            lastSentAtUnixMs: max(grant.createdAtUnixMs, liveShare.lastSentAtUnixMs ?? 0))
    }

    private var hasPendingChanges: Bool { draft?.hasChanges == true || hasUnsentItemEdits }

    var body: some View {
        VaultSheetScaffold(title: "Share Details", trailing: { trailingToolbar }) {
            form
        }
        // Mid-publish the sheet must stay up to report how it ended.
        .interactiveDismissDisabled(busy)
        .task { if draft == nil { await loadGrant() } }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .animation(Motion.standard, value: confirmRevoke)
    }

    // MARK: Toolbar

    /// Apply, or the spinner while a publish (Apply or a confirmed hand-over)
    /// is in flight.
    @ViewBuilder private var trailingToolbar: some View {
        if liveShare.fingerprintConfirmed, draft != nil {
            if busy {
                ProgressView()
            } else {
                Button {
                    Task { await apply() }
                } label: {
                    Text("Apply").fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                // Not while "Stop sharing" waits for its answer: a publish
                // finishing after the revoke would put the grant back.
                .disabled(!hasPendingChanges || confirmRevoke)
            }
        }
    }

    // MARK: Sections

    private var form: some View {
        Form {
            infoSection
            if liveShare.fingerprintConfirmed {
                capabilitySection
                updateModeSection
            }
            revokeSection
        }
        // A pick made while a publish is in flight would be overwritten when
        // it lands, and a revoke racing it could be undone by it.
        .disabled(busy)
        .shareHandOverConfirmation(
            isPresented: $confirmHandOver, pending: draft?.pendingHandOver,
            onConfirm: { Task { await handOver() } },
            onCancel: { draft?.cancelHandOver() })
        .alert("Couldn't hand over", isPresented: Binding(
            get: { handOverError != nil }, set: { if !$0 { handOverError = nil } })) {
            Button("Try again") { Task { await handOver() } }
            Button("Cancel", role: .cancel) { draft?.cancelHandOver() }
        } message: {
            Text(verbatim: handOverError ?? "")
        }
    }

    private var infoSection: some View {
        Section {
            // The sheet is reached from a PERSON as well as from an item, so it
            // has to name the item it is about. Reached from the item screen the
            // identity used to be implicit; reached from Family nothing on
            // screen said which of several shared items was being configured.
            if let item {
                LabeledContent {
                    Text(verbatim: item.title.isEmpty ? appString("Untitled") : item.title)
                        .themedForeground(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } label: {
                    Label {
                        Text("Item")
                    } icon: {
                        VaultIcon(item.category.avatarIcon, size: Metric.iconInline)
                    }
                }
            }
            LabeledContent("Recipient") {
                Text(verbatim: share.recipientLabel)
                    .themedForeground(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("Status") {
                Text(liveShare.fingerprintConfirmed ? "Active" : "Pending")
                    .themedForeground(liveShare.fingerprintConfirmed ? .success : .secondary)
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

    @ViewBuilder private var capabilitySection: some View {
        if grantUnavailable {
            Section {
                VaultInfoBanner(.warning,
                                text: "Can't read what they can use right now. Check your connection and reopen this screen.")
                    .inList()
            }
            .listRowBackground(Color.clear)
        } else if let item, let draft {
            Section {
                ForEach(item.fields) { field in
                    FieldCapabilityRow(field: field, item: item,
                                       capability: draft.capability(for: field.id) ?? .off(for: field),
                                       onSelect: { select($0, for: field.id) })
                }
                ForEach(itemPasskeys) { passkey in
                    let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
                    PasskeyCapabilityRow(passkey: passkey,
                                         capability: draft.capability(for: slot) ?? .passkey(.none),
                                         onSelect: { select($0, for: slot) })
                }
            } header: {
                Text("What they can use")
            } footer: {
                Text("Turning a field off removes it from their device on their next refresh. Values they already saw can't be taken back.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private var updateModeSection: some View {
        Section {
            Toggle("Update automatically", isOn: Binding(
                get: { liveShare.isAutoUpdate },
                set: { enabled in
                    var updated = liveShare
                    updated.autoUpdate = enabled
                    env.sharingStore.upsert(updated)
                }))
        } footer: {
            // Says why Apply is lit when no capability changed.
            if hasUnsentItemEdits {
                Text("Your latest edits haven't reached them yet. Tap Apply to send them.")
            } else {
                Text("When automatic updates are off, your edits reach this person only when you tap Apply.")
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private var revokeSection: some View {
        Section {
            Button(role: .destructive) {
                // Realtime CloudKit action: offline, explain instead of
                // surfacing a raw iCloud error mid-flow.
                if env.reachability.hasSatisfiedNetworkPath {
                    confirmRevoke = true
                } else {
                    Haptics.warning()
                    showRevokeOfflineNotice = true
                }
            } label: {
                Text("Stop sharing this item").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedDestructive)
            .disabled(busy)
            .onlineActionAppearance(online: env.reachability.hasSatisfiedNetworkPath)
            .offlineActionNotice(isPresented: $showRevokeOfflineNotice,
                                 message: "You need an internet connection to revoke access. The share stays active until then.")
            // Honest about BOTH the scope and the limit: only this item goes
            // away, and anything already handed over cannot be pulled back.
            if confirmRevoke {
                InlineConfirm(
                    message: "They lose access to this item. Anything else you shared with them stays. Values already handed over stay on their device.",
                    confirmTitle: "Stop sharing",
                    onCancel: { confirmRevoke = false },
                    onConfirm: {
                        confirmRevoke = false
                        Task { await revoke() }
                    })
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    // MARK: Actions

    /// Every row's mode change. A hand-over parks in the draft and asks first.
    private func select(_ capability: FieldCapability, for slot: String) {
        draft?.select(capability, for: slot)
        if draft?.pendingHandOver != nil { confirmHandOver = true }
    }

    /// Seed the capability editor from the LIVE grant (never a local guess).
    ///
    /// A failure here used to return silently, and because the editor is hidden
    /// while the draft is nil, an offline or throttled owner saw a sheet that
    /// looked like the share granted nothing at all, with Revoke as the only
    /// control. Say what happened instead.
    private func loadGrant() async {
        guard share.fingerprintConfirmed, let item else { return }
        grantUnavailable = false
        guard let grant = try? await env.approvalShare.fetchGrantFresh(
                  zoneID: zoneID, forItemId: item.id,
                  nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
        else {
            grantUnavailable = true
            return
        }
        loadedGrant = grant
        // Preserve the live grant's device scope on any republish (INV-04).
        editingDeviceScope = grant.allowedDeviceKeyBindings.isEmpty ? .multi : .single
        var seeded: [String: FieldCapability] = [:]
        for field in item.fields {
            seeded[field.id] = grant.capabilities[field.id] ?? .off(for: field)
        }
        for passkey in itemPasskeys {
            let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
            seeded[slot] = grant.capabilities[slot] ?? .passkey(.none)
        }
        draft = ShareCapabilityDraft(published: seeded)
    }

    /// Commit every pending pick, and the item's current content with them.
    private func apply() async {
        guard let draft else { return }
        do {
            if try await publish(draft.selection) {
                statusNote = appString("Access updated.")
            }
        } catch {
            errorMessage = SharingErrorMessage.text(for: error)
        }
    }

    /// A confirmed hand-over publishes at once, on its own: the grant as it
    /// stands plus the hand-over. Other picks stay unsaved for Apply. The
    /// row's mode ("Secret handed over") and the status line say it landed;
    /// a failure asks again with the system alert.
    private func handOver() async {
        guard let pending = draft?.pendingHandOver,
              let capabilities = draft?.publishedConfirmingHandOver else { return }
        do {
            if try await publish(capabilities) {
                statusNote = PasskeySlot.isPasskeySlot(pending.slot)
                    ? appString("Key handed over") : appString("Secret handed over")
            }
        } catch {
            handOverError = SharingErrorMessage.text(for: error)
        }
    }

    /// Republish the grant with `capabilities` (epoch bump). The same publish
    /// re-seals the item's CURRENT values and display metadata, so it also
    /// delivers edits a manual-update share is waiting for. Removed fields'
    /// blobs are deleted server-side; the recipient's projection and AutoFill
    /// cache follow on their next push-driven refresh. Returns false when
    /// there was nothing to publish against (no live grant yet, or busy).
    private func publish(_ capabilities: [String: FieldCapability]) async throws -> Bool {
        guard !busy, let item, let grant = loadedGrant else { return false }
        busy = true
        defer { busy = false }
        let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Re-seal to the recipient's CURRENT identity/devices. The shared
        // composer assembles fields + passkeys + device scope exactly like
        // the create ceremony and preserves this share's device scope — the
        // edit path can no longer drop passkeys or widen single→multi.
        let profile = try await env.approvalShare.fetchParticipantProfile(zoneID: zoneID)
        let published = try await SharedGrantComposer.publish(
            service: env.approvalShare, store: env.store, item: item,
            capabilities: capabilities, itemPasskeys: itemPasskeys,
            vaultKey: env.session.vaultKey,
            profile: SharedGrantComposer.RecipientProfile(
                participantPubKey: profile.participantPubKey,
                deviceSigningKeys: profile.deviceSigningKeys,
                deviceHPKEDirectory: profile.deviceHPKEDirectory),
            deviceScope: editingDeviceScope, epoch: grant.epoch + 1,
            zoneID: zoneID, nowUnixMs: nowUnixMs)
        loadedGrant = published
        draft?.didPublish(capabilities)
        // The publish minted a new grant id and superseded the old grant,
        // and it delivered the item's current content. Skipped when the
        // share was removed meanwhile, so it is never written back.
        if var updated = env.sharingStore.shares.first(where: { $0.id == share.id }) {
            updated.grantId = published.id
            updated.lastSentAtUnixMs = published.createdAtUnixMs
            env.sharingStore.upsert(updated)
        }
        return true
    }

    /// Whether this share is the only thing left in its zone. A zone holds one
    /// item-share per grant, and a Space fan-out deliberately puts many items
    /// into ONE zone per person — so the zone may only be torn down when this
    /// is the last item in it.
    private var isLastShareInZone: Bool {
        env.sharingStore.shares.filter { $0.zoneName == share.zoneName }.count <= 1
    }

    /// Revoke THIS item only.
    ///
    /// This used to call `revoke(zoneName:)`, which deletes the whole record
    /// zone, so revoking one item silently revoked every other item shared with
    /// the same person — while the dialog promised only that they could no
    /// longer request codes.
    private func revoke() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if isLastShareInZone {
                // Nothing else lives here: drop the zone so the recipient loses
                // the share entirely and the invite artifacts are GC'd.
                try await env.approvalShare.revoke(zoneName: share.zoneName,
                                                   inviteRecordName: share.inviteRecordName)
                if let dropRecordName = share.dropRecordName {
                    await env.inviteLinks.deleteInvite(recordName: dropRecordName)
                }
            } else {
                // By item, not by a stored grant id: every Apply mints a new
                // grant, so a remembered id (or one from another device) can
                // name a grant that is already gone, and revoking it deleted
                // nothing while this sheet reported success.
                try await env.approvalShare.revokeGrants(forItemId: share.itemId, zoneID: zoneID)
            }
            env.sharingStore.remove(zoneName: share.zoneName, itemId: share.itemId)
            dismiss()
        } catch {
            errorMessage = SharingErrorMessage.text(for: error)
        }
    }
}
