import SwiftUI

/// Navigation route that pushes the Profile screen (kept distinct from the `String`
/// item-detail route). Codable so it survives `homePath` state restoration.
struct ProfileRoute: Hashable, Codable {}

/// Profile hub — avatar + name + email at the top, then grouped nav rows that open detail
/// screens (Personal Information, Payment, Loox, Family), an inline Devices list
/// (`ProfileDevicesCard`), and a bottom button to switch the active profile (persona). Pushed
/// onto the Home stack; every row's data mirrors the vault and scopes to the ACTIVE persona
/// (INV-R03).
struct ProfileScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showSwitcher = false

    private var persona: Persona? { env.repository.activePersona }
    private var identity: VaultItem? { env.repository.activeProfileItem }

    /// Name under the avatar: the identity's Full Name when set, else the persona name.
    private var displayName: String {
        if let full = identity?.fields.first(where: { $0.label == "Full Name" })?.value, !full.isEmpty {
            return full
        }
        return persona?.displayName ?? appString("Profile")
    }

    /// Email under the avatar — the active persona's identity email (nil under strict anonymity).
    private var displayEmail: String? {
        persona.flatMap { env.repository.identityUsername(forPersona: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                header

                // Section 1 — "system" rows: white SF Symbol glyph on a neutral gray tile,
                // matching the iOS Settings app's own icon rows (owner-approved SF Symbol
                // exception, Profile-only, 260715).
                ProfileGroupCard {
                    ProfileNavRow(title: "Personal Information", tile: .system("person.text.rectangle.fill")) { PersonalInformationScreen() }
                    ProfileRowDivider()
                    ProfileNavRow(title: "Payment", tile: .system("creditcard.fill")) { PaymentCardsScreen() }
                }

                // Section 2 — "badge" rows: colored/brand art on a white tile + hairline border.
                ProfileGroupCard {
                    ProfileNavRow(title: "Loox", tile: .brandMark) { LooxHubScreen() }
                    ProfileRowDivider()
                    // "fa_users" — FontAwesome6 Duotone "users" glyph (imported into
                    // Assets.xcassets mirroring the DeviceIcons import, see DeviceIcons.swift),
                    // tinted green on the section-2 white tile (260715 owner request).
                    ProfileNavRow(title: "Family", tile: .colored(.templateAsset("fa_users"), ProfileBadgeTint.family)) { FamilyScreen() }
                }

                // Devices — the list itself lives inline here now (previously a nav row that
                // pushed `DevicesScreen`); see `ProfileDevicesCard`.
                ProfileDevicesCard()

                switchButton
            }
            .padding(Space.gutter)
            .padding(.bottom, Space.s8)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Profile")
        .platformNavigationBarTitleDisplayMode(.inline)
        // Switch profile — the persona picker (dismisses itself on select).
        .sheet(isPresented: $showSwitcher) {
            NavigationStack { PersonaSwitcherScreen() }
        }
    }

    // MARK: Header (avatar + name + email)

    @ViewBuilder private var header: some View {
        VStack(spacing: Space.s3) {
            if let identity {
                ProfileAvatarView(identity: identity, size: 88)
            } else {
                LooxDotsAvatar(size: 88)
            }
            VStack(spacing: 2) {
                Text(verbatim: displayName)
                    .vaultType(.screenTitle)
                    .themedForeground()
                    .lineLimit(1)
                if let displayEmail, !displayEmail.isEmpty {
                    Text(verbatim: displayEmail)
                        .vaultType(.subhead)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s2)
    }

    // MARK: Bottom — switch profile

    private var switchButton: some View {
        Button { showSwitcher = true } label: {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.orderRepeat, size: Metric.iconInline)
                Text("Switch profile")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
        .padding(.top, Space.s2)
    }
}
