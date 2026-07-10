import CloudKit
import SwiftUI

/// Owner share-config flow: pick a recipient (looked-up iCloud identity, no
/// bearer semantics), set per-field capability, create the CKShare, wait for
/// the recipient to accept + publish their identity, run the one-time
/// fingerprint ceremony, then publish the signed grant + sealed blobs.
/// Fail-closed at the door: no iCloud account or no notification permission →
/// the flow never starts (ADR-2).
struct ShareAccessSheet: View {
    let itemID: String
    /// Resume entry (from the Notifications "Shares you sent" list): open
    /// straight into the approval config with this recipient pre-filled, so a
    /// share left pending after a dismiss/relaunch is continued without
    /// re-choosing the path or retyping the email. Create Share reuses the
    /// existing zone (matched by recipient), so no duplicate share is minted.
    var resumeEmail: String? = nil
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        /// Entry: quick link (encrypted snapshot, opens anywhere) vs
        /// approval-based iCloud share (the pre-existing flow).
        case choose
        case quickLink
        case checking
        case blocked(ApprovalPrerequisites.Blocker)
        case config
        case creating
        // `shareURL` = pretty invite link (UI); `rawShareURL` = the CKShare
        // URL the rendezvous envelope needs (drop retries while waiting).
        case waiting(zoneID: CKRecordZone.ID, shareURL: URL?, rawShareURL: URL?)
        case fingerprint(zoneID: CKRecordZone.ID, code: String,
                         profile: (participantPubKey: Data, deviceSigningKeys: [Data],
                                   deviceHPKEDirectory: [DeviceHPKEDirectoryEntry], createdAtUnixMs: Int64))
        case publishing
        case done
        case failed(String)
    }

    @State private var step: Step = .choose
    @State private var recipientEmail = ""
    @State private var capabilities: [String: FieldCapability] = [:]
    /// Device scope (P03b): OFF = single-device — values sealed exclusively
    /// to the recipient's first-enrolled device key (crypto-enforced, INV-04).
    @State private var allowMultipleDevices = true
    /// Hand-over selection (TOTP seed / passkey key) awaiting the
    /// irreversibility confirmation (INV-08). Applied only on confirm.
    @State private var pendingHandOver: (id: String, capability: FieldCapability)?
    /// Share pending the destructive revoke confirmation.
    @State private var revokeTarget: ItemShareRecord?
    /// iMessage compose (recipient pre-filled) for the invite link.
    @State private var showMessageCompose = false
    /// A rendezvous drop reached the recipient's armed inbox — their device
    /// will surface the invite by itself; the link is now just a backup.
    @State private var autoInviteSent = false
    /// The bounded poll ran out — surface that waiting continues manually.
    @State private var pollExhausted = false
    /// One-shot guard so the resume entry seeds the config exactly once.
    @State private var didAutoResume = false

    private var item: VaultItem? { env.repository.item(id: itemID) }

    /// This item's passkeys (matched by relying party, same rule AND same
    /// source the detail screen uses). Reads the repository's already-decrypted
    /// list rather than re-decrypting via the live Vault Key: the config form
    /// renders item fields straight from the decrypted item, so gating the
    /// passkey rows on a live key made them vanish whenever the key wasn't
    /// momentarily available even though the detail screen still showed them.
    private var itemPasskeys: [PasskeyInfo] {
        guard let item else { return [] }
        return env.repository.passkeys
            .filter { item.matchesRelyingParty($0.relyingParty) }
    }

    private var hasGrantedCapability: Bool {
        capabilities.values.contains { $0.grantsAnything }
    }

    private var normalizedEmail: String {
        recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Every zone this owner ever shared to the SAME recipient — the accepted
    /// ones carry the opaque userRecordID the rendezvous drop needs.
    private var recipientZoneNames: [String] {
        env.sharingStore.shares
            .filter { $0.recipientLabel.lowercased() == normalizedEmail }
            .map(\.zoneName)
    }

    /// Non-nil while the sheet should poll for the recipient's profile.
    /// Driving `.task(id:)` off this makes cancellation structural — the poll
    /// dies with the view or the step, never leaking (review H1).
    private var pollingZoneName: String? {
        if case .waiting(let zoneID, _, _) = step { return zoneID.zoneName }
        return nil
    }

    /// Live lifecycle of the share being waited on — drives the waiting copy so
    /// an accepted-but-not-yet-published recipient reads as "finishing on their
    /// device" instead of the misleading "waiting for them to accept".
    private var waitingStatus: ShareLifecycle? {
        guard case .waiting(let zoneID, _, _) = step else { return nil }
        return env.sharingStore.shares.first { $0.zoneName == zoneID.zoneName }?.status
    }

    var body: some View {
        VaultSheetScaffold(title: sheetTitle) {
            content
        }
        .task(id: pollingZoneName) {
            guard let zoneName = pollingZoneName else { return }
            await pollForProfile(zoneName: zoneName)
        }
        .onAppear {
            guard !didAutoResume, let email = resumeEmail else { return }
            didAutoResume = true
            recipientEmail = email
            step = .checking
            Task { await enter() }
        }
        .confirmationDialog("Revoke access?", isPresented: revokeDialogBinding,
                            titleVisibility: .visible) {
            Button("Revoke Access", role: .destructive) {
                if let target = revokeTarget {
                    Task { await revoke(target) }
                }
            }
        } message: {
            // Forward-secrecy honesty (H5): future access ends now; already-
            // delivered shared values cannot be clawed back.
            Text("They can't request codes anymore. Values that were already shared stay on their device.")
        }
        // Hand-over confirmation (INV-08): the one honest moment to say a
        // delivered secret is not revocable by us.
        .confirmationDialog("Hand over this secret?", isPresented: handOverDialogBinding,
                            titleVisibility: .visible) {
            Button("Hand Over — Can't Be Taken Back", role: .destructive) {
                if let pending = pendingHandOver {
                    capabilities[pending.id] = pending.capability
                }
                pendingHandOver = nil
            }
        } message: {
            Text("They'll be able to use it without asking you, on their own device. Revoking later only stops updates — a secret already handed over can't be pulled back. To truly revoke it, change it at the website.")
        }
    }

    private var revokeDialogBinding: Binding<Bool> {
        Binding(get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } })
    }

    private func revoke(_ share: ItemShareRecord) async {
        do {
            try await env.approvalShare.revoke(zoneName: share.zoneName,
                                               inviteRecordName: share.inviteRecordName)
            // The rendezvous drop is creator-delete only — GC it here too.
            if let dropRecordName = share.dropRecordName {
                await env.inviteLinks.deleteInvite(recordName: dropRecordName)
            }
            env.sharingStore.remove(zoneName: share.zoneName)
        } catch {
            step = .failed(error.localizedDescription)
        }
        revokeTarget = nil
    }

    private var sheetTitle: LocalizedStringResource {
        switch step {
        case .choose: "Share"
        case .quickLink: "Quick Link"
        default: "Share Access"
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .choose:
            chooseView
        case .quickLink:
            QuickLinkView(itemID: itemID)
        case .checking:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .blocked(let blocker):
            blockedView(blocker)
        case .config:
            configForm
        case .creating, .publishing:
            VStack(spacing: Space.s4) {
                ProgressView()
                Text("Setting up encrypted approval transport…")
                    .vaultType(.callout).themedForeground(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .waiting(_, let shareURL, _):
            waitingView(shareURL: shareURL)
        case .fingerprint(_, let code, _):
            TrustFingerprintView(code: code, recipientLabel: recipientEmail) {
                Task { await confirmFingerprintAndPublish() }
            }
        case .done:
            doneView
        case .failed(let message):
            VStack(spacing: Space.s4) {
                PolarisIcon(Icons.alert, size: Metric.iconTile)
                    .themedForeground(.destructive)
                Text(verbatim: message)
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    step = .config
                } label: {
                    Text("Try Again")
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
                .buttonStyle(.themedProminent)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Steps

    private func enter() async {
        if let blocker = await ApprovalPrerequisites.check() {
            step = .blocked(blocker)
            return
        }
        if capabilities.isEmpty, let item {
            // Least exposure by default: everything Off until the owner opts in.
            for field in item.fields {
                capabilities[field.id] = field.kind == .totp ? .totp(.none) : .value(.none)
            }
            for passkey in itemPasskeys {
                capabilities[PasskeySlot.slotId(credentialID: passkey.credentialID)]
                    = .passkey(.none)
            }
        }
        if let item {
            let allPks = env.repository.passkeys
            ShareDiagnostics.log("PASSKEY", "itemHosts=[\(item.autofillHosts.joined(separator: ","))] "
                + "vaultPasskeys=\(allPks.count) rps=[\(allPks.map { $0.relyingParty }.joined(separator: ","))] "
                + "matched=\(itemPasskeys.count) liveKey=\(env.session.vaultKey != nil)")
        }
        step = .config
    }

    private func createShare() async {
        // Re-entrancy guard: a double-tapped button queues two MainActor
        // tasks; the second must not mint a second zone (review M2).
        guard case .config = step else { return }
        step = .creating
        pollExhausted = false
        do {
            // Resume path (review H2): an unfinished share to the SAME
            // recipient reuses its zone instead of littering a new one.
            let pending = env.sharingStore.shares(forItem: itemID).first {
                !$0.fingerprintConfirmed && $0.recipientLabel == normalizedEmail
            }
            let setup = try await env.approvalShare.createShare(
                recipientEmail: normalizedEmail, existingZoneName: pending?.zoneName)
            // Pretty invite link (invite.looxpassword.com) — opens the app
            // directly on the recipient's phone instead of Safari/iCloud.
            // Fall back to the raw CKShare URL if minting fails (offline).
            var inviteURL = setup.shareURL
            var inviteRecordName: String?
            if let shareURL = setup.shareURL,
               let minted = try? await env.inviteLinks.createInviteLink(shareURL: shareURL) {
                inviteURL = minted.url
                inviteRecordName = minted.recordName
            }
            // Loox-to-Loox tier (U5): if the recipient has an armed invite
            // inbox, drop a sealed envelope so their device gets a push and
            // surfaces the invite by itself. Best-effort — the link below
            // remains the universal fallback either way.
            var dropRecordName: String?
            if let shareURL = setup.shareURL {
                // A superseded drop from an earlier attempt at THIS pending
                // share is dead weight in the recipient's inbox — GC it
                // before dropping anew (creator-only delete).
                if let staleDrop = pending?.dropRecordName {
                    await env.inviteLinks.deleteInvite(recordName: staleDrop)
                }
                dropRecordName = await env.inviteInbox.dropInvite(
                    shareURL: shareURL, recipientEmail: normalizedEmail,
                    knownRecipientZoneNames: recipientZoneNames)
                autoInviteSent = dropRecordName != nil
            }
            // Approval Mode listening turns on now, deliberately BEFORE the
            // grant exists — the accept push must be receivable. The pending
            // record below keeps that state accounted for.
            env.settings.approvalModeEnabled = true
            env.sharingStore.upsert(ItemShareRecord(
                itemId: itemID, zoneName: setup.zoneID.zoneName,
                recipientLabel: normalizedEmail, grantId: nil,
                createdAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                fingerprintConfirmed: false, inviteRecordName: inviteRecordName,
                dropRecordName: dropRecordName))
            step = .waiting(zoneID: setup.zoneID, shareURL: inviteURL,
                            rawShareURL: setup.shareURL)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    /// The recipient may arm their invite inbox AFTER this share was created
    /// (fresh install, first launch of a new build) — a single drop attempt
    /// at creation would silently strand the auto-invite tier, so the waiting
    /// poll retries until the descriptor appears or the ceremony moves on.
    private func retryAutoInviteIfNeeded() async {
        guard !autoInviteSent,
              case .waiting(let zoneID, _, let rawShareURL) = step,
              let rawShareURL else { return }
        guard let name = await env.inviteInbox.dropInvite(
            shareURL: rawShareURL, recipientEmail: normalizedEmail,
            knownRecipientZoneNames: recipientZoneNames) else { return }
        autoInviteSent = true
        if var pending = env.sharingStore.shares(forItem: itemID)
            .first(where: { $0.zoneName == zoneID.zoneName }) {
            pending.dropRecordName = name
            env.sharingStore.upsert(pending)
        }
    }

    /// Structured poll (auto-cancelled via `.task(id:)`): identity loaded
    /// once, gentle backoff, bounded — the ceremony can also be finished
    /// later by reopening the sheet (the pending record resumes it).
    private func pollForProfile(zoneName: String) async {
        guard let ownerKey = try? DeviceSigningIdentity.loadOrCreate().publicKeyRaw else { return }
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        var delay: Duration = .seconds(3)
        for attempt in 0..<80 { // ≈ 10 minutes at the capped interval
            guard !Task.isCancelled else { return }
            if let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) {
                env.sharingStore.updateStatus(zoneName: zoneName, to: .readyForCeremony)
                let code = TrustFingerprint.code(ownerSigningPubKey: ownerKey,
                                                 participantPubKey: profile.participantPubKey)
                step = .fingerprint(zoneID: zoneID, code: code, profile: profile)
                return
            }
            // The recipient may have armed their inbox since the last try —
            // re-attempt the auto-drop on a slower cadence (~every 30-60s). Same
            // cadence re-checks CKShare acceptance so the copy can switch to
            // "accepted, finishing on their device" even before the profile lands.
            if attempt % 6 == 5 {
                await retryAutoInviteIfNeeded()
                if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                    env.sharingStore.updateStatus(zoneName: zoneName, to: .accepted)
                }
            }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(10))
        }
        // Budget exhausted must SAY so — a silent stop reads as "still
        // polling" and strands the owner on a screen that no longer checks.
        pollExhausted = true
    }

    /// One immediate profile check (the "Check Now" button) — also re-tries
    /// the auto-drop so "Check Now" doubles as "re-send the auto-invite".
    private func checkProfileNow() async {
        await retryAutoInviteIfNeeded()
        guard case .waiting(let zoneID, _, _) = step,
              let ownerKey = try? DeviceSigningIdentity.loadOrCreate().publicKeyRaw
        else { return }
        guard let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) else {
            // No profile yet, but they may already have accepted — reflect that.
            if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                env.sharingStore.updateStatus(zoneName: zoneID.zoneName, to: .accepted)
            }
            return
        }
        env.sharingStore.updateStatus(zoneName: zoneID.zoneName, to: .readyForCeremony)
        let code = TrustFingerprint.code(ownerSigningPubKey: ownerKey,
                                         participantPubKey: profile.participantPubKey)
        step = .fingerprint(zoneID: zoneID, code: code, profile: profile)
    }

    private func confirmFingerprintAndPublish() async {
        guard case .fingerprint(let zoneID, _, let profile) = step else { return }
        guard let item else {
            step = .failed(appString("This item no longer exists."))
            return
        }
        step = .publishing
        do {
            let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
            // Single-device seals to the recipient's first-enrolled device;
            // the composer fails loudly if that device isn't published yet
            // (INV-04, never falls back to the synced key). Passkeys + display
            // metadata are assembled identically to the edit path via the
            // shared composer so the two can never drift.
            let deviceScope: DeviceScope = allowMultipleDevices ? .multi : .single
            let grant = try await SharedGrantComposer.publish(
                service: env.approvalShare, store: env.store, item: item,
                capabilities: capabilities, itemPasskeys: itemPasskeys,
                vaultKey: env.session.vaultKey,
                profile: SharedGrantComposer.RecipientProfile(
                    participantPubKey: profile.participantPubKey,
                    deviceSigningKeys: profile.deviceSigningKeys,
                    deviceHPKEDirectory: profile.deviceHPKEDirectory),
                deviceScope: deviceScope, epoch: 1, zoneID: zoneID, nowUnixMs: nowUnixMs)
            // Acceptance is proven — the public invite artifacts have served
            // their purpose; delete them now (owner is the only principal
            // who can — public-db records are creator-delete only).
            let pendingRecord = env.sharingStore.shares(forItem: item.id)
                .first { $0.zoneName == zoneID.zoneName }
            if let inviteRecordName = pendingRecord?.inviteRecordName {
                await env.inviteLinks.deleteInvite(recordName: inviteRecordName)
            }
            if let dropRecordName = pendingRecord?.dropRecordName {
                await env.inviteLinks.deleteInvite(recordName: dropRecordName)
            }
            // The names are CARRIED into the active record: deleteInvite is
            // best-effort, and revoke retries the GC with these same names.
            env.sharingStore.upsert(ItemShareRecord(
                itemId: item.id, zoneName: zoneID.zoneName,
                recipientLabel: recipientEmail, grantId: grant.id,
                createdAtUnixMs: nowUnixMs, fingerprintConfirmed: true,
                inviteRecordName: pendingRecord?.inviteRecordName,
                dropRecordName: pendingRecord?.dropRecordName))
            step = .done
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    // MARK: Subviews

    /// Entry chooser: a portable encrypted link vs the approval-based iCloud
    /// share. The quick link is listed first — it's the "just send it" path.
    private var chooseView: some View {
        Form {
            Section {
                shareOptionRow(icon: Icons.globe,
                               title: "Quick Link",
                               subtitle: "Create an encrypted link that opens anywhere — no app needed. Expires automatically.") {
                    step = .quickLink
                }
                shareOptionRow(icon: Icons.shield,
                               title: "Share with a Loox user",
                               subtitle: "Approval-based access over iCloud — you stay in control of every use.") {
                    step = .checking
                    Task { await enter() }
                }
            } footer: {
                Text("A quick link is a one-time snapshot of the fields you pick. Sharing with a Loox user stays live and can require your approval for every use.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func shareOptionRow(icon: String, title: LocalizedStringResource,
                                subtitle: LocalizedStringResource,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                PolarisIcon(icon, size: Metric.iconUtility)
                    .themedForeground(.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.inAppLocalized)
                        .vaultType(.headline).themedForeground()
                    Text(subtitle.inAppLocalized)
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PolarisIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, Space.s1)
        }
        .buttonStyle(.plain)
    }

    private var configForm: some View {
        Form {
            Section {
                TextField("Recipient's iCloud email", text: $recipientEmail)
                    .platformKeyboardType(.emailAddress)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Access is tied to this iCloud account — only they can accept, and there's no link that works for anyone else.")
            }
            .listRowBackground(VaultColors.surface)

            if let item {
                Section {
                    ForEach(item.fields) { field in
                        FieldCapabilityRow(field: field, capability: binding(for: field),
                                           requestHandOver: { proposed in
                                               pendingHandOver = (field.id, proposed)
                                           })
                    }
                    ForEach(itemPasskeys) { passkey in
                        PasskeyCapabilityRow(passkey: passkey,
                                             capability: passkeyBinding(for: passkey),
                                             requestHandOver: { proposed in
                                                 pendingHandOver = (PasskeySlot.slotId(
                                                     credentialID: passkey.credentialID), proposed)
                                             })
                    }
                } header: {
                    Text("What they can use")
                } footer: {
                    Text("Shared values are visible to them and can't be taken back later. \"Ask each time\" codes need your approval for every use — the secret never leaves your vault.")
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: $allowMultipleDevices) {
                        Label { Text("Allow use on multiple devices") } icon: { PolarisIcon(Icons.apps) }
                    }
                } footer: {
                    Text("When off, everything is encrypted for the first device they enrolled — their other devices only see a locked placeholder.")
                }
                .listRowBackground(VaultColors.surface)

                let existing = env.sharingStore.shares(forItem: item.id)
                if !existing.isEmpty {
                    Section {
                        ForEach(existing) { share in
                            LabeledContent(share.recipientLabel) {
                                Text(statusLabel(for: share.status).inAppLocalized)
                                    .themedForeground(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    revokeTarget = share
                                } label: {
                                    Label("Revoke", image: Icons.trash)
                                }
                            }
                        }
                    } header: {
                        Text("Shared with \(existing.count)")
                    } footer: {
                        Text("Revoking stops all future requests immediately. Values you marked Shared were already delivered and stay with them.")
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }

            Section {
                Button {
                    Task { await createShare() }
                } label: {
                    Text("Create Share")
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
                .buttonStyle(.themedProminent)
                .disabled(!recipientEmail.contains("@") || !hasGrantedCapability)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// Owner-facing lifecycle label for the "Shared with" row. Distinguishes an
    /// invite still awaiting acceptance from one accepted but not yet confirmed.
    private func statusLabel(for status: ShareLifecycle) -> LocalizedStringResource {
        switch status {
        case .inviteSent: "Invite sent"
        case .accepted: "Accepted — finishing"
        case .readyForCeremony: "Ready to confirm"
        case .active: "Active"
        }
    }

    private func binding(for field: DynamicField) -> Binding<FieldCapability> {
        Binding(
            get: { capabilities[field.id] ?? (field.kind == .totp ? .totp(.none) : .value(.none)) },
            set: { capabilities[field.id] = $0 })
    }

    private func passkeyBinding(for passkey: PasskeyInfo) -> Binding<FieldCapability> {
        let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
        return Binding(get: { capabilities[slot] ?? .passkey(.none) },
                       set: { capabilities[slot] = $0 })
    }

    private var handOverDialogBinding: Binding<Bool> {
        Binding(get: { pendingHandOver != nil },
                set: { if !$0 { pendingHandOver = nil } })
    }

    /// Design 10f: the owner is never made to watch a spinner here — the
    /// calm "invite sent" card replaces the old polling screen, with an
    /// explicit Done that closes the sheet outright (the pending state now
    /// persists in `SharingStore` and resurfaces on Home / Item Detail /
    /// Notifications regardless of whether this sheet stays open).
    private func waitingView(shareURL: URL?) -> some View {
        let accepted = waitingStatus == .accepted
        let title = item?.title.isEmpty == false ? item!.title : appString("this item")
        return ScrollView {
            VStack(spacing: Space.s5) {
                ShareInviteSentSheet(recipientLabel: recipientEmail, itemTitle: title, accepted: accepted)

                if !accepted && autoInviteSent {
                    Text("Their device was notified automatically too — the Messages link below is just a backup.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .multilineTextAlignment(.center)
                }
                if pollExhausted {
                    Text("Still waiting — you can close this screen and finish later, or tap Check Now.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Space.s3) {
                    Button { dismiss() } label: {
                        Text("Done").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                    }
                    .buttonStyle(.themedProminent)

                    if let shareURL {
                        #if os(iOS)
                        // Primary nudge: iMessage with the recipient pre-filled
                        // (the share sheet can't preselect one; the compose
                        // window can).
                        if MessageComposeView.canSendText {
                            Button {
                                showMessageCompose = true
                            } label: {
                                Label { Text("Nudge via Messages") } icon: { PolarisIcon(Icons.share) }
                                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                            }
                            .sheet(isPresented: $showMessageCompose) {
                                MessageComposeView(
                                    recipients: [normalizedEmail],
                                    body: appString("I shared an item with you in Loox Password. Open this link on your iPhone to accept: \(shareURL.absoluteString)"))
                            }
                        } else {
                            ShareLink(item: shareURL) {
                                Label { Text("Share Invite Link") } icon: { PolarisIcon(Icons.share) }
                                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                            }
                        }
                        #else
                        ShareLink(item: shareURL) {
                            Label { Text("Share Invite Link") } icon: { PolarisIcon(Icons.share) }
                                .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                        }
                        #endif
                    }
                    // Manual escape hatch: the background poll has a bounded
                    // budget — this button re-checks on demand so a long wait
                    // can't strand the owner on this screen.
                    Button {
                        Task { await checkProfileNow() }
                    } label: {
                        Text("Check Now").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                    }
                }

                if !accepted {
                    Text("First time sharing with someone? A Messages nudge helps them find the invite.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Space.gutter)
        }
    }

    private var doneView: some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.shield, size: Metric.iconTileLarge)
                .themedForeground(.success)
            Text("Access shared")
                .vaultType(.section).themedForeground()
            Text("They now see what you allowed. You can change or revoke access anytime from this item.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func blockedView(_ blocker: ApprovalPrerequisites.Blocker) -> some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.info, size: Metric.iconTile)
                .themedForeground(.warning)
            Text(blocker == .iCloudUnavailable
                 ? "Sign in to iCloud to share access. Sharing uses an encrypted approval transport — it does not turn on vault sync."
                 : "Approval requests need notifications. Allow notifications in Settings to share \"ask each time\" access.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            // The gate result can change while the sheet is up (user flips
            // the permission in Settings and comes back) — allow a re-check.
            Button {
                step = .checking
                Task { await enter() }
            } label: {
                Text("Check Again")
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
