import SwiftUI

/// Drill-down for the "Overall password strength" card. Answers the two things a
/// user actually taps that card for (adversarial read of the need, DNA #1):
///   1. how the vault splits across Strong / Fair / Weak, and
///   2. WHICH passwords drag the score down — weakest first, each row tapping
///      through to the item so it can be fixed on the spot.
/// Strong items are deliberately NOT listed (progressive disclosure — they're
/// noise here; the distribution row already accounts for them). Scoped to the
/// active persona, like the Watchtower screen that presents it.
struct WatchtowerStrengthScreen: View {
    @Environment(AppEnvironment.self) private var env

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let strength: PasswordStrength
    }

    /// Cached in state: the pattern-aware engine over every password is far too
    /// costly per render (same reasoning as HomeScreen's cached analyze).
    @State private var all: [Entry] = []
    @State private var overallStrength = 100

    private func refresh() {
        let items = env.repository.activePersonaItems
        all = items.compactMap { item in
            guard let field = item.passwordField, !field.value.isEmpty, !field.isExtraProtected
            else { return nil }
            let password = field.value
            return Entry(id: item.id,
                         title: item.title.isEmpty ? appString("Untitled") : item.title,
                         subtitle: item.subtitle,
                         strength: PasswordStrength.evaluate(password))
        }
        overallStrength = PasswordAudit.analyze(items).overallStrength
    }

    var body: some View {
        let toFix = all.filter { $0.strength != .strong }
            .sorted { $0.strength < $1.strength }
        let strongCount = all.count - toFix.count

        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s3) {
                    WatchtowerStrengthBar(value: overallStrength)
                    Text("\(strongCount) of \(all.count) passwords are strong")
                        .vaultType(.callout)
                        .themedForeground(.secondary)
                    ForEach(PasswordStrength.allCases.reversed(), id: \.self) { tier in
                        distributionRow(tier, count: all.filter { $0.strength == tier }.count)
                    }
                }
                .padding(.vertical, Space.s1)
            }
            .listRowBackground(VaultColors.surface)

            if toFix.isEmpty {
                Section {
                    HStack(spacing: Space.s3) {
                        VaultIcon(Icons.checkCircle, size: Metric.iconInline)
                            .themedForeground(.success)
                        Text("Every password is strong and unique.")
                            .vaultType(.callout)
                            .themedForeground(.secondary)
                    }
                }
                .listRowBackground(VaultColors.surface)
            } else {
                Section("To fix") {
                    ForEach(toFix) { entry in
                        NavigationLink(value: entry.id) {
                            strengthRow(entry)
                        }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .themedFormBackground()
        .navigationTitle(Text("Overall password strength"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: env.repository.items.count) { refresh() }
    }

    private func distributionRow(_ tier: PasswordStrength, count: Int) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(VaultColors.strength(tier)).frame(width: 9, height: 9)
            Text(tier.title).vaultType(.subhead).themedForeground(.primary)
            Spacer()
            Text(verbatim: "\(count)").vaultType(.subhead).themedForeground(.secondary)
        }
    }

    private func strengthRow(_ entry: Entry) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title).vaultType(.body).lineLimit(1)
                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).vaultType(.caption)
                        .themedForeground(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            Text(entry.strength.title)
                .vaultType(.caption)
                .foregroundStyle(VaultColors.strength(entry.strength))
        }
    }
}
