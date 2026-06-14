import Foundation

/// When to switch from the primary theme to the night theme. Mirrors Telegram's
/// `AutomaticThemeSwitchTrigger`.
nonisolated enum AutoNightSetting: Codable, Sendable, Equatable {
    case off
    case system                                       // follow device dark mode
    case time(fromMinutes: Int, toMinutes: Int)       // minutes since midnight
    case brightness(threshold: Double)                // device brightness 0…1
}

nonisolated enum AutoNight {
    /// Whether the *night* theme should be active right now. `off` returns nil —
    /// the caller then uses the primary theme's own appearance.
    static func prefersNight(
        _ setting: AutoNightSetting,
        systemIsDark: Bool,
        now: Date = Date(),
        brightness: Double
    ) -> Bool? {
        switch setting {
        case .off: return nil
        case .system: return systemIsDark
        case .time(let from, let to): return inWindow(now: now, fromMinutes: from, toMinutes: to)
        case .brightness(let threshold): return brightness < threshold
        }
    }

    /// True if `now`'s minute-of-day is within [from, to). Window may cross midnight.
    static func inWindow(now: Date, fromMinutes: Int, toMinutes: Int) -> Bool {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if fromMinutes <= toMinutes {
            return mins >= fromMinutes && mins < toMinutes
        }
        return mins >= fromMinutes || mins < toMinutes
    }
}
