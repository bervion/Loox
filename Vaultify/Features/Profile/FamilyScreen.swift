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
    @State private var route: FamilyShareRoute?
    @State private var pendingRoute: FamilyShareRoute?

    private var members: [FamilyMember] {
        Dictionary(grouping: MemberFeatureProjection.outgoingShares(env.sharingStore.shares,
                          ownedItems: env.repository.memberOwnedItems), by: \.recipientLabel)
            .map { FamilyMember(label: $0.key, shares: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("People appear here when you share an item or a Space with them.")
                        .vaultType(.callout).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                    if let persona = env.repository.activePersona {
                        Text(verbatim: persona.displayName).vaultType(.subhead).themedForeground(.secondaryBody)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if members.isEmpty {
                    emptyState
                } else {
                    ProfileGroupCard {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberRow(member)
                            if index < members.count - 1 {
                                Divider()
                                    .padding(.leading, Space.s4 + Metric.avatarRow + Space.s3)
                            }
                        }
                    }
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle(Text("Family"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { shareSpaceButton.padding(Space.gutter)
                .background(Color(rgb: env.theme.active.groupedBackground)) }
        .sheet(item: $route, onDismiss: advanceRoute) { route in
            switch route {
            case .scope:
                FamilyShareScopeSheet { next in pendingRoute = next }
            case .itemPicker:
                MemberItemChooserSheet(title: "Choose an item", needsSnapshotFields: false) { itemID, personaID in
                    pendingRoute = .item(MemberItemSelection(id: itemID, personaID: personaID))
                }
            case .item(let selected):
                ShareAccessSheet(itemID: selected.id, entry: .approvalOnly, ownerPersonaID: selected.personaID)
            case .space:
                ShareSpaceSheet()
            }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in route = nil; pendingRoute = nil }
        .refreshable { await env.ownerShareRefresher.refreshAndWait() }
    }

    /// Sole primary action on this screen (action-hierarchy rule). It fans a
    /// whole Space out to one person in a single ceremony, which is also the
    /// only way to reach someone from here rather than from an item.
    private var shareSpaceButton: some View {
        Button { route = .scope } label: {
            HStack(spacing: Space.s2) {
                VaultIcon(Icons.share, size: Metric.iconInline)
                Text("Share with family")
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
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(verbatim: member.label).vaultType(.body).themedForeground()
                        .fixedSize(horizontal: false, vertical: true)
                    // A bare count read as an unread badge and silently mixed
                    // pending invites into the total. Name the unit, and keep
                    // "waiting" separate from "they can use this".
                    Text(subtitle(member).inAppLocalized)
                        .vaultType(.subhead).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
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
        if member.activeCount == 0 { return "\(member.pendingCount) waiting" }
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
                Text("Share a saved item or a Space to start. You choose what each person can use.")
                    .vaultType(.callout).themedForeground(.secondaryBody)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s8)
    }

    private func initial(_ label: String) -> String {
        guard let first = label.first else { return "?" }
        return first.uppercased()
    }

    private func advanceRoute() {
        defer { pendingRoute = nil }
        guard let pendingRoute else { return }
        if case .item(let selected) = pendingRoute,
           !env.repository.memberCanUseItem(selected.id, personaID: selected.personaID,
                                             needsSnapshotFields: false) { return }
        route = pendingRoute
    }
}

/// One person's shared items. Each row opens the share detail (manage what they
/// can use, push an update, or revoke just that item).
private struct FamilyMemberScreen: View {
    let label: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShare: ItemShareRecord?
    @State private var resumeShare: ItemShareRecord?

    /// Derived from the observed store on every render, never captured at push
    /// time: revoking inside the detail sheet mutates the store, and a snapshot
    /// taken by the parent list would keep showing rows whose share is gone —
    /// tapping one would open a detail sheet for a record that no longer exists.
    private var shares: [ItemShareRecord] {
        MemberFeatureProjection.outgoingShares(env.sharingStore.shares(forRecipient: label),
                                               ownedItems: env.repository.memberOwnedItems)
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
                                Divider()
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
        .refreshable { await env.ownerShareRefresher.refreshAndWait() }
        .onChange(of: env.repository.activePersona?.id) { _, _ in selectedShare = nil; resumeShare = nil; dismiss() }
    }

    private func shareRow(_ share: ItemShareRecord) -> some View {
        Button {
            guard env.repository.memberOwnedItems.contains(where: { $0.id == share.itemId }),
                  env.sharingStore.shares.contains(where: { $0.id == share.id }) else { return }
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
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(verbatim: itemTitle(share)).vaultType(.body).themedForeground()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ShareStepper.detailSubtitle(for: share.status).inAppLocalized)
                        .vaultType(.subhead)
                        .themedForeground(share.status == .active ? .successBody : .secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
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
            Text("There are no shared items with this person in the current profile.")
                .vaultType(.callout).themedForeground(.secondaryBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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

private enum FamilyShareRoute: Identifiable {
    case scope, itemPicker, item(MemberItemSelection), space
    var id: String {
        switch self {
        case .scope: "scope"
        case .itemPicker: "item-picker"
        case .item(let selected): "item-\(selected.id)"
        case .space: "space"
        }
    }
}

private struct FamilyShareScopeSheet: View {
    let onSelect: (FamilyShareRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VaultSheetScaffold(title: "Share with family") {
            Form {
                Section {
                    option(icon: Icons.lock, title: "Share one item",
                           subtitle: "Choose a saved item and the permissions for one person.", route: .itemPicker)
                    option(icon: Icons.folder, title: "Share a Space",
                           subtitle: "Share eligible items from one Space with one person.", route: .space)
                } footer: {
                    Text("Sharing uses Approval Mode over iCloud. It does not turn on vault sync.")
                        .themedForeground(.secondaryBody)
                }
                .listRowBackground(VaultColors.surface)
            }
        }
    }

    private func option(icon: String, title: LocalizedStringResource,
                        subtitle: LocalizedStringResource, route: FamilyShareRoute) -> some View {
        Button {
            onSelect(route)
            dismiss()
        } label: {
            HStack(spacing: Space.s3) {
                VaultIcon(icon, size: Metric.iconUtility).themedForeground(.accentText)
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(title.inAppLocalized).vaultType(.headline).themedForeground()
                    Text(subtitle.inAppLocalized).vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                VaultIcon(Icons.chevronRight, size: Metric.iconInline).themedForeground(.iconSecondary)
            }
            .frame(minHeight: Metric.hitMin)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
