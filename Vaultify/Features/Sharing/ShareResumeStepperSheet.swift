import CloudKit
import SwiftUI

/// The canonical "resume a pending share" surface (design 12c) — reachable
/// from Home's pending row, Item Detail's "Shared with" section, and the
/// Notifications "Shares you sent" row alike, so a share left mid-flight
/// always resolves to the same 4-step picture no matter where it's resumed.
///
/// UI-layer only: every action here calls services `ShareAccessSheet` /
/// `ShareRecipientDetailSheet` already call (idempotent `createShare` to
/// re-mint the invite link, the same status-only CloudKit reads
/// `OwnerShareRefresher` uses, the same `revoke`). No new protocol surface.
struct ShareResumeStepperSheet: View {
    let share: ItemShareRecord
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showMessageCompose = false
    @State private var pendingShareURL: URL?
    @State private var confirmCancel = false
    @State private var continueShare = false
    @State private var busy = false
    @State private var errorMessage: String?
    /// Neutral feedback (e.g. "no update yet") — secondary styling, not red.
    @State private var noticeMessage: String?

    /// Re-read live from the store on every render — `share` is a value-type
    /// snapshot from whichever list presented this sheet, so Check Now must
    /// reflect through the store, not the frozen parameter.
    private var liveShare: ItemShareRecord {
        env.sharingStore.shares.first { $0.zoneName == share.zoneName } ?? share
    }
    private var item: VaultItem? { env.repository.item(id: share.itemId) }
    private var itemTitle: String { item?.title.isEmpty == false ? item!.title : appString("this item") }

