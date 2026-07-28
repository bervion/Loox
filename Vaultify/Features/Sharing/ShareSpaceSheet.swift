import CloudKit
import SwiftUI

/// "Share a Space" ceremony (Family full-group sharing, phase A3 stage 2):
/// pick a recipient and one of the active persona's Spaces, run the SAME
/// trust ceremony `ShareAccessSheet` uses (`createShare` → wait for the
/// participant profile → publish (no owner step) → resolve
/// `SharedGrantComposer.RecipientProfile` + `DeviceScope`) exactly ONCE, then
/// fan the Space's eligible logins out to that member in one
/// `SpaceShareMembershipExecutor.reconcile` call.
///
/// Deliberately does NOT reimplement any of the ceremony's crypto/transport:
/// every CloudKit call routes through the same `ApprovalShareService` the
/// single-item sheet calls. The one deliberate behavior change
/// from the single-item sheet is zone reuse: `ShareAccessSheet` dedupes only
/// within ONE item's pending shares, so sharing N different items to the same
/// recipient mints N zones; a Space share reuses ONE zone per (active
/// persona, recipient) instead — see `SpaceShareZoneDedupe` — because that is
/// the entire point of the per-grant transport this ceremony publishes into.
struct ShareSpaceSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case checking
        case blocked(ApprovalPrerequisites.Blocker)
        case config
        case creating
        case waiting(zoneID: CKRecordZone.ID, shareURL: URL?)
        case publishing
        case result(SpaceShareMembershipExecutor.Summary)
        case failed(String)
    }

    @State private var step: Step = .checking
    @State private var selectedSpaceId: String?
    @State private var recipientEmail = ""
    /// Device scope (mirrors `ShareAccessSheet`'s P03b toggle, same default).
    @State private var allowMultipleDevices = true
    @State private var pendingInviteRecordName: String?
    @State private var participantHasAccepted = false
    @State private var pollExhausted = false
    @State private var showMessageCompose = false
    /// Set once the fingerprint is confirmed — frozen inputs to
    /// `SpaceShareMembershipExecutor.reconcile`, so a Retry after a fan-out
    /// failure re-invokes `reconcile` directly instead of re-running the
    /// ceremony (createShare/wait/fingerprint) a second time.
    @State private var resolvedRecipient: SpaceShareRecipientContext?

    private var normalizedRecipient: String {
        recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var selectedSpace: Folder? {
        guard let selectedSpaceId else { return nil }
        return env.repository.activePersonaSpaces.first { $0.id == selectedSpaceId }
    }

    private var spaceItems: [VaultItem] {
        guard let selectedSpace else { return [] }
        return env.repository.items(inFolder: selectedSpace.id)
    }

    private var eligibleCount: Int {
        SpaceShareMembershipReconciler.desired(spaceItems: spaceItems).count
    }

    private var canShare: Bool {
        selectedSpace != nil && normalizedRecipient.contains("@") && eligibleCount > 0
    }

    /// Reuse the recipient's existing zone (scoped to the active persona,
    /// INV-R03) instead of minting a new one — see `SpaceShareZoneDedupe`.
    private var existingZoneName: String? {
        SpaceShareZoneDedupe.existingZoneName(
            recipientShares: env.sharingStore.shares(forRecipient: normalizedRecipient),
            activePersonaItemIds: Set(env.repository.activePersonaItems.map(\.id)))
    }

    private var pollingZoneName: String? {
        if case .waiting(let zoneID, _) = step { return zoneID.zoneName }
        return nil
    }

    var body: some View {
        VaultSheetScaffold(title: "Share a Space", trailing: { toolbarTrailing }) {
            content
        }
        .task {
            guard case .checking = step else { return }
            await checkPrerequisites()
        }
        .task(id: pollingZoneName) {
            guard let zoneName = pollingZoneName else { return }
            await pollForProfile(zoneName: zoneName)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareAcceptanceHint)) { _ in
            Task { await checkProfileNow() }
        }
    }

    @ViewBuilder private var toolbarTrailing: some View {
        if case .waiting = step {
            Menu {
                Button { Task { await checkProfileNow() } } label: { Text("Check now") }
            } label: {
                PolarisIcon(Icons.moreHorizontal, size: Metric.iconInline)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .checking:
            // The prerequisite probe resolves in a blink, so copy here would
            // only flash: the spinner takes the glyph slot alone and the state
            // keeps the same silhouette as everything that follows it.
            VaultStatusScreen(busySystemImage: "person.2", busy: true)
        case .blocked(let blocker):
            blockedView(blocker)
        case .config:
            configForm
        case .creating:
            // Same title as the fan-out step: to the user this is one operation,
            // and the body names which half of it is running.
            VaultStatusScreen(busySystemImage: "person.2.badge.key",
                              title: "Sharing your Space…",
                              message: .key("Setting up encrypted approval transport…"),
                              busy: true)
        case .waiting(_, let shareURL):
            waitingView(shareURL: shareURL)
        case .publishing:
            publishingView
        case .result(let summary):
            resultView(summary)
        case .failed(let message):
            failedView(message)
        }
    }

    // MARK: Prerequisites

    private func checkPrerequisites() async {
        if let blocker = await ApprovalPrerequisites.check() {
            step = .blocked(blocker)
        } else {
            step = .config
        }
    }

    @ViewBuilder
    private func blockedView(_ blocker: ApprovalPrerequisites.Blocker) -> some View {
        switch blocker {
        case .notificationsNotAsked, .notificationsDenied:
            NotificationPermissionGateView(
                explanation: "Loox uses notifications to deliver approval requests. When someone in this Space asks to use an item, the request appears as an alert on this device.",
                denied: blocker == .notificationsDenied) {
                step = .checking
                Task { await checkPrerequisites() }
            }
        case .iCloudUnavailable:
            VaultStatusScreen(
                icon: Icons.info,
                tint: .warning,
                title: "Sign in to iCloud",
                message: .key("Sign in to iCloud to share access. Sharing uses an encrypted approval transport; it does not turn on vault sync."),
                primary: .init(title: "Check again") {
                    step = .checking
                    Task { await checkPrerequisites() }
                })
        }
    }

    // MARK: Config (pick Space + recipient)

    private var configForm: some View {
        Form {
            Section {
                if env.repository.activePersonaSpaces.isEmpty {
                    Label { Text("No Spaces yet") } icon: { PolarisIcon(Icons.folder, size: Metric.iconTileLarge) }
                        .themedForeground(.secondary)
                } else {
                    ForEach(env.repository.activePersonaSpaces) { space in
                        Button { selectedSpaceId = space.id } label: {
                            spaceRow(space)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Space to share")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                TextField("Recipient's iCloud email", text: $recipientEmail)
                    .platformKeyboardType(.emailAddress)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Access is tied to this iCloud account. Only they can accept, and no link works for anyone else.")
            }
            .listRowBackground(VaultColors.surface)

            if selectedSpace != nil {
                Section {
                    LabeledContent("Logins") {
                        Text("\(eligibleCount) of \(spaceItems.count)")
                    }
                } header: {
                    Text("What's shared")
                } footer: {
                    // Zero eligible logins is policy, not a bug: the safelist
                    // only ever hands over logins, so say that where the count
                    // and the dead CTA are visible.
                    if eligibleCount == 0 {
                        Text("Only logins can be shared, so nothing in this Space qualifies yet.")
                    } else {
                        Text("This shares usernames, passwords, email addresses, and websites for every eligible login currently in this Space.")
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: $allowMultipleDevices) {
                        Label { Text("Allow use on multiple devices") } icon: { PolarisIcon(Icons.apps) }
                    }
                } footer: {
                    Text("When off, everything is encrypted for the first device they enrolled. Their other devices only see a locked placeholder.")
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                Button {
                    Task { await createShare() }
                } label: {
                    Text("Share this Space").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .disabled(!canShare)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func spaceRow(_ space: Folder) -> some View {
        HStack(spacing: Space.s3) {
            FolderBadge(icon: space.iconAsset, color: space.color, size: Metric.badgeTile)
            Text(space.name).themedForeground()
            Spacer()
            Text("\(env.repository.itemCount(for: space.id))").themedForeground(.secondary)
            if selectedSpaceId == space.id {
                PolarisIcon(Icons.check, size: 18).foregroundStyle(Color(rgb: env.theme.active.accent))
            }
        }
        .contentShape(.rect)
    }

    // MARK: Ceremony (identical shape to ShareAccessSheet — createShare → wait → fingerprint)

    private func createShare() async {
        guard case .config = step, selectedSpace != nil else { return }
        step = .creating
        pollExhausted = false
        participantHasAccepted = false
        do {
            let setup = try await env.approvalShare.createShare(
                recipientEmail: normalizedRecipient, existingZoneName: existingZoneName)
            var inviteURL = setup.shareURL
            if let shareURL = setup.shareURL,
               let minted = try? await env.inviteLinks.createInviteLink(shareURL: shareURL) {
                inviteURL = minted.url
                pendingInviteRecordName = minted.recordName
            }
            // Approval Mode listening must be on before the accept push can
            // be received (mirrors ShareAccessSheet.createShare).
            env.settings.approvalModeEnabled = true
            step = .waiting(zoneID: setup.zoneID, shareURL: inviteURL)
        } catch {
            step = .failed(SharingErrorMessage.text(for: error))
        }
    }

    /// Structured poll (auto-cancelled via `.task(id:)`) — same shape as
    /// `ShareAccessSheet.pollForProfile`, without the auto-invite-drop
    /// retry (Loox-to-Loox rendezvous tier): the Messages/ShareLink nudge
    /// below remains the primary delivery path either way.
    private func pollForProfile(zoneName: String) async {
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        var delay: Duration = .seconds(3)
        for _ in 0..<24 { // ≈ 2.5 minutes at the capped interval
            guard !Task.isCancelled else { return }
            if let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) {
                // Their key is here and the owner already chose the Space and
                // the recipient — the fan-out's field scope is derived by
                // `SpaceShareSafelist`, not by a human, so there is nothing
                // left to ask. Publish straight through.
                await confirmedProfile(zoneID: zoneID, profile: profile)
                return
            }
            if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                participantHasAccepted = true
            }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(10))
        }
        pollExhausted = true
    }

    private func checkProfileNow() async {
        guard case .waiting(let zoneID, _) = step else { return }
        guard let profile = try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID) else {
            if await env.approvalShare.participantAccepted(zoneID: zoneID) {
                participantHasAccepted = true
            }
            return
        }
        await confirmedProfile(zoneID: zoneID, profile: profile)
    }

    private func waitingView(shareURL: URL?) -> some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                ShareInviteSentSheet(recipientLabel: recipientEmail,
                                     itemTitle: selectedSpace?.name ?? appString("this Space"),
                                     accepted: participantHasAccepted)

                if pollExhausted {
                    Text("Still waiting. You can close this screen and finish later, or check again from the menu above.")
                        .vaultType(.footnote).themedForeground(.secondary).multilineTextAlignment(.center)
                }

                VStack(spacing: Space.s3) {
                    if participantHasAccepted {
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                    } else if let shareURL {
                        #if os(iOS)
                        if MessageComposeView.canSendText {
                            Button {
                                showMessageCompose = true
                            } label: {
                                Label { Text("Nudge via Messages") } icon: { PolarisIcon(Icons.share) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themedProminent)
                            .sheet(isPresented: $showMessageCompose) {
                                MessageComposeView(
                                    recipients: [normalizedRecipient],
                                    body: appString("I shared an item with you in Loox Password. Open this link on your iPhone to accept: \(shareURL.absoluteString)"))
                            }
                        } else {
                            ShareLink(item: shareURL) {
                                Label { Text("Share invite link") } icon: { PolarisIcon(Icons.share) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themedProminent)
                        }
                        #else
                        ShareLink(item: shareURL) {
                            Label { Text("Share invite link") } icon: { PolarisIcon(Icons.share) }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                        #endif
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedTinted)
                    } else {
                        Button { dismiss() } label: {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                    }
                }

                if !participantHasAccepted {
                    Text("First time sharing with someone? A Messages nudge helps them find the invite.")
                        .vaultType(.footnote).themedForeground(.tertiary).multilineTextAlignment(.center)
                }
            }
            .padding(Space.gutter)
        }
    }

    /// The recipient's key has landed: freeze it as the fan-out's recipient
    /// context and publish. No owner step in between — the Space and the
    /// recipient were chosen at create time, and the per-item field scope is
    /// derived by `SpaceShareSafelist` rather than by a human.
    private func confirmedProfile(zoneID: CKRecordZone.ID,
                                  profile: (participantPubKey: Data, deviceSigningKeys: [Data],
                                            deviceHPKEDirectory: [DeviceHPKEDirectoryEntry],
                                            createdAtUnixMs: Int64)) async {
        // Acceptance is proven — GC the invite link now.
        if let pendingInviteRecordName {
            await env.inviteLinks.deleteInvite(recordName: pendingInviteRecordName)
            self.pendingInviteRecordName = nil
        }
        resolvedRecipient = SpaceShareRecipientContext(
            zoneID: zoneID,
            recipientLabel: normalizedRecipient,
            profile: SharedGrantComposer.RecipientProfile(
                participantPubKey: profile.participantPubKey,
                deviceSigningKeys: profile.deviceSigningKeys,
                deviceHPKEDirectory: profile.deviceHPKEDirectory),
            deviceScope: allowMultipleDevices ? .multi : .single)
        await publishFanOut()
    }

    // MARK: Fan-out (the one step that is NOT the single-item sheet's shape)

    /// Re-invoked by the Retry button on a partial/failed result — safe
    /// because `SpaceShareMembershipExecutor.reconcile` always starts from a
    /// fresh live-grant read and is a pure diff of that against the Space's
    /// CURRENT items, so re-running it after a partial failure only retries
    /// what didn't already land.
    private func publishFanOut() async {
        guard let recipient = resolvedRecipient, let selectedSpace else { return }
        step = .publishing
        do {
            let executor = SpaceShareMembershipExecutor(
                publisher: LiveSpaceShareGrantPublisher(service: env.approvalShare, store: env.store),
                store: env.sharingStore)
            let summary = try await executor.reconcile(
                spaceItems: env.repository.items(inFolder: selectedSpace.id),
                recipient: recipient,
                nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
            step = .result(summary)
        } catch {
            step = .failed(SharingErrorMessage.text(for: error))
        }
    }

    private var publishingView: some View {
        VaultStatusScreen(busySystemImage: "person.2.badge.key",
                          title: "Sharing your Space…",
                          message: .key("\(eligibleCount) items"),
                          busy: true)
    }

    // MARK: Result

    private func resultView(_ summary: SpaceShareMembershipExecutor.Summary) -> some View {
        let created = summary.outcomes.filter { $0.kind == .created }.count
        let updated = summary.outcomes.filter { $0.kind == .updated }.count
        let revoked = summary.outcomes.filter { $0.kind == .revoked }.count
        let hasFailures = !summary.failures.isEmpty
        return ScrollView {
            VStack(spacing: Space.s5) {
                PolarisIcon(hasFailures ? Icons.alert : Icons.shield, size: Metric.iconTileLarge)
                    .themedForeground(hasFailures ? .warning : .success)
                Text(hasFailures ? "Needs attention" : "Space shared")
                    .vaultType(.section).themedForeground()
                Text(hasFailures
                     ? "Most of this Space shared. A few items couldn't be sent. Items already shared are untouched."
                     : "They can now use every shared login in this Space. Manage or revoke access anytime from Family.")
                    .vaultType(.callout).themedForeground(.secondary).multilineTextAlignment(.center)

                countsCard(created: created, updated: updated, revoked: revoked)

                if hasFailures {
                    failuresCard(summary.failures)
                }

                VStack(spacing: Space.s3) {
                    if hasFailures {
                        Button { Task { await publishFanOut() } } label: {
                            Text("Retry").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                        Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                            .buttonStyle(.themedTinted)
                    } else {
                        Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                            .buttonStyle(.themedProminent)
                    }
                }
            }
            .padding(Space.gutter)
        }
    }

    private func countsCard(created: Int, updated: Int, revoked: Int) -> some View {
        VStack(spacing: Space.s2) {
            countRow(label: "Added", value: created)
            countRow(label: "Updated", value: updated)
            countRow(label: "Removed", value: revoked)
        }
        .padding(Space.s4)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func countRow(label: LocalizedStringResource, value: Int) -> some View {
        HStack {
            Text(label.inAppLocalized).themedForeground(.secondary)
            Spacer()
            Text(verbatim: "\(value)").themedForeground()
        }
    }

    /// Best-effort item title per failed key: create/update failures are
    /// keyed by itemId (resolves directly); revoke failures are keyed by
    /// grantId (falls back to a generic label — resolving a grantId back to
    /// its item after the grant is gone isn't worth the extra bookkeeping for
    /// a first pass at this UI).
    private func failuresCard(_ failures: [String: Error]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("\(failures.count) items").vaultType(.headline).themedForeground()
            ForEach(Array(failures.keys.sorted()), id: \.self) { key in
                Text(verbatim: failureLabel(key))
                    .vaultType(.footnote).themedForeground(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func failureLabel(_ key: String) -> String {
        let title = env.repository.item(id: key)?.title
        return (title?.isEmpty == false ? title! : appString("an item"))
    }

    /// `message` is a service error the caller already resolved, so it goes in
    /// the verbatim slot rather than the catalog.
    private func failedView(_ message: String) -> some View {
        // Retry resumes the fan-out once the ceremony is done; before that the
        // only way forward is back to the picker.
        let actionTitle: LocalizedStringKey = resolvedRecipient != nil ? "Retry" : "Try again"
        return VaultStatusScreen(
            icon: Icons.alert,
            tint: .destructive,
            title: "Something went wrong",
            message: .verbatim(message),
            primary: .init(title: actionTitle) {
                if resolvedRecipient != nil {
                    Task { await publishFanOut() }
                } else {
                    step = .config
                }
            })
    }
}
