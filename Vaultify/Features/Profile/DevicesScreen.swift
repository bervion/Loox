import SwiftUI

/// Devices — the devices this vault syncs to over iCloud. Lists every device that has
/// published a record (this device is always shown, even offline), newest-seen first. This
/// is the **list-only** v1: no revoke (removing a device's key access needs a key rotation —
/// see plan `260715-1630-profile-refactor` phase 06 / ADR-D).
///
/// As of the 260715 Profile redesign, the list itself renders inline on the Profile hub
/// (`ProfileDevicesCard`, sharing this screen's `DeviceRow`), so this standalone screen isn't
/// currently linked from Profile — kept as a ready destination for a future "manage devices"
/// action (e.g. once revoke ships) rather than deleted.
struct DevicesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devices: [VaultDevice] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ProfileGroupCard {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        DeviceRow(device: device)
                        if index < devices.count - 1 { ProfileRowDivider() }
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

    private func load() async {
        let service = DeviceRegistryService(settings: env.settings)
        // Show this device immediately (no network), then publish + refresh from CloudKit.
        if devices.isEmpty { devices = [service.thisDevice] }
        await service.publish()
        let fetched = await service.fetchDevices()
        if !fetched.isEmpty { devices = fetched }
    }
}
