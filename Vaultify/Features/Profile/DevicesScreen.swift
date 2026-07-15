import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Devices — the devices this vault syncs to. This interim version shows THIS device; the
/// full cross-device CloudKit registry (list every device + "Synced Xh ago" + revoke) is
/// plan `260715-1630-profile-refactor` phase 06 (needs an ADR + security pass first).
struct DevicesScreen: View {
    @Environment(AppEnvironment.self) private var env

    private var deviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        appString("This device")
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ProfileGroupCard {
                    HStack(spacing: Space.s3) {
                        ProfileRowTile(icon: Icons.device)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: deviceName).vaultType(.body).themedForeground().lineLimit(1)
                            Text("This device").vaultType(.subhead).themedForeground(.secondary)
                        }
                        Spacer(minLength: Space.s2)
                        activeBadge
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: Metric.rowHeight)
                }
                Text("Other devices you pair with this vault will appear here.")
                    .vaultType(.footnote).themedForeground(.tertiary)
                    .padding(.horizontal, Space.s2)
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Devices")
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    private var activeBadge: some View {
        Text("Active")
            .vaultType(.caption)
            .themedForeground(.success)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(env.theme.active.color(.success).opacity(0.14), in: Capsule())
    }
}
