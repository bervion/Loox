import SwiftUI

enum PrivateEmailStatusPresentation {
    static func label(_ alias: EmailAlias) -> String {
        switch alias.status {
        case .active: return appString("Forwarding active")
        case .paused, .disabled: return appString("Forwarding paused")
        case .reserved: return alias.backendMinted ? appString("Finish setup") : appString("Not yet active")
        case .draft: return appString("Draft")
        }
    }

    static func role(_ alias: EmailAlias) -> ThemeRole {
        switch alias.status {
        case .active: return .successBody
        case .reserved: return .warningBody
        case .draft, .paused, .disabled: return .secondaryBody
        }
    }
}

struct PrivateEmailFieldValue: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).vaultType(.footnote).themedForeground(.secondaryBody)
            Text(verbatim: value).vaultType(.body).themedForeground(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: Metric.hitMin, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Menu choices use a stacked label/value so native inline picker truncation
/// cannot hide the selected service or recipient at accessibility text sizes.
struct PrivateEmailChoiceLabel: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            PrivateEmailFieldValue(label: label, value: value)
            VaultIcon(Icons.chevronDown, size: Metric.iconInline).themedForeground(.iconSecondary)
        }.frame(minHeight: Metric.hitMin).contentShape(.rect)
    }
}

/// Actionable availability or verification notices take priority. Standing
/// guidance becomes ordinary context so a state never stacks competing banners.
struct PrivateEmailReceiveOnlySection: View {
    let hasActionableNotice: Bool

    var body: some View {
        if hasActionableNotice {
            Section {} footer: {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Receive only").vaultType(.footnote).fontWeight(.semibold)
                    Text("Replying from your inbox may reveal your real email.").vaultType(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }.themedForeground(.secondaryBody)
            }
        } else {
            Section {
                VaultInfoBanner(.info, title: "Receive only",
                                text: "Replying from your inbox may reveal your real email.").subtle().inList()
            }
        }
    }
}

/// Every privacy transition conceals immediately. Returning to the foreground
/// never reveals an address the user revealed in an earlier scene.
struct PrivateEmailRecipientValue: View {
    let email: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(verbatim: revealed ? email : EmailMask.masked(email))
                .vaultType(.body).themedForeground(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Metric.hitMin, alignment: .leading)
                .animation(revealed ? .vault(Motion.standard, reduceMotion: reduceMotion) : nil, value: revealed)
            Button {
                guard scenePhase == .active, env.session.state == .unlocked else { return }
                revealed.toggle()
                Haptics.tap()
            } label: {
                VaultIcon(revealed ? Icons.hide : Icons.reveal, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
                    .frame(width: Metric.hitMin, height: Metric.hitMin).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(revealed ? "Hide email" : "Show email"))
        }
        .onChange(of: email) { _, _ in revealed = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
        .onChange(of: env.session.state) { _, state in if state != .unlocked { revealed = false } }
        .onDisappear { revealed = false }
    }
}
