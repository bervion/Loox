import SwiftUI

/// One person you share vault items with, aggregated from the owner-side share registry.
private struct FamilyMember: Identifiable {
    let label: String            // recipient email (owner-local; never leaves this device)
    let shares: [ItemShareRecord]
    var id: String { label }
}

/// Family — the people you share vault items with, grouped from `SharingStore`. A members
/// list; tap a person to see and manage (or revoke) what they can access. "Share a Space"
/// (`ShareSpaceSheet`) fans a whole Space's eligible logins out to one member in a single
/// ceremony (Family full-group sharing, phase A3); individual items can still be shared
/// via each item's own Share sheet, and both paths populate this same members list.
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
                                    .padding(.leading, Space.s4 + 36 + Space.s3)
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

    /// Sole primary action on this screen (action-hierarchy rule) — fans a
    /// whole Space out to one member in a single ceremony (`ShareSpaceSheet`).
    private var shareSpaceButton: some View {
        Button { showShareSpace = true } label: {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.share, size: Metric.iconInline)
                Text("Share a Space")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        NavigationLink { FamilyMemberScreen(label: member.label, shares: member.shares) } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(Color(rgb: env.theme.active.accentSoft)).frame(width: 36, height: 36)
                    Text(verbatim: initial(member.label))
                        .vaultType(.subhead).themedForeground(.accentText)
                }
                Text(verbatim: member.label).vaultType(.body).themedForeground().lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(verbatim: "\(member.shares.count)").themedForeground(.secondary)
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                Circle().fill(Color(rgb: env.theme.active.accentSoft)).frame(width: 92, height: 92)
                PolarisIcon(Icons.organization, size: 40).themedForeground(.accent)
            }
            VStack(spacing: Space.s2) {
                Text("No one yet").vaultType(.headline).themedForeground()
                Text("Share an item, or share a whole Space above, and they'll appear here.")
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

/// One family member's shared items — each row opens the recipient/share detail (manage
/// capabilities, push updates, or revoke) via the existing `ShareRecipientDetailSheet`.
private struct FamilyMemberScreen: View {
    let label: String
    let shares: [ItemShareRecord]
    @Environment(AppEnvironment.self) private var env
    @State private var selectedShare: ItemShareRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                ProfileGroupCard {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        shareRow(share)
                        if index < shares.count - 1 {
                            Rectangle()
                                .fill(Color(rgb: env.theme.active.separator))
                                .frame(height: 0.5)
                                .padding(.leading, Space.s4)
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
    }

    private func shareRow(_ share: ItemShareRecord) -> some View {
        Button { selectedShare = share } label: {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: itemTitle(share)).vaultType(.body).themedForeground().lineLimit(1)
                    Text(statusText(share.status))
                        .vaultType(.subhead)
                        .themedForeground(share.status == .active ? .success : .secondary)
                }
                Spacer(minLength: Space.s2)
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func itemTitle(_ share: ItemShareRecord) -> String {
        if let title = env.repository.item(id: share.itemId)?.title, !title.isEmpty { return title }
        return appString("an item")
    }

    private func statusText(_ status: ShareLifecycle) -> LocalizedStringResource {
        status == .active ? "Active" : "Pending"
    }
}
