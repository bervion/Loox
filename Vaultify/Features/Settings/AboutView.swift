import SwiftUI

/// About — editorial storytelling page: question hook → "why we built Loox"
/// ink block → three numbered promises → how your data is protected → privacy
/// & contact. One continuous scroll, pushed from Settings.
///
/// The origin-timeline and team sections from the design are intentionally not
/// shipped: their names/dates are placeholder data.
struct AboutView: View {
    @Environment(AppEnvironment.self) private var env

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                hero
                refusalBlock
                promises
                signature
                protectionCard
                privacyCard
                footer
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.s4)
        }
        .themedFormBackground()
        .navigationTitle("About")
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero — question hook

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            BrandLogoMark(size: 22, shadowRadius: 0, shadowY: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("Your passwords guard everything.")
                    .vaultType(.largeTitle)
                    .themedForeground(.primary)
                Text("Who guards them?")
                    .vaultType(.largeTitle)
                    .themedForeground(.accent)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Every account you own, your money, your photos, your conversations, hangs on a handful of passwords. We think the thing that holds them should answer to you, and no one else.")
                .vaultType(.body)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Refusal block — deliberate ink card

    /// Fixed dark "ink block" — an editorial emphasis card that stays dark in
    /// both light and dark themes (its own surface, like the decorative
    /// quick-action tints), with fixed light foregrounds chosen for it.
    private var refusalBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Why we built Loox")
                .vaultType(.sectionLabel)
                .foregroundStyle(AboutInk.highlight)
            Text("We didn't invent a new need. We took one of the oldest needs on the internet, keeping secrets, and made it 10× better.")
                .vaultType(.headline)
                .foregroundStyle(AboutInk.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("No accounts to create. No servers holding your vault. No subscription holding your data hostage. Just your iPhone, your keys, your secrets.")
                .vaultType(.subhead)
                .foregroundStyle(AboutInk.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AboutInk.surface)
        .vaultCornerRadius(Radius.lg)
    }

    // MARK: Three promises

    private var promises: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Our three promises")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.leading, Space.s1)

            promiseCard(number: 1, tint: env.theme.active.color(.accent),
                        title: "Your device is the vault",
                        body: "Everything is sealed with AES-256 before it touches storage. If it ever leaves your iPhone, to iCloud, to another device, it leaves already locked. We couldn't read it if we wanted to. Nobody can.")
            promiseCard(number: 2, tint: QuickActionCard.tealTint,
                        title: "Trust is verified, never assumed",
                        body: "Share a password, pair a device, open on a computer. Every handover makes both sides compare a code before anything moves. A little ceremony, on purpose. Secrets deserve it.")
            promiseCard(number: 3, tint: QuickActionCard.purpleTint,
                        title: "You can always walk away",
                        body: "Export everything, anytime, in formats other apps read. Your Emergency Kit recovers your vault without us. A lock that only locks in is a cage. Loox is a door, and you hold the key.")
        }
    }

    private func promiseCard(number: Int, tint: Color,
                             title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(verbatim: "\(number)")
                // Dynamic-Type-scalable large-title text style (still rounded/heavy for the
                // decorative numeral look) instead of a fixed pixel size, so it keeps pace
                // with the surrounding vaultType body copy at accessibility sizes.
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.heavy)
                .foregroundStyle(tint.opacity(0.35))
            Text(title)
                .vaultType(.headline)
                .themedForeground(.primary)
            Text(body)
                .vaultType(.subhead)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: Radius.lg, padding: 0)
    }

    // MARK: Signature

    private var signature: some View {
        VStack(spacing: Space.s2) {
            Text("Made by a small team that got tired of trusting strangers with their secrets.")
                .vaultType(.subhead)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            BrandLogoMark(size: 22, shadowRadius: 0, shadowY: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }

    // MARK: How your data is protected

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("How your data is protected")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.leading, Space.s1)
            VStack(alignment: .leading, spacing: Space.s4) {
                aboutRow(Icons.key, "Argon2id key derivation",
                         "Your master password is stretched with a memory-hard function (64 MiB, t=3).")
                aboutRow(Icons.lockFill, "AES-256-GCM encryption",
                         "Every item is sealed individually before it touches storage.")
                aboutRow(Icons.person, "Secure Enclave biometrics",
                         "The Vault Key is released only after Face ID / Touch ID.")
                aboutRow(Icons.globe, "Zero backend",
                         "Nothing is sent to a server. Your vault never leaves the device unencrypted.")
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(cornerRadius: Radius.lg, padding: 0)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Privacy")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.leading, Space.s1)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Loox collects no analytics and has no accounts. The only network request is the optional, anonymised breach check.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                Text("Includes the Argon2 reference implementation (CC0 / Apache-2.0).")
                    .vaultType(.caption)
                    .themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(cornerRadius: Radius.lg, padding: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s2) {
            Text("We answer every email ourselves.")
                .vaultType(.footnote)
                .themedForeground(.secondary)
            Text(verbatim: EmergencyKitInfo.defaultSupportContact)
                .vaultType(.subhead)
                .fontWeight(.semibold)
                .themedForeground(.accentText)
                .textSelection(.enabled)
            Text("Version \(version) (\(build))")
                .vaultType(.caption)
                .themedForeground(.tertiary)
                .padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }

    private func aboutRow(_ icon: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            PolarisIcon(icon, size: 22).foregroundStyle(Color.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).vaultType(.subhead).fontWeight(.medium).themedForeground(.primary)
                Text(detail).vaultType(.caption).themedForeground(.secondary)
            }
        }
    }
}

/// Fixed palette for the About page's dark ink block (deliberately identical
/// in light and dark themes — it is its own surface, not a themed one).
private enum AboutInk {
    static let surface = Color(rgb: 0x17181C)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let highlight = Color(rgb: 0x20BDFD)
}
