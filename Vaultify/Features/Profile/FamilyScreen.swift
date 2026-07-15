import SwiftUI

/// Family — the family-group feature (invite members, share vault items to the group). The
/// full model needs its own design + security pass (plan `260715-1630-profile-refactor`
/// phase 05), so this interim screen states intent without shipping unreviewed sharing.
struct FamilyScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                ZStack {
                    Circle().fill(Color(rgb: env.theme.active.accentSoft)).frame(width: 92, height: 92)
                    PolarisIcon(Icons.organization, size: 40).themedForeground(.accent)
                }
                VStack(spacing: Space.s2) {
                    Text("Family sharing").vaultType(.headline).themedForeground()
                    Text("Invite people to share vault items with your family. This is coming soon.")
                        .vaultType(.callout).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s10)
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Family")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
