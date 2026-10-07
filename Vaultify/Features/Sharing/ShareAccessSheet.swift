import CloudKit
import SwiftUI

/// Owner share-config flow: pick a recipient (looked-up iCloud identity, no
/// bearer semantics), set per-field capability, create the CKShare, wait for
/// the recipient to accept + publish their identity, run the one-time
/// fingerprint ceremony, then publish the signed grant + sealed blobs.
/// Fail-closed at the door: no iCloud account or no notification permission →
/// the flow never starts (ADR-2).
struct ShareAccessSheet: View {
    enum Entry { case choose, approvalOnly }
    let itemID: String
    /// Resume entry (from the Notifications "Shares you sent" list): open
    /// straight into the approval config with this recipient pre-filled, so a
    /// share left pending after a dismiss/relaunch is continued without
    /// re-choosing the path or retyping the email. Create Share reuses the
    /// existing zone (matched by recipient), so no duplicate share is minted.
    var resumeEmail: String? = nil
    /// Family deliberately enters the Approval Mode ceremony. A fake resume
    /// address must never be used to skip the generic share-path chooser.
    var entry: Entry = .choose
    var ownerPersonaID: String? = nil
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
    /// Realtime-action offline notice (revoking is only true once iCloud says so).
    @State private var showRevokeOfflineNotice = false
    /// iMessage compose (recipient pre-filled) for the invite link.
    @State private var showMessageCompose = false
    /// A rendezvous drop reached the recipient's armed inbox — their device
    /// will surface the invite by itself; the link is now just a backup.
    @State private var autoInviteSent = false
    /// The bounded poll ran out — surface that waiting continues manually.
    @State private var pollExhausted = false
    /// One-shot guard so the resume entry seeds the config exactly once.
    @State private var didAutoResume = false
    @State private var enteredPersonaID: String?

