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
    /// Share pending the destructive revoke confirmation.
    @State private var revokeTarget: ItemShareRecord?
    /// iMessage compose (recipient pre-filled) for the invite link.
    @State private var showMessageCompose = false
    /// A rendezvous drop reached the recipient's armed inbox — their device
    /// will surface the invite by itself; the link is now just a backup.
    @State private var autoInviteSent = false
    /// The bounded poll ran out — surface that waiting continues manually.
    @State private var pollExhausted = false

    private var item: VaultItem? { env.repository.item(id: itemID) }

    private var hasGrantedCapability: Bool {
        capabilities.values.contains { $0.isAskEachTimeTOTP || $0.isSharedValue }
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

    var body: some View {
        VaultSheetScaffold(title: sheetTitle) {
            content
        }
        .task(id: pollingZoneName) {
            guard let zoneName = pollingZoneName else { return }
            await pollForProfile(zoneName: zoneName)
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
                let code = TrustFingerprint.code(ownerSigningPubKey: ownerKey,
                                                 participantPubKey: profile.participantPubKey)
                step = .fingerprint(zoneID: zoneID, code: code, profile: profile)
                return
            }
            // The recipient may have armed their inbox since the last try —
            // re-attempt the auto-drop on a slower cadence (~every 30-60s).
            if attempt % 6 == 5 { await retryAutoInviteIfNeeded() }
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
              let ownerKey = try? DeviceSigningIdentity.loadOrCreate().publicKeyRaw,
              let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID)
        else { return }
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
            let sharedValues: [String: Data] = Dictionary(uniqueKeysWithValues:
                item.fields.compactMap { field in
                    guard capabilities[field.id]?.isSharedValue == true,
                          !field.isExtraProtected else { return nil }
                    return (field.id, Data(field.value.utf8))
                })
            let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
            // Field labels/kinds travel in the SEALED envelope so the
            // recipient renders username as username, password as password.
            let displayFields = Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
                capabilities[field.id]?.isSharedValue == true || capabilities[field.id]?.isAskEachTimeTOTP == true
                    ? (field.id, SharedDisplayEnvelope.FieldMeta(label: field.label,
                                                                 kind: field.kind.rawValue))
                    : nil
            })
            // Single-device: seal to the recipient's FIRST-enrolled device
            // (deterministic choice); their other devices stay Tier 0. A
            // recipient app without a device directory can't honor the
            // promise — fail loudly, never fall back to the synced key.
            let deviceScope: DeviceScope = allowMultipleDevices ? .multi : .single
            var allowedDevices: [DeviceHPKEDirectoryEntry] = []
            if deviceScope == .single {
                guard let first = profile.deviceHPKEDirectory.min(by: {
                    ($0.addedAtUnixMs, $0.deviceKeyID.hexString)
                        < ($1.addedAtUnixMs, $1.deviceKeyID.hexString)
                }) else {
                    step = .failed(appString("Single-device sharing needs the recipient to update Loox first."))
                    return
                }
                allowedDevices = [first]
            }
            let grant = try await env.approvalShare.publishGrant(
                itemId: item.id,
                capabilities: capabilities,
                sharedValues: sharedValues,
                displayTitle: item.title.isEmpty ? appString("Shared item") : item.title,
                displayWebsiteHost: item.urlField?.value.isEmpty == false
                    ? URL(string: item.urlField!.value)?.host : nil,
                displayFields: displayFields,
                participantPubKey: profile.participantPubKey,
                pinnedDeviceSigningKeys: profile.deviceSigningKeys,
                epoch: 1, zoneID: zoneID, nowUnixMs: nowUnixMs,
                deviceScope: deviceScope, allowedDevices: allowedDevices)
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
                        FieldCapabilityRow(field: field, capability: binding(for: field))
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
                                Text(share.fingerprintConfirmed ? "Active" : "Pending")
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

    private func binding(for field: DynamicField) -> Binding<FieldCapability> {
        Binding(
            get: { capabilities[field.id] ?? (field.kind == .totp ? .totp(.none) : .value(.none)) },
            set: { capabilities[field.id] = $0 })
    }

    private func waitingView(shareURL: URL?) -> some View {
        VStack(spacing: Space.s5) {
            ProgressView()
            Text("Waiting for them to accept…")
                .vaultType(.section).themedForeground()
            Text(autoInviteSent
                 ? "Their device was notified automatically. If nothing shows up there, send the link below as a backup."
                 : "Send the invitation link — the first share with someone always needs it. After they accept once, future shares notify their device automatically.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            if pollExhausted {
                Text("Still waiting — you can close this screen and finish later, or tap Check Now.")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let shareURL {
                #if os(iOS)
                // Primary: iMessage with the recipient pre-filled (the share
                // sheet can't preselect one; the compose window can).
                if MessageComposeView.canSendText {
                    Button {
                        showMessageCompose = true
                    } label: {
                        Label { Text("Send via Messages") } icon: { PolarisIcon(Icons.share) }
                            .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                    }
                    .buttonStyle(.themedProminent)
                    .sheet(isPresented: $showMessageCompose) {
                        MessageComposeView(
                            recipients: [normalizedEmail],
                            body: appString("I shared an item with you in Loox Password. Open this link on your iPhone to accept: \(shareURL.absoluteString)"))
                    }
                }
                #endif
                ShareLink(item: shareURL) {
                    Label { Text("Share Another Way") } icon: { PolarisIcon(Icons.share) }
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
            }
            // Manual escape hatch: the background poll has a bounded budget —
            // this button re-checks on demand so a long wait can't strand the
            // owner on this screen.
            Button {
                Task { await checkProfileNow() }
            } label: {
                Text("Check Now").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
