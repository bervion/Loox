import SwiftUI

/// Pillar breakdown behind the Vault Health number: six bars, earned/max,
/// one plain-language line each. Tap target of the overview ring.
struct WhyThisScoreScreen: View {
    let payload: AuditReportPayload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(spacing: Space.s1) {
                    Text(verbatim: "\(payload.score)")
                        .vaultType(.largeTitle)
                        .monospacedDigit()
                        .themedForeground(.primary)
                    Text(verbatim: appString("out of 1000"))
                        .vaultType(.footnote)
                        .themedForeground(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s4)

                VStack(spacing: 0) {
                    ForEach(payload.pillars, id: \.pillar) { pillar in
                        PillarRow(score: pillar)
                        if pillar != payload.pillars.last {
                            ThemedDivider().padding(.leading, Space.gutter)
                        }
                    }
                }
                .themedCard(padding: 0)

                Text("The score is the sum of the six areas above. Fix an issue and run the audit again to see the change.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.gutter)
        }
        .themedFormBackground()
        .navigationTitle(Text("Why this score"))
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

private struct PillarRow: View {
    @Environment(AppEnvironment.self) private var env
    let score: PillarScore

    private var fraction: Double {
        score.max > 0 ? Double(score.earned) / Double(score.max) : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(Self.title(score.pillar))
                    .vaultType(.body)
                    .themedForeground(.primary)
                Spacer()
                Text(verbatim: "\(score.earned) / \(score.max)")
                    .vaultType(.footnote)
                    .monospacedDigit()
                    .themedForeground(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(rgb: env.theme.active.separator).opacity(0.5))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text(Self.caption(score.pillar))
                .vaultType(.footnote)
                .themedForeground(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: "\(score.earned) / \(score.max)"))
    }

    private var barColor: Color {
        let theme = env.theme.active
        if fraction >= 0.8 { return Color(rgb: watchtowerGaugeGreen(theme)) }
        if fraction >= 0.5 { return Color(rgb: watchtowerGaugeAmber(theme)) }
        return theme.color(.destructive)
    }

    static func title(_ pillar: AuditPillar) -> LocalizedStringResource {
        let base: LocalizedStringResource = switch pillar {
        case .exposure: "Exposure"
        case .quality: "Password quality"
        case .reuseIsolation: "Reuse isolation"
        case .authReadiness: "Authentication"
        case .integrity: "Vault integrity"
        case .maintenance: "Maintenance"
        }
        return base.inAppLocalized
    }

    static func caption(_ pillar: AuditPillar) -> LocalizedStringResource {
        let base: LocalizedStringResource = switch pillar {
        case .exposure: "Passwords found in known leaks"
        case .quality: "How resistant your passwords are to guessing"
        case .reuseIsolation: "Whether one breach could spread to other accounts"
        case .authReadiness: "Passkeys and verification codes saved in Loox"
        case .integrity: "Duplicates, conflicts, and broken data"
        case .maintenance: "Audit recency and item upkeep"
        }
        return base.inAppLocalized
    }
}