    private var item: VaultItem? { env.repository.memberOwnedItems.first { $0.id == itemID } }
    private var scopeIsValid: Bool {
        env.session.state == .unlocked
            && env.repository.memberCanUseItem(itemID, personaID: ownerPersonaID ?? enteredPersonaID,
                                               needsSnapshotFields: false)
    }

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
        VaultSheetScaffold(title: sheetTitle, trailing: { toolbarTrailing }) {
            content
        }
        // Hosted here, not at the root: a sheet draws above the root overlay,
        // so a tour about sharing has to live inside the sheet it explains.
        .tutorialHost(env.tutorial, flowIDs: ["sharing"])
        .task { env.tutorial.startIfNeeded(.sharing) }
        .onDisappear { env.tutorial.cancelPendingStart() }
        .task(id: pollingZoneName) {
            guard let zoneName = pollingZoneName else { return }
            await pollForProfile(zoneName: zoneName)
        }
        .onAppear {
            guard !didAutoResume else { return }
            didAutoResume = true
            enteredPersonaID = ownerPersonaID ?? env.repository.activePersona?.id
            if let email = resumeEmail { recipientEmail = email }
            guard resumeEmail != nil || entry == .approvalOnly else { return }
            step = .checking
            Task { await enter() }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in dismiss() }
        .onChange(of: env.session.state) { _, state in if state != .unlocked { dismiss() } }
        .offlineActionNotice(isPresented: $showRevokeOfflineNotice,
                             message: "You need an internet connection to revoke access. The share stays active until then.")
        .animation(Motion.standard, value: revokeTarget?.id)
        .animation(Motion.standard, value: pendingHandOver?.id)
    }

    private func revoke(_ share: ItemShareRecord) async {
        guard scopeIsValid, env.sharingStore.shares.contains(where: { $0.id == share.id }) else { return }
        do {
            try await env.approvalShare.revoke(zoneName: share.zoneName,
                                               inviteRecordName: share.inviteRecordName)
            // The rendezvous drop is creator-delete only — GC it here too.
            if let dropRecordName = share.dropRecordName {
                await env.inviteLinks.deleteInvite(recordName: dropRecordName)
            }
            env.sharingStore.remove(zoneName: share.zoneName)
        } catch {
            step = .failed(SharingErrorMessage.text(for: error))
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

    /// Low-frequency manual escape hatch for the waiting step, demoted off the
    /// primary action row into the toolbar overflow (action-hierarchy rule):
    /// the button stack below only ever shows the ranked next step.
    @ViewBuilder private var toolbarTrailing: some View {
        if case .waiting = step {
            Menu {
                Button {
                    Task { await checkProfileNow() }
                } label: { Text("Check now") }
            } label: {
                VaultIcon(Icons.moreHorizontal, size: Metric.iconInline)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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
        case .done:
            doneView
        case .failed(let message):
            VStack(spacing: Space.s4) {
                VaultIcon(Icons.alert, size: Metric.iconTile)
                    .themedForeground(.destructive)
                Text(verbatim: message)
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    step = .config
                } label: {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Steps

    /// The unfinished share this sheet is resuming, if any.
    private var resumingRecord: ItemShareRecord? {
        guard resumeEmail != nil else { return nil }
        return env.sharingStore.shares(forItem: itemID).first {
            !$0.fingerprintConfirmed && $0.recipientLabel == normalizedEmail
        }
    }

    private func enter() async {
        guard scopeIsValid else { step = .failed(appString("This item is no longer available in this profile.")); return }
        if let blocker = await ApprovalPrerequisites.check() {
            step = .blocked(blocker)
            return
        }
        guard scopeIsValid else { return }
        // Resuming: replay the scope the owner already chose. It is frozen on
        // the record at create time precisely so this sheet never asks twice —
        // and `allowMultipleDevices` MUST come from the record, because the
        // in-memory default is the more permissive one and would silently widen
        // a single-device share.
        if let record = resumingRecord, let planned = record.plannedCapabilities {
            if capabilities.isEmpty { capabilities = planned }
            allowMultipleDevices = record.plannedAllowMultipleDevices ?? true
            // The recipient's key has already landed: there is nothing left for
            // the owner to decide, so finish instead of showing the form again.
            if record.status == .readyForCeremony {
                await activate(record: record)
                return
            }
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
        guard case .config = step, scopeIsValid else { return }
        let authorizedCapabilities = capabilities
        let authorizedDeviceScope = allowMultipleDevices
        let authorizedRecipient = normalizedEmail
        step = .creating
        pollExhausted = false
        do {
            // Reuse this recipient's existing zone, scoped to the active
            // persona (INV-R03), instead of minting a new one per item. Sharing
            // a second item to someone already connected used to mean a whole
            // new CKShare, a new accept, and a new profile publish — even though
            // their key was already on file. With the zone reused, the profile
            // is found on the first poll tick and the share completes at once.
            let existingZoneName = SpaceShareZoneDedupe.existingZoneName(
                recipientShares: env.sharingStore.shares(forRecipient: normalizedEmail),
                activePersonaItemIds: Set(env.repository.memberOwnedItems.map(\.id)))
            // Carried separately: the invite artifacts to supersede belong to
            // THIS item's unfinished attempt, not to the shared zone.
            let pending = env.sharingStore.shares(forItem: itemID).first {
                !$0.fingerprintConfirmed && $0.recipientLabel == normalizedEmail
            }
            let setup = try await env.approvalShare.createShare(
                recipientEmail: authorizedRecipient,
                existingZoneName: existingZoneName ?? pending?.zoneName)
            // Keep the already-authorized pending attempt under its original
            // item if a profile switch interrupts the network call. No grant
            // values are published until the live ownership gate passes.
            if !env.sharingStore.shares.contains(where: { $0.itemId == itemID && $0.zoneName == setup.zoneID.zoneName }) {
                env.sharingStore.upsert(ItemShareRecord(
                    itemId: itemID, zoneName: setup.zoneID.zoneName,
                    recipientLabel: authorizedRecipient, grantId: nil,
                    createdAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000), fingerprintConfirmed: false,
                    plannedCapabilities: authorizedCapabilities, plannedAllowMultipleDevices: authorizedDeviceScope))
            }
            guard scopeIsValid else { return }
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
            // Freeze the owner's scope onto the record. This tap IS the
            // authorization; the seal has to wait for the recipient's key, but
            // the decision does not, so it is replayed by `ShareActivationService`
            // rather than re-collected from the owner.
            env.sharingStore.upsert(ItemShareRecord(
                itemId: itemID, zoneName: setup.zoneID.zoneName,
                recipientLabel: normalizedEmail, grantId: nil,
                createdAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                fingerprintConfirmed: false, inviteRecordName: inviteRecordName,
                dropRecordName: dropRecordName,
                plannedCapabilities: authorizedCapabilities,
                plannedAllowMultipleDevices: authorizedDeviceScope))
            guard scopeIsValid else { return }
            step = .waiting(zoneID: setup.zoneID, shareURL: inviteURL,
                            rawShareURL: setup.shareURL)
        } catch {
            step = .failed(SharingErrorMessage.text(for: error))
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
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        var delay: Duration = .seconds(3)
        // Short budget on purpose: the silent acceptance push (plus the hint
        // hook on the waiting view) is the primary detector now — this poll is
        // only the fallback for a throttled or undelivered push.
        for attempt in 0..<24 { // ≈ 2.5 minutes at the capped interval
            guard !Task.isCancelled else { return }
            if let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) {
                env.sharingStore.updateStatus(zoneName: zoneName, to: .readyForCeremony)
                await activateCurrentShare(zoneName: zoneName, profile: profile)
                return
            }
            // Every tick: re-check CKShare acceptance (a cheap single-record
            // fetch) so the copy flips to "accepted, finishing on their
            // device" within seconds of the accept, not on a slow cadence.
            if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                env.sharingStore.updateStatus(zoneName: zoneName, to: .accepted)
            }
            // The recipient may have armed their inbox since the last try —
            // re-attempt the auto-drop on a slower cadence (~every 30-60s):
            // unlike the read above, this WRITES to the public DB.
            if attempt % 6 == 5 {
                await retryAutoInviteIfNeeded()
            }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(10))
        }
        // Budget exhausted must SAY so — a silent stop reads as "still
        // polling" and strands the owner on a screen that no longer checks.
        pollExhausted = true
    }

    /// One immediate profile check (the "Check now" button and the
    /// acceptance-push hint). While waiting it also re-tries the auto-drop so
    /// "Check now" doubles as "re-send the auto-invite" — but that retry
    /// WRITES to the public DB, so it stays behind the step guard: the hint
    /// can fire this on every push while the sheet is open, and once the
    /// ceremony has left `.waiting` a check must stay read-only.
    private func checkProfileNow() async {
        guard case .waiting(let zoneID, _, _) = step else { return }
        await retryAutoInviteIfNeeded()
        guard let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) else {
            // No profile yet, but they may already have accepted — reflect that.
            if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                env.sharingStore.updateStatus(zoneName: zoneID.zoneName, to: .accepted)
            }
            return
        }
        env.sharingStore.updateStatus(zoneName: zoneID.zoneName, to: .readyForCeremony)
        await activateCurrentShare(zoneName: zoneID.zoneName, profile: profile)
    }

    /// Finish the share now that the recipient's key is here. There is no second
    /// owner decision: the scope was authorized at create time and is replayed
    /// from the record, so this publishes straight through to `.done`.
    private func activateCurrentShare(zoneName: String,
                                      profile: ShareActivationService.ParticipantProfile) async {
        guard scopeIsValid else { return }
        guard let record = env.sharingStore.shares(forItem: itemID)
            .first(where: { $0.zoneName == zoneName }) else { return }
        step = .publishing
        await apply(await env.shareActivation.activate(record: record, profile: profile))
    }

    /// Resume entry where the profile already landed: fetch it, then publish.
    private func activate(record: ItemShareRecord) async {
        guard scopeIsValid, record.itemId == itemID else { return }
        step = .publishing
        await apply(await env.shareActivation.activate(record: record))
    }

    private func apply(_ outcome: ShareActivationService.Outcome) async {
        switch outcome {
        case .activated:
            step = .done
        case .needsUnlock:
            step = .failed(appString("Unlock Loox, then try again."))
        case .needsOwnerScope:
            // A share created before the scope was persisted: the owner is the
            // only source for it, so fall back to the config form.
            step = .config
        case .notReady:
            // The profile went away between the fetch and the publish — go back
            // to waiting rather than reporting a failure that isn't one.
            step = .config
        case .failed(let message):
            step = .failed(message)
        }
    }

    // MARK: Subviews

    /// Entry chooser: a portable encrypted link vs the approval-based iCloud
    /// share. The quick link is listed first — it's the "just send it" path.
    /// Share Links off in Settings → the Quick Link path disappears from the
    /// chooser entirely (a listed-but-dead option is the confusion the
    /// preference is meant to remove). Operator/outage states keep the row:
    /// `QuickLinkView` explains those with their own copy.
    private var quickLinkOffered: Bool {
        env.capabilities.availability(.shareLink, operation: .create) != .disabledByUser
    }

    private var chooseView: some View {
        Form {
            Section {
                if quickLinkOffered {
                    shareOptionRow(icon: Icons.globe,
                                   title: "Quick Link",
                                   subtitle: "Create an encrypted link that opens anywhere, no app needed. Expires automatically.") {
                        step = .quickLink
                    }
                }
                shareOptionRow(icon: Icons.shield,
                               title: "Share with a Loox user",
                               subtitle: "Approval-based access over iCloud. You stay in control of every use.") {
                    step = .checking
                    Task { await enter() }
                }
            } footer: {
                if quickLinkOffered {
                    Text("A quick link is a one-time snapshot of the fields you pick. Sharing with a Loox user stays live and can require your approval for every use.")
                }
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func shareOptionRow(icon: String, title: LocalizedStringResource,
                                subtitle: LocalizedStringResource,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                VaultIcon(icon, size: Metric.iconUtility)
                    .themedForeground(.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.inAppLocalized)
                        .vaultType(.headline).themedForeground()
                    Text(subtitle.inAppLocalized)
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VaultIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, Space.s1)
        }
        .buttonStyle(.plain)
    }

    /// People this owner already shares with, under the ACTIVE persona only.
    ///
    /// Persona scope matters: zone reuse is persona-scoped by design, so
    /// offering someone whose only zone belongs to another persona would
    /// silently mint a new zone and put the recipient through a fresh accept —
    /// exactly the friction the picker exists to remove. Excludes anyone
    /// already on this item.
    private var suggestedRecipients: [String] {
        let personaItemIds = Set(env.repository.memberOwnedItems.map(\.id))
        let alreadyOnThisItem = Set(env.sharingStore.shares(forItem: itemID).map(\.recipientLabel))
        let labels = env.sharingStore.shares
            .filter { personaItemIds.contains($0.itemId) }
            .map(\.recipientLabel)
            .filter { !alreadyOnThisItem.contains($0) }
        return Array(Set(labels)).sorted()
    }

    private var configForm: some View {
        Form {
            if !suggestedRecipients.isEmpty {
                Section {
                    ForEach(suggestedRecipients, id: \.self) { label in
                        Button {
                            recipientEmail = label
                        } label: {
                            HStack(spacing: Space.s3) {
                                Text(verbatim: label)
                                    .vaultType(.body).themedForeground(.primary)
                                Spacer(minLength: Space.s2)
                                if normalizedEmail == label {
                                    VaultIcon(Icons.check, size: Metric.iconInline)
                                        .themedForeground(.accentText)
                                }
                            }
                            .frame(minHeight: Metric.hitMin)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Share with")
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                TextField("Recipient's iCloud email", text: $recipientEmail)
                    .platformKeyboardType(.emailAddress)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Access is tied to this iCloud account. Only they can accept, and no link works for anyone else.")
            }
            .listRowBackground(VaultColors.surface)

            if let item {
                Section {
                    ForEach(item.fields) { field in
                        FieldCapabilityRow(field: field, item: item, capability: binding(for: field),
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
                    // Hand-over confirmation (INV-08): the one honest moment to say
                    // a delivered secret is not revocable by us.
                    if let pending = pendingHandOver {
                        InlineConfirm(
                            message: "They'll be able to use it without asking you, on their own device. Revoking later only stops updates; a secret already handed over can't be pulled back. To truly revoke it, change it at the website.",
                            confirmTitle: "Hand over: can't be taken back",
                            onCancel: { pendingHandOver = nil },
                            onConfirm: {
                                capabilities[pending.id] = pending.capability
                                pendingHandOver = nil
                            })
                    }
                } header: {
                    Text("What they can use")
                } footer: {
                    Text("Shared values are visible to them and can't be taken back later. \"Ask each time\" codes need your approval for every use. The secret never leaves your vault.")
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: $allowMultipleDevices) {
                        Label { Text("Allow use on multiple devices") } icon: { VaultIcon(Icons.apps) }
                    }
                } footer: {
                    Text("When off, everything is encrypted for the first device they enrolled. Their other devices only see a locked placeholder.")
                }
                .listRowBackground(VaultColors.surface)

                let existing = env.sharingStore.shares(forItem: item.id)
                if !existing.isEmpty {
                    Section {
                        ForEach(existing) { share in
                            VStack(alignment: .leading, spacing: Space.s2) {
                                LabeledContent(share.recipientLabel) {
                                    Text(statusLabel(for: share.status).inAppLocalized)
                                        .themedForeground(.secondary)
                                }
                                // Forward-secrecy honesty (H5): future access ends
                                // now; already-delivered values cannot be clawed back.
                                if revokeTarget?.id == share.id {
                                    InlineConfirm(
                                        message: "They can't request codes anymore. Values that were already shared stay on their device.",
                                        confirmTitle: "Revoke access",
                                        onCancel: { revokeTarget = nil },
                                        onConfirm: { Task { await revoke(share) } })
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    // Realtime CloudKit action — offline, the
                                    // swipe explains instead of erroring.
                                    if env.reachability.hasSatisfiedNetworkPath {
                                        revokeTarget = share
                                    } else {
                                        Haptics.warning()
                                        showRevokeOfflineNotice = true
                                    }
                                } label: {
                                    Label { Text("Revoke") } icon: { VaultIcon(Icons.trash) }
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
                    Text("Create share")
                        .frame(maxWidth: .infinity)
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
        case .accepted: "Accepted. Finishing"
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
                    Text("Their device was notified automatically too. The Messages link below is just a backup.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .multilineTextAlignment(.center)
                }
                if pollExhausted {
                    Text("Still waiting. You can close this screen and finish later, or check again from the menu above.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                }

                // In-person delivery: hand the phone over and let the recipient
                // scan — same email-keyed invite URL as the Messages nudge, just
                // a faster channel when they're next to you.
                if !accepted, let shareURL {
                    invitationQRCard(url: shareURL)
                }

                // Action hierarchy: exactly one filled primary + at most one
                // quiet secondary. Before acceptance the single most useful
                // thing the owner can do is help the recipient find the
                // invite (nudge); "Done" is the quiet fallback since the
                // pending state already persists and resurfaces elsewhere.
                // Once accepted there is nothing left to nudge — Done becomes
                // the primary. "Check now" is a low-frequency escape hatch,
                // demoted to the toolbar overflow (see `toolbarTrailing`).
                VStack(spacing: Space.s3) {
                    if accepted {
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                    } else if let shareURL {
                        #if os(iOS)
                        // Primary nudge: iMessage with the recipient pre-filled
                        // (the share sheet can't preselect one; the compose
                        // window can).
                        if MessageComposeView.canSendText {
                            Button {
                                showMessageCompose = true
                            } label: {
                                Label { Text("Nudge via Messages") } icon: { VaultIcon(Icons.share) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themedProminent)
                            .sheet(isPresented: $showMessageCompose) {
                                MessageComposeView(
                                    recipients: [normalizedEmail],
                                    body: appString("I shared an item with you in Loox Password. Open this link on your device to accept: \(shareURL.absoluteString)"))
                            }
                        } else {
                            ShareLink(item: shareURL) {
                                Label { Text("Share invite link") } icon: { VaultIcon(Icons.share) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themedProminent)
                        }
                        #else
                        ShareLink(item: shareURL) {
                            Label { Text("Share invite link") } icon: { VaultIcon(Icons.share) }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                        #endif
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedTinted)
                    } else {
                        // Rare fallback (no invite URL minted) — Done is the
                        // only available action.
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
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
        // The silent acceptance push landed while this sheet is open — check
        // immediately instead of waiting out the poll's backoff. Safe to fire
        // repeatedly: checkProfileNow is a one-shot fetch and drops itself if
        // the step already moved past waiting.
        .onReceive(NotificationCenter.default.publisher(for: .shareAcceptanceHint)) { _ in
            Task { await checkProfileNow() }
        }
    }

    /// In-person delivery of the invite: the recipient scans this with their
    /// Camera to open the universal invite link and accept — no Messages or
    /// email round-trip. The share stays keyed to the recipient's iCloud
    /// account; the QR only carries the same invite URL the nudge would send.
    private func invitationQRCard(url: URL) -> some View {
        VStack(spacing: Space.s3) {
            QRCodeView(payload: url.absoluteString)
                .frame(width: 200, height: 200)
            Text("Have them scan this with their Camera to accept.")
                .vaultType(.footnote).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var doneView: some View {
        VStack(spacing: Space.s4) {
            VaultIcon(Icons.shield, size: Metric.iconTileLarge)
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

    @ViewBuilder
    private func blockedView(_ blocker: ApprovalPrerequisites.Blocker) -> some View {
        switch blocker {
        case .notificationsNotAsked, .notificationsDenied:
            NotificationPermissionGateView(
                explanation: "Loox uses notifications to deliver approval requests. When the person you shared with asks to use this item, the request appears as an alert on this device.",
                denied: blocker == .notificationsDenied) {
                step = .checking
                Task { await enter() }
            }
        case .iCloudUnavailable:
            VStack(spacing: Space.s4) {
                VaultIcon(Icons.info, size: Metric.iconTile)
                    .themedForeground(.warning)
                Text("Sign in to iCloud to share access. Sharing uses an encrypted approval transport; it does not turn on vault sync.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                // The gate result can change while the sheet is up (user signs
                // in and comes back) — allow a re-check.
                Button {
                    step = .checking
                    Task { await enter() }
                } label: {
                    Text("Check again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
