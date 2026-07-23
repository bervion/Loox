import SwiftUI

/// Display bucket for a connected service's live state — the iCloud+-style
/// status dot vocabulary. Collapses `CapabilityAvailability` (mode, health,
/// breaker, connectivity, preference) into the four colors a glance can read.
enum CapabilityDisplayStatus {
    /// Service reachable and accepting work — green.
    case active
    /// Temporarily limited but not broken (device offline, operator
    /// maintenance/degraded) — orange.
    case attention
    /// Runtime outage: infra failures tripped the breaker or the last calls
    /// died at the edge (e.g. the worker or Cloudflare is down) — red.
    case outage
    /// Not running by decision: user preference off or operator
    /// disabled/retired — gray.
    case off

    /// Resolve one capability's dot from the store. `.create` is the probe
    /// operation: it is the first thing every service surface gates, so its
    /// availability is what the user will actually experience.
    static func resolve(_ id: CapabilityID, store: CapabilityStore) -> CapabilityDisplayStatus {
        switch store.availability(id, operation: .create) {
        case .available: return .active
        case .offline, .maintenance: return .attention
        case .temporarilyUnavailable: return .outage
        case .disabledByOperator, .disabledByUser, .retired: return .off
        case .unknown: return .active
        }
    }

    /// Accessibility description (the dot alone must never be the only carrier).
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .active: "Service available"
        case .attention: "Service limited"
        case .outage: "Service interrupted"
        case .off: "Service off"
        }
    }
}

/// Small solid status dot. Color comes from semantic theme roles so every
/// theme keeps contrast; size follows the iCloud+ tile dots.
struct CapabilityStatusDot: View {
    let status: CapabilityDisplayStatus
    var size: CGFloat = 8
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel(Text(status.accessibilityLabel))
    }

    private var color: Color {
        let theme = env.theme.active
        switch status {
        case .active: return theme.color(.success)
        case .attention: return theme.color(.warning)
        case .outage: return theme.color(.destructive)
        case .off: return theme.color(.iconDisabled)
        }
    }
}
