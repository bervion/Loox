import CloudKit
import SwiftUI

/// Route value for the Home → Shared-with-me navigation.
nonisolated struct SharedWithMeRoute: Hashable {}

/// Full identity of an accepted shared zone. Shared-database zones are
/// namespaced by the SHARING OWNER's user record name — rebuilding a zone ID
/// from the bare zoneName defaults to `__defaultOwner__` and misses the zone
/// entirely on a real cross-account share. Owner name also disambiguates the
/// TOFU pin (two owners could otherwise collide on a zone name).
nonisolated struct SharedZoneRoute: Hashable {
    let zoneName: String
    let ownerName: String

    init(zoneID: CKRecordZone.ID) {
        zoneName = zoneID.zoneName
        ownerName = zoneID.ownerName
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }
}

/// Everything other people shared with this account (recipient side):
/// one row per accepted approval zone. Zones live in the shared CloudKit
/// database; nothing here touches the local vault store.
struct SharedWithMeScreen: View {
    @Environment(AppEnvironment.self) private var env

    private enum LoadState {
        case loading
        case ready([CKRecordZone.ID])
        case failed(String)
    }

    @State private var loadState: LoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let zones):
                if zones.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Nothing shared with you yet") } icon: {
                            PolarisIcon(Icons.shield, size: Metric.iconTileLarge)
                        }
                    } description: {
                        Text("When someone shares access with you, it appears here.")
                    }
                } else {
                    zoneList(zones)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label { Text("Couldn't load shares") } icon: {
                        PolarisIcon(Icons.alert, size: Metric.iconTileLarge)
                    }
                } description: {
                    Text(verbatim: message)
                }
            }
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Shared with Me")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task(id: env.approvalCoordinator.recipientChangeCounter) { await load() }
    }

    private func zoneList(_ zones: [CKRecordZone.ID]) -> some View {
        // Typed route (NOT String — the root stack already maps String to
        // ItemDetailScreen) carrying the FULL zone identity incl. ownerName.
        List(zones, id: \.self) { zoneID in
            NavigationLink(value: SharedZoneRoute(zoneID: zoneID)) {
                HStack(spacing: Space.s3) {
                    PolarisIcon(Icons.shield, size: Metric.iconInline).themedForeground(.accent)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Shared item").vaultType(.body).themedForeground()
                        Text(pinnedLabel(zoneID))
                            .vaultType(.footnote).themedForeground(.secondary)
                    }
                }
                .frame(minHeight: Metric.hitMin)
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationDestination(for: SharedZoneRoute.self) { route in
            SharedItemView(route: route)
        }
    }

    private func pinnedLabel(_ zoneID: CKRecordZone.ID) -> LocalizedStringKey {
        ApprovalRecipientService.pinnedOwnerKey(zoneID: zoneID) != nil
            ? "Verified" : "Needs verification"
    }

    private func load() async {
        do {
            let zones = try await env.approvalRecipient.acceptedApprovalZones()
            loadState = .ready(zones)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
