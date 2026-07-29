import SwiftUI

/// One person you share vault items with, aggregated from the owner-side share registry.
private struct FamilyMember: Identifiable {
    let label: String            // recipient email (owner-local; never leaves this device)
    let shares: [ItemShareRecord]
    var id: String { label }

    var activeCount: Int { shares.filter { $0.status == .active }.count }
    var pendingCount: Int { shares.count - activeCount }
}

/// Family — the people you share vault items with, grouped from `SharingStore`.
///
/// There is no membership entity behind this screen and there does not need to
/// be: a person exists here because you shared something with them. The invite
/// IS the relationship. What the screen has to do is make that legible, which
/// means offering a way to START a relationship ("Invite someone") rather than
/// only ever listing the side effects of item sharing.
struct FamilyScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showShareSpace = false

    private var members: [FamilyMember] {
        Dictionary(grouping: env.sharingStore.shares, by: \.recipientLabel)
            .map { FamilyMember(label: $0.key, shares: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                shareSpaceButton
                if members.isEmpty {
                    emptyState
                } else {
                    ProfileGroupCard {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberRow(member)
                            if index < members.count - 1 {
                                Rectangle()
                                    .fill(Color(rgb: env.theme.active.separator))
                                    .frame(height: 0.5)
                                    .padding(.leading, Space.s4 + Metric.avatarRow + Space.s3)
                            }
                        }
                    }
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Family")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSpace) { ShareSpaceSheet() }
    }

    /// Sole primary action on this screen (action-hierarchy rule). It fans a
    /// whole Space out to one person in a single ceremony, which is also the
    /// only way to reach someone from here rather than from an item.
    private var shareSpaceButton: some View {
        Button { showShareSpace = true } label: {
            HStack(spacing: Space.s2) {
                VaultIcon(Icons.share, size: Metric.iconInline)
                Text("Invite someone")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        NavigationLink { FamilyMemberScreen(label: member.label) } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(Color(rgb: env.theme.active.accentSoft))
                        .frame(width: Metric.avatarRow, height: Metric.avatarRow)
                    Text(verbatim: initial(member.label))
                        .vaultType(.subhead).themedForeground(.accentText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: member.label).vaultType(.body).themedForeground().lineLimit(1)
                    // A bare count read as an unread badge and silently mixed
                    // pending invites into the total. Name the unit, and keep
                    // "waiting" separate from "they can use this".
                    Text(subtitle(member))
                        .vaultType(.subhead).themedForeground(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VaultIcon(Icons.chevronRight, size: Metric.iconCompact)
                    .themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ member: FamilyMember) -> LocalizedStringResource {
        if member.activeCount == 0 { return "Waiting to accept" }
        if member.pendingCount == 0 { return "\(member.activeCount) shared" }
        return "\(member.activeCount) shared, \(member.pendingCount) waiting"
    }

    private var emptyState: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                Circle().fill(Color(rgb: env.theme.active.accentSoft))
                    .frame(width: Metric.avatarHero, height: Metric.avatarHero)
                VaultIcon(Icons.organization, size: Metric.iconTileLarge)
                    .themedForeground(.accent)
            }
            VStack(spacing: Space.s2) {
                Text("No one yet").vaultType(.headline).themedForeground()
                Text("Invite someone above, or share a single item from the item itself. Either way they show up here.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s8)
    }

    private func initial(_ label: String) -> String {
        guard let first = label.first else { return "?" }
        return first.uppercased()
    }
}

/// One person's shared items. Each row opens the share detail (manage what they
/// can use, push an update, or revoke just that item).
private struct FamilyMemberScreen: View {
    let label: String
    @Environment(AppEnvironment.self) private var env
    @State private var selectedShare: ItemShareRecord?
    @State private var resumeShare: ItemShareRecord?

    /// Derived from the observed store on every render, never captured at push
    /// time: revoking inside the detail sheet mutates the store, and a snapshot
    /// taken by the parent list would keep showing rows whose share is gone —
    /// tapping one would open a detail sheet for a record that no longer exists.
    private var shares: [ItemShareRecord] {
        env.sharingStore.shares(forRecipient: label)
            .sorted { itemTitle($0).localizedCaseInsensitiveCompare(itemTitle($1)) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                if shares.isEmpty {
                    emptyState
                } else {
                    ProfileGroupCard {
                        ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                            shareRow(share)
                            if index < shares.count - 1 {
                                Rectangle()
                                    .fill(Color(rgb: env.theme.active.separator))
                                    .frame(height: 0.5)
                                    .padding(.leading, Space.s4 + Metric.iconTile + Space.s3)
                            }
                        }
                    }
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle(label)
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedShare) { ShareRecipientDetailSheet(share: $0) }
        .sheet(item: $resumeShare) { ShareResumeStepperSheet(share: $0) }
    }

    private func shareRow(_ share: ItemShareRecord) -> some View {
        Button {
            // Same routing rule the item screen uses: an unfinished share needs
            // the resume surface, not the manage surface, which for a pending
            // record shows only info and Revoke and so dead-ends.
            if share.status == .active { selectedShare = share } else { resumeShare = share }
        } label: {
            HStack(spacing: Space.s3) {
                // Received items used to render with no type at all here; the
                // category avatar is what tells a Secure Note from a login.
                VaultIcon(categoryIcon(share), size: Metric.iconTile)
                    .themedForeground(.iconSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: itemTitle(share)).vaultType(.body).themedForeground().lineLimit(1)
                    Text(ShareStepper.detailSubtitle(for: share.status))
                        .vaultType(.subhead)
                        .themedForeground(share.status == .active ? .success : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VaultIcon(Icons.chevronRight, size: Metric.iconCompact)
                    .themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s2) {
            Text("Nothing shared").vaultType(.headline).themedForeground()
            Text("You revoked everything you had shared with this person.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s8)
    }

    private func itemTitle(_ share: ItemShareRecord) -> String {
        if let title = env.repository.item(id: share.itemId)?.title, !title.isEmpty { return title }
        return appString("an item")
    }

    private func categoryIcon(_ share: ItemShareRecord) -> String {
        env.repository.item(id: share.itemId)?.category.avatarIcon ?? Icons.lock
    }
}
