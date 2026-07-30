import Foundation

/// Tone associated with a rotation state — drives color and iconography in the UI.
nonisolated enum RotationTone: Sendable {
    case neutral
    case warning
    case destructive
}

/// The computed rotation state of a single item's password.
/// Derived from `rotateDays`, `passwordChangedAt` / `createdAt`, and the current date.
nonisolated enum RotationState: Sendable, Equatable {
    case ok
    case overdue
    case soon
    case stale
}

/// The reason an item surfaced in the "needs attention" list.
nonisolated enum AttentionReason: Sendable, Equatable {
    case overdue
    case weak
    case soon
    case stale

    /// Severity language shared by every surface that shows this reason (the Home
    /// rows, that section's count badge, the item detail banner): a weak or overdue
    /// password is destructive, a cadence merely running out is a warning.
    var tone: RotationTone {
        switch self {
        case .overdue, .weak: return .destructive
        case .soon, .stale: return .warning
        }
    }
}

/// Pure, `nonisolated` value type carrying the derived rotation status and its
/// display resources. Logic is ported from the DS reference (app.jsx:42-57):
///
///   rotateDays > 0 → due = rotateDays - daysSinceChange
///     due ≤ 0     → overdue (destructive)
///     due ≤ 5     → soon    (warning)
///     otherwise   → ok
///   rotateDays = 0, daysSinceChange ≥ 180 → stale (warning)
///   otherwise → ok
nonisolated struct RotationStatus: Sendable {
    let state: RotationState
    let tone: RotationTone
    /// Full localized label (e.g. "Change overdue by 3 days").
    let label: LocalizedStringResource
    /// Short localized label for compact UI (e.g. "Overdue").
    let short: LocalizedStringResource

    // MARK: Factory

    /// Evaluate rotation status given item metadata and the current date.
    ///
    /// - Parameters:
    ///   - rotateDays: 0 = off; 15 / 30 / 90 = cadence.
    ///   - passwordChangedAt: explicit timestamp, or nil → use `createdAt`.
    ///   - createdAt: item creation date, used as fallback baseline.
    ///   - now: injection point for deterministic testing.
    static func evaluate(
        rotateDays: Int,
        passwordChangedAt: Date?,
        createdAt: Date,
        now: Date = .now
    ) -> RotationStatus {
        let baseline = passwordChangedAt ?? createdAt
        let daysSince = max(0, Int(now.timeIntervalSince(baseline) / 86_400))

        if rotateDays > 0 {
            let due = rotateDays - daysSince
            if due <= 0 {
                // Overdue: |due| days past deadline.
                let overdueDays = -due
                let label: LocalizedStringResource = "Change overdue by \(overdueDays) days"
                return RotationStatus(state: .overdue, tone: .destructive,
                                      label: label.inAppLocalized,
                                      short: overdueLabelShort)
            }
            if due <= 5 {
                // Due soon.
                let label: LocalizedStringResource = "Change in \(due) days"
                let short: LocalizedStringResource = "\(due) days"
                return RotationStatus(state: .soon, tone: .warning,
                                      label: label.inAppLocalized,
                                      short: short.inAppLocalized)
            }
            // Within cadence — ok.
            let label: LocalizedStringResource = "Change in \(due) days"
            return RotationStatus(state: .ok, tone: .neutral,
                                  label: label.inAppLocalized, short: okLabelShort)
        }

        // No cadence: surface stale if password unchanged for ≥ 180 days.
        if daysSince >= 180 {
            let months = max(1, Int(round(Double(daysSince) / 30.0)))
            let label: LocalizedStringResource = "\(months) months since last change"
            return RotationStatus(state: .stale, tone: .warning,
                                  label: label.inAppLocalized,
                                  short: staleLabelShort)
        }

        return RotationStatus(state: .ok, tone: .neutral,
                              label: okLabelFull, short: okLabelShort)
    }

    // MARK: Attention reason

    /// Reason this item should appear in the "Needs attention" list.
    /// Returns nil when both rotation and password strength are acceptable.
    ///
    /// - Parameters:
    ///   - status: pre-computed `RotationStatus` for this item.
    ///   - isWeak: true when the item's password strength score is weak (score ≤ 1
    ///             per `PasswordStrength.evaluate`, i.e. `.weak`).
    static func attentionReason(status: RotationStatus, isWeak: Bool) -> AttentionReason? {
        switch status.state {
        case .overdue: return .overdue
        case .soon:    return .soon
        case .stale:   return .stale
        case .ok:      return isWeak ? .weak : nil
        }
    }
}

// MARK: - Shared label constants (avoid repeated allocations)

private nonisolated let okLabelFull: LocalizedStringResource  = LocalizedStringResource("Healthy").inAppLocalized
private nonisolated let okLabelShort: LocalizedStringResource = LocalizedStringResource("Good").inAppLocalized
private nonisolated let staleLabelShort: LocalizedStringResource = LocalizedStringResource("Stale").inAppLocalized
private nonisolated let overdueLabelShort: LocalizedStringResource = LocalizedStringResource("Overdue").inAppLocalized