    var body: some View {
        VaultSheetScaffold(title: LocalizedStringResource("Sharing \"\(itemTitle)\""),
                           trailing: { toolbarTrailing }) {
            ScrollView {
                VStack(spacing: Space.s5) {
                    Text("with \(share.recipientLabel), started \(startedText)")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    stepperCard

                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .vaultType(.footnote).themedForeground(.destructive)
                            .multilineTextAlignment(.center)
                    }
                    if let noticeMessage {
                        Text(verbatim: noticeMessage)
                            .vaultType(.footnote).themedForeground(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    actionButtons
                }
                .padding(Space.gutter)
            }
        }
        .sheet(isPresented: $continueShare) {
            ShareAccessSheet(itemID: share.itemId, resumeEmail: share.recipientLabel)
        }
        .confirmationDialog("Cancel this invite?", isPresented: $confirmCancel,
                            titleVisibility: .visible) {
            Button("Cancel Invite", role: .destructive) { Task { await cancelInvite() } }
        } message: {
            Text("They won't be able to accept it anymore. You can share again anytime.")
        }
        #if os(iOS)
        .sheet(isPresented: $showMessageCompose) {
            if let pendingShareURL {
                MessageComposeView(
                    recipients: [share.recipientLabel],
                    body: appString(
                        "I shared an item with you in Loox Password. Open this link on your iPhone to accept: \(pendingShareURL.absoluteString)"))
            }
        }
        #endif
    }

    /// Cancelling the invite is destructive, once-per-screen, and low
    /// frequency next to "keep going" — demoted to the toolbar overflow
    /// (action-hierarchy rule) instead of sitting beside Check Now.
    @ViewBuilder private var toolbarTrailing: some View {
        if liveShare.status != .active {
            Menu {
                Button(role: .destructive) {
                    confirmCancel = true
                } label: { Label("Cancel Invite", image: Icons.trash) }
            } label: {
                PolarisIcon("ic_menu_horizontal", size: Metric.iconInline)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(busy)
        }
    }

    private var startedText: String {
        Date(timeIntervalSince1970: Double(share.createdAtUnixMs) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Stepper card

    private var stepperCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ForEach(ShareStepper.steps(for: liveShare.status)) { step in
                stepRow(step)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
        )
    }

    private func stepRow(_ step: ShareStepperStep) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            stepBubble(step)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title.inAppLocalized)
                    .vaultType(.headline)
                    .themedForeground(step.state == .current ? .warning : .primary)
                    .opacity(step.state == .todo ? 0.4 : 1)
                Text(step.subtitle.inAppLocalized)
                    .vaultType(.footnote).themedForeground(.secondary)
                    .opacity(step.state == .todo ? 0.4 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func stepBubble(_ step: ShareStepperStep) -> some View {
        ZStack {
            switch step.state {
            case .done:
                Circle().fill(Color(rgb: env.theme.active.successSoft))
                PolarisIcon(Icons.check, size: 12).themedForeground(.success)
            case .current:
                Circle().strokeBorder(env.theme.active.color(.warning), lineWidth: 2)
                ProgressView().controlSize(.mini)
            case .todo:
                Circle().strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 1.5)
                Text(verbatim: "\(step.id)")
                    .vaultType(.caption).themedForeground(.tertiary)
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: Actions

    /// One filled primary per state (the ranked next step) plus at most one
    /// quiet secondary ("Check now" — a manual refresh, not the expected
    /// action). Cancelling the invite is destructive and demoted to the
    /// toolbar overflow (`toolbarTrailing`) instead of standing beside it.
    @ViewBuilder private var actionButtons: some View {
        VStack(spacing: Space.s3) {
            switch liveShare.status {
            case .active:
                // Fully active (e.g. activation just finished in the nested
                // sheet) — nudging or cancelling the invite no longer applies.
                Text("Access is active. \(share.recipientLabel) can use this item now.")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                Button { dismiss() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)

            case .readyForCeremony:
                Button {
                    continueShare = true
                } label: {
                    Text("Continue to Activate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                checkNowButton

            case .accepted:
                // They already accepted — re-sending the invite would be
                // misleading; the wait is on their device publishing a profile.
                Text("\(share.recipientLabel) accepted. Waiting for their device to finish setting up, usually right after they unlock Loox.")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                checkNowButton

            case .inviteSent:
                Button {
                    Task { await sendNudge() }
                } label: {
                    if busy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label { Text("Send Invite via Messages") } icon: { PolarisIcon(Icons.share) }
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.themedProminent)
                .disabled(busy)
                checkNowButton
            }
        }
    }

    private var checkNowButton: some View {
        Button {
            Task { await checkNow() }
        } label: {
            Text("Check now").frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedTinted)
        .disabled(busy)
    }

    /// Idempotent — re-mints/re-fetches the SAME CKShare URL (no new zone,
    /// no new participant) purely to hand it to a Messages compose window.
    private func sendNudge() async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            let setup = try await env.approvalShare.createShare(
                recipientEmail: share.recipientLabel, existingZoneName: share.zoneName)
            pendingShareURL = setup.shareURL
            guard setup.shareURL != nil else { return }
            #if os(iOS)
            if MessageComposeView.canSendText {
                showMessageCompose = true
            } else {
                errorMessage = appString("Messages isn't available on this device.")
            }
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Same status-only CloudKit reads `OwnerShareRefresher` runs in the
    /// background — this is the manual, immediate counterpart of it. Always
    /// leaves visible feedback: advancing the stepper, an offline notice, or
    /// a "no update yet" note — a silent tap reads as a broken button.
    private func checkNow() async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        noticeMessage = nil
        guard env.capabilities.connectivity == .online else {
            errorMessage = appString("You're offline. Try again once you're connected.")
            return
        }
        let before = liveShare.status
        let zoneID = CKRecordZone.ID(zoneName: share.zoneName)
        if (try? await env.approvalShare.fetchParticipantProfile(zoneID: zoneID)) != nil {
            env.sharingStore.updateStatus(zoneName: share.zoneName, to: .readyForCeremony)
        } else if await env.approvalShare.participantAccepted(zoneID: zoneID) {
            env.sharingStore.updateStatus(zoneName: share.zoneName, to: .accepted)
        }
        if liveShare.status == before {
            noticeMessage = appString("No update yet. You'll see the step advance once they act.")
        }
    }

    private func cancelInvite() async {
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
}
