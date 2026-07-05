import SwiftUI

/// Route value for Home-header bell → notifications.
nonisolated struct NotificationsRoute: Hashable {}

/// Everything awaiting the user's decision (V7): pending share invitations
/// (recipient) and pending approval requests (owner). The push alerts remain
/// the quick path — this screen is the durable inbox behind them.
struct NotificationsScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Approval sheet presented from a request row (same plumbing as the
    /// shell's push-driven presentation — onFinished clears the inbox entry).
    @State private var presentedApproval: ApprovalCoordinator.PendingOwnerRequest?
    @State private var acceptError: String?

    private var invites: [InviteEnvelope] { env.inviteInboxCoordinator.pendingInvites }
    private var requests: [ApprovalCoordinator.PendingOwnerRequest] {
        env.approvalCoordinator.pendingOwnerRequests
    }
    private var history: [NotificationHistoryStore.Entry] { env.notificationHistory.entries }

    var body: some View {
        Group {
            if invites.isEmpty && requests.isEmpty && history.isEmpty {
                ContentUnavailableView {
                    Label { Text("No notifications") } icon: {
                        PolarisIcon(Icons.notification, size: Metric.iconTileLarge)
                    }
                } description: {
                    Text("Share invitations and approval requests appear here.")
                }
            } else {
                List {
                    if !invites.isEmpty {
                        Section("Share invitations") {
                            ForEach(invites, id: \.inviteID) { invite in
                                inviteRow(invite)
                            }
                        }
                        .listRowBackground(VaultColors.surface)
                    }
                    if !requests.isEmpty {
                        Section("Approval requests") {
                            ForEach(requests) { pending in
                                requestRow(pending)
                            }
                        }
                        .listRowBackground(VaultColors.surface)
                    }
                    if !history.isEmpty {
                        Section("Recent") {
                            ForEach(history) { entry in
                                historyRow(entry)
                            }
                        }
                        .listRowBackground(VaultColors.surface)
                    }
                }
                .themedFormBackground()
            }
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Notifications")
        .platformNavigationBarTitleDisplayMode(.inline)
        // The shell's quick-path alert stands down while this screen owns
        // the queue — otherwise the same invite pops twice at once.
        .onAppear {
            env.inviteInboxCoordinator.alertsSuppressed = true
            env.approvalCoordinator.autoPresentSuppressed = true
        }
        .onDisappear {
            env.inviteInboxCoordinator.alertsSuppressed = false
            env.approvalCoordinator.autoPresentSuppressed = false
        }
        .task {
            await env.inviteInboxCoordinator.reconcile()
            env.approvalCoordinator.refreshOwnerRequests()
        }
        .sheet(item: $presentedApproval) { pending in
            ApprovalRequestSheet(
                pending: pending,
                itemTitle: env.repository.item(id: pending.request.itemId)?.title
                    ?? appString("an item"),
                onFinished: {
                    env.approvalCoordinator.clearPending(requestId: pending.request.requestId)
                })
        }
        .alert("Couldn't accept the invitation",
               isPresented: Binding(get: { acceptError != nil },
                                    set: { if !$0 { acceptError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: acceptError ?? "")
        }
    }

    /// "Awaiting your action" marker on pending rows.
    private var pendingDot: some View {
        Circle().fill(env.theme.active.color(.success)).frame(width: 8, height: 8)
    }

    private func inviteRow(_ invite: InviteEnvelope) -> some View {
        HStack(spacing: Space.s3) {
            pendingDot
            PolarisIcon(Icons.share, size: Metric.iconInline).themedForeground(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Share invitation").vaultType(.body).themedForeground()
                Text(Date(timeIntervalSince1970: Double(invite.createdAtUnixMs) / 1000)
                    .formatted(date: .abbreviated, time: .shortened))
                    .vaultType(.footnote).themedForeground(.secondary)
            }
            Spacer(minLength: Space.s2)
            Button("Not Now") { env.inviteInboxCoordinator.dismiss(invite) }
                .buttonStyle(.bordered)
            Button("Accept") {
                Task {
                    do { try await env.inviteInboxCoordinator.accept(invite) }
                    catch { acceptError = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: Metric.hitMin)
    }

    private func historyRow(_ entry: NotificationHistoryStore.Entry) -> some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(historyIcon(entry.kind), size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(historyTitle(entry.kind)).vaultType(.body).themedForeground()
                HStack(spacing: Space.s2) {
                    if let label = entry.label {
                        Text(verbatim: label)
                            .vaultType(.footnote).themedForeground(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text(Date(timeIntervalSince1970: Double(entry.atUnixMs) / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                        .vaultType(.footnote).themedForeground(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metric.hitMin)
    }

    private func historyIcon(_ kind: NotificationHistoryStore.Entry.Kind) -> String {
        switch kind {
        case .inviteReceived, .inviteAccepted, .inviteDismissed: Icons.share
        case .approvalApproved: Icons.shield
        case .approvalRejected: Icons.shieldAlert
        }
    }

    private func historyTitle(_ kind: NotificationHistoryStore.Entry.Kind) -> LocalizedStringKey {
        switch kind {
        case .inviteReceived: "Share invitation received"
        case .inviteAccepted: "Invitation accepted"
        case .inviteDismissed: "Invitation dismissed"
        case .approvalApproved: "Code request approved"
        case .approvalRejected: "Code request rejected"
        }
    }

    private func requestRow(_ pending: ApprovalCoordinator.PendingOwnerRequest) -> some View {
        Button { presentedApproval = pending } label: {
            HStack(spacing: Space.s3) {
                pendingDot
                PolarisIcon(Icons.shield, size: Metric.iconInline).themedForeground(.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Code approval requested").vaultType(.body).themedForeground()
                    Text(Date(timeIntervalSince1970: Double(pending.request.createdAtUnixMs) / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                        .vaultType(.footnote).themedForeground(.secondary)
                }
                Spacer(minLength: Space.s2)
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .frame(minHeight: Metric.hitMin)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
