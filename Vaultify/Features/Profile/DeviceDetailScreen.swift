import SwiftUI

/// Detail for one registry device (pushed from Profile › Devices): the device art as a
/// hero, read-only facts, and — for OTHER devices — the red "Log Out Device" action
/// (Telegram/WhatsApp anatomy: facts stacked, exactly one destructive action at the
/// bottom, consequence stated in the confirm dialog). The sign-out is cooperative and
/// takes effect when the target comes online — the copy says so honestly.
struct DeviceDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let device: VaultDevice

    @State private var confirmLogOut = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                hero
                infoCard
                if device.isCurrent {
                    Text("This is the device you are using.")
                        .vaultType(.footnote).themedForeground(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s2)
                } else {
                    logOutSection
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle(Text(verbatim: title))
        .platformNavigationBarTitleDisplayMode(.inline)
        .analyticsScreen("device_detail")
        .confirmationDialog("Log out this device?", isPresented: $confirmLogOut,
                            titleVisibility: .visible) {
            Button("Log Out Device", role: .destructive) { Task { await logOut() } }
        } message: {
            Text("The device signs out and removes its local Loox data the next time it comes online. Your vault items are not affected.")
        }
    }

    private var title: String { device.model.isEmpty ? device.name : device.model }

    private var hero: some View {
        VStack(spacing: Space.s3) {
            VaultIcon(DeviceIconMapping.icon(forModel: device.model), size: 72)
                .foregroundStyle(Color(rgb: RGBMath.ensureContrast(
                    ProfileBadgeTint.deviceHex, on: env.theme.active.groupedBackground, floor: 3.0)))
            Text(verbatim: title)
                .vaultType(.screenTitle).themedForeground()
                .multilineTextAlignment(.center)
            if device.isCurrent {
                Text("This device")
                    .vaultType(.caption)
                    .themedForeground(.success)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(env.theme.active.color(.success).opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s4)
    }

    private var infoCard: some View {
        ProfileGroupCard {
            infoRow(label: "Model", value: device.model.isEmpty ? device.name : device.model)
            ProfileRowDivider()
            infoRow(label: "App Version", value: device.appVersion.isEmpty
                ? appString("Unknown") : "Loox \(device.appVersion)")
            ProfileRowDivider()
            infoRow(label: "Last seen", value: lastSeenText)
        }
    }

    private func infoRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(label).vaultType(.body).themedForeground()
            Spacer(minLength: Space.s2)
            Text(verbatim: value)
                .vaultType(.body).themedForeground(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
    }

    private var lastSeenText: String {
        if device.isCurrent { return appString("Now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appResourceLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: device.lastSeenAt, relativeTo: .now)
    }

    private var logOutSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ProfileGroupCard {
                Button {
                    confirmLogOut = true
                } label: {
                    HStack {
                        if busy { ProgressView().controlSize(.small) }
                        Text("Log Out Device")
                            .vaultType(.body)
                            .foregroundStyle(env.theme.active.color(.destructive))
                    }
                    .frame(maxWidth: .infinity, minHeight: Metric.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            if let error {
                Text(verbatim: error)
                    .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                    .padding(.horizontal, Space.s2)
            }
            Text("The sign-out completes when the device is online. A device that stays offline keeps its local copy, still protected by your Loox Password.")
                .vaultType(.footnote).themedForeground(.tertiary)
                .padding(.horizontal, Space.s2)
        }
    }

    private func logOut() async {
        busy = true; error = nil
        do {
            let registry = DeviceRegistryService(settings: env.settings)
            try await registry.logOut(deviceID: device.id)
            Haptics.warning()
            NotificationCenter.default.post(name: .vaultDevicesChanged, object: nil)
            dismiss()
        } catch let failure as DeviceRegistryService.Failure {
            // A refusal the registry made deliberately — say what it was, rather
            // than blaming the network for a decision the app took.
            self.error = failure.errorDescription
            Haptics.error()
        } catch {
            self.error = appString("Couldn’t log out the device. Check your connection and try again.")
            Haptics.error()
        }
        busy = false
    }
}

extension Notification.Name {
    /// Posted after a successful device sign-out so the Profile Devices card reloads.
    static let vaultDevicesChanged = Notification.Name("vaultDevicesChanged")
}
