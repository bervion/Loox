import SwiftUI

/// Editorial landing page for a paid plan (Loox+ or Loox Max), pushed from the
/// paywall's "Learn more" link. Reuses the About page's storytelling language —
/// two-line hero with the accent second line, the fixed dark ink block, and
/// icon feature rows on a themed card — so the membership story reads like the
/// rest of the brand. Every number comes from the frozen `LooxQuotas` table;
/// nothing commercial is hardcoded here.
struct LooxPlanLandingScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// `.plus` or `.max` — `.free` has no landing (the paywall never links it).
    let tier: LooxTier

    private var quotas: LooxQuotas { tier.quotas }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                hero
                inkBlock
                featureCard
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.s4)
        }
        .themedFormBackground()
        .navigationTitle(Text(verbatim: tier.displayName))
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero — two-line hook, accent close (About idiom)

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // One-shot brand reveal, same animation as the Security empty
            // state (owner request 260716) — leading-aligned with the
            // editorial copy; the component collapses under Reduce Motion.
            LooxSwirlAnimationView(mode: .reveal)
                .frame(width: 112, height: 112)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if tier == .max {
                    Text("Everything Loox can do.")
                        .vaultType(.largeTitle).themedForeground(.primary)
                    Text("For your whole world.")
                        .vaultType(.largeTitle).themedForeground(.accent)
                } else {
                    Text("Set it once.")
                        .vaultType(.largeTitle).themedForeground(.primary)
                    Text("Stay protected.")
                        .vaultType(.largeTitle).themedForeground(.accent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(tier == .max
                 ? "Loox Max is the full product: room for every alias, sharing for the people you trust, and services sized for daily use."
                 : "Loox+ keeps your digital life maintained: weak spots surfaced, private addresses for sites that leak, and a workflow that does the follow-up for you.")
                .vaultType(.body)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Ink block (About's fixed dark editorial card)

    private var inkBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Why upgrade")
                .vaultType(.sectionLabel)
                .foregroundStyle(AboutInk.highlight)
            Text(tier == .max
                 ? "One plan that covers everything you protect."
                 : "Good security is a habit. Loox+ makes it an easy one.")
                .vaultType(.headline)
                .foregroundStyle(AboutInk.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(tier == .max
                 ? "Higher limits everywhere, sharing seats for the people around you, and every service sized for daily use."
                 : "The full Watchtower workflow keeps watch, and private addresses keep your real inbox out of strangers' databases.")
                .vaultType(.subhead)
                .foregroundStyle(AboutInk.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AboutInk.surface)
        .vaultCornerRadius(Radius.lg)
    }

    // MARK: Feature rows (quota-driven)

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Included with Loox")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.leading, Space.s1)
            VStack(alignment: .leading, spacing: Space.s4) {
                planRow(Icons.mail,
                        appString("Up to \(quotas.retainedAliases) private addresses"),
                        appString("A different address for every site. Pause or delete one the moment it leaks."))
                planRow(Icons.organization,
                        sharingTitle,
                        appString("Approval Mode seats for the people you trust. They ask, you approve, and secrets stay in your vault."))
                planRow(Icons.watchtower,
                        appString("Full protection"),
                        appString("Every finding with the Fix Queue, history and reminders, not just the critical ones."))
                planRow(Icons.share,
                        appString("Room for everyday sharing"),
                        appString("Up to \(quotas.linkCreates30d) share links and \(quotas.quickViewApprovals30d) browser approvals in any 30 days."))
                planRow(Icons.person,
                        profilesTitle,
                        appString("Separate work, personal, and anything in between."))
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(padding: 0)
        }
    }

    private var sharingTitle: String {
        quotas.outgoingRecipients == 1
            ? appString("Share with one trusted person")
            : appString("Secure sharing with up to \(quotas.outgoingRecipients) people")
    }

    private var profilesTitle: String {
        if let cap = quotas.personas {
            return appString("Up to \(cap) profiles")
        }
        return appString("Profiles without a cap")
    }

    private func planRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            PolarisIcon(icon, size: 22)
                .themedForeground(.accentText)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .vaultType(.subhead).fontWeight(.medium).themedForeground(.primary)
                Text(verbatim: detail)
                    .vaultType(.caption).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
