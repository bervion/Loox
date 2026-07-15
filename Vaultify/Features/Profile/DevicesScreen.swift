import SwiftUI

/// Devices — the devices this vault syncs to over iCloud. Lists every device that has
/// published a record (this device is always shown, even offline), newest-seen first. This
/// is the **list-only** v1: no revoke (removing a device's key access needs a key rotation —
/// see plan `260715-1630-profile-refactor` phase 06 / ADR-D).
struct DevicesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devices: [VaultDevice] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ProfileGroupCard {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        deviceRow(device)
                        if index < devices.count - 1 {
                            Rectangle()
                                .fill(Color(rgb: env.theme.active.separator))
                                .frame(height: 0.5)
                                .padding(.leading, Space.s4 + 30 + Space.s3)
                        }
                    }
                }
                if devices.count <= 1 {
                    Text("Other devices you pair with this vault will appear here.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .padding(.horizontal, Space.s2)
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Devices")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func deviceRow(_ device: VaultDevice) -> some View {
        HStack(spacing: Space.s3) {
            ProfileRowTile(icon: Icons.device)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.name).vaultType(.body).themedForeground().lineLimit(1)
                Text(verbatim: subtitle(device)).vaultType(.subhead).themedForeground(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if device.isCurrent { activeBadge }
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
    }

    private func subtitle(_ device: VaultDevice) -> String {
        if device.isCurrent { return appString("This device") }
        // Locale-aware relative time ("2 hours ago" / "2 giờ trước") — no catalog strings.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appResourceLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: device.lastSeenAt, relativeTo: .now)
    }

    private var activeBadge: some View {
        Text("Active")
            .vaultType(.caption)
            .themedForeground(.success)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(env.theme.active.color(.success).opacity(0.14), in: Capsule())
    }

    private func load() async {
        let service = DeviceRegistryService(settings: env.settings)
        // Show this device immediately (no network), then publish + refresh from CloudKit.
        if devices.isEmpty { devices = [service.thisDevice] }
        await service.publish()
        let fetched = await service.fetchDevices()
        if !fetched.isEmpty { devices = fetched }
    }
}
