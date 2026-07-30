import SwiftUI

/// The item detail screen's warning banner: ONE expandable notice carrying every
/// open warning about this item, most severe first, with the fix for the top one.
///
/// Two sources, deliberately:
/// - **Live, always fresh** — weak password and rotation cadence, from the same
///   `RotationStatus` engine as Home's "Needs Attention" section, so an item listed
///   there always explains itself here in the same words.
/// - **Last saved audit** — the findings only Watchtower can know: a password found
///   in a known leak (needs the network, so it can only come from a completed
///   audit), the same password reused on other items, and a site that supports
///   verification codes with no code saved. Dismissed findings stay dismissed
///   (`ItemAuditFindings`), and a verdict the user has already acted on since the
///   audit ran is dropped here rather than re-stated.
///
/// One banner, not a stack: three tinted cards with three text buttons is the button
/// wall DNA rule 7 forbids. The severity of the top warning colors the banner; the
/// rest are listed inside.
struct ItemAttentionBanner: View {
    let item: VaultItem
    /// Findings from the last audit that name this item (already filtered to the
    /// user's open decisions). Empty when no audit has run — the live warnings below
    /// still work, since they need no audit.
    var auditFindings: ItemAuditFindings = .none
    /// Opens the editor with the password generator. Nil when this screen has no
    /// password it may replace (no password field, or one sealed behind Extra
    /// Protection) — a warning then states the problem without a dead-end action.
    let onUpdatePassword: (() -> Void)?
    /// Opens the plain editor, where a verification code is added as a field.
    let onEditItem: () -> Void

    var body: some View {
        if let top = warnings.first {
            VaultExpandableBanner(
                top.variant,
                icon: top.icon,
                title: top.title,
                count: warnings.count,
                actionLabel: actionLabel(for: top),
                action: action(for: top),
                detail: { detailStack }
            )
        }
    }

    /// One line per warning. A single warning needs no title repeated from the
    /// banner header, so it renders as the sentence alone.
    private var detailStack: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(warnings) { warning in
                VStack(alignment: .leading, spacing: 2) {
                    if warnings.count > 1 {
                        Text(warning.title).fontWeight(.semibold)
                    }
                    Text(warning.detail)
                }
            }
        }
    }

    // MARK: Warning model

    /// A single thing wrong with this item, ranked so the banner always leads with
    /// the same one for the same state (`rank`, lower = more urgent).
    private struct Warning: Identifiable {
        let id: String
        let rank: Int
        let variant: VaultInfoBanner.Variant
        let icon: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        let fix: Fix
    }

    private enum Fix { case password, verificationCode, none }

    /// Rule IDs the item detail speaks for. Everything else the audit finds
    /// (URL hygiene, duplicates, staleness) belongs to Watchtower's report, not on
    /// top of the fields the user came here to use. `quality.weak` is deliberately
    /// absent: the live weak-password warning below says the same thing without
    /// needing an audit to have run.
    private static let surfacedRuleIDs: Set<String> = [
        "exposure.leaked", "reuse.exact", "auth.totp-missing",
    ]

    private var warnings: [Warning] {
        (localWarnings + auditWarnings).sorted { $0.rank < $1.rank }
    }

    // MARK: Live warnings (no audit required)

    private var rotationStatus: RotationStatus {
        RotationStatus.evaluate(
            rotateDays: item.rotateDays,
            passwordChangedAt: item.passwordChangedAt,
            createdAt: item.createdAt)
    }

    private var localWarnings: [Warning] {
        guard let reason = RotationStatus.attentionReason(status: rotationStatus,
                                                          isWeak: item.hasWeakPassword)
        else { return [] }
        switch reason {
        case .weak:
            return [Warning(
                id: "weak", rank: 1, variant: .error, icon: Icons.alert,
                title: LocalizedStringResource("Weak password").inAppLocalized,
                detail: LocalizedStringResource("This password is easy to guess. Generate a stronger one.").inAppLocalized,
                fix: .password)]
        case .overdue:
            return [Warning(
                id: "overdue", rank: 3, variant: .error, icon: Icons.clock,
                title: LocalizedStringResource("Password change overdue").inAppLocalized,
                detail: rotationStatus.label, fix: .password)]
        case .soon:
            return [Warning(
                id: "soon", rank: 4, variant: .warning, icon: Icons.clock,
                title: LocalizedStringResource("Password change due soon").inAppLocalized,
                detail: rotationStatus.label, fix: .password)]
        case .stale:
            return [Warning(
                id: "stale", rank: 4, variant: .warning, icon: Icons.clock,
                title: LocalizedStringResource("Password unchanged for a long time").inAppLocalized,
                detail: rotationStatus.label, fix: .password)]
        }
    }

    // MARK: Audit-derived warnings

    private var auditWarnings: [Warning] {
        auditFindings.findings
            .filter { Self.surfacedRuleIDs.contains($0.ruleID) }
            .filter(isStillTrue)
            .map(warning(for:))
    }

    /// Drop a verdict the item has moved past since the audit completed. The audit
    /// is a snapshot; re-stating a fixed problem is worse than staying quiet.
    private func isStillTrue(_ finding: QueuedFinding) -> Bool {
        switch finding.ruleID {
        case "auth.totp-missing":
            // A code added since the audit answers this one.
            return item.totpField == nil
        case "exposure.leaked", "reuse.exact":
            // Both verdicts are about the password VALUE: a password changed after
            // the audit ran was never the one that was checked.
            guard let password = item.passwordField?.value, !password.isEmpty else { return false }
            return (item.passwordChangedAt ?? item.createdAt) <= auditFindings.completedAt
        default:
            return true
        }
    }

    private func warning(for finding: QueuedFinding) -> Warning {
        Warning(
            id: finding.fingerprint,
            rank: rank(for: finding),
            variant: variant(for: finding),
            icon: icon(for: finding.ruleID),
            title: AuditFindingCopy.itemTitle(ruleID: finding.ruleID),
            detail: AuditFindingCopy.explanation(ruleID: finding.ruleID),
            fix: finding.ruleID == "auth.totp-missing" ? .verificationCode : .password)
    }

    /// Interleaved with the live warnings' ranks: leak first, then a weak password,
    /// then reuse, then the rotation states, and the 2FA opportunity last (it is an
    /// improvement, not a problem with what is saved).
    private func rank(for finding: QueuedFinding) -> Int {
        switch finding.ruleID {
        case "exposure.leaked": return 0
        case "reuse.exact": return 2
        case "auth.totp-missing": return 5
        default: return 6
        }
    }

    private func variant(for finding: QueuedFinding) -> VaultInfoBanner.Variant {
        switch finding.ruleID {
        case "exposure.leaked": return .error
        case "reuse.exact": return finding.severity >= .high ? .error : .warning
        // An available verification code is an opportunity, not a fault: info tone.
        case "auth.totp-missing": return .info
        default: return .warning
        }
    }

    private func icon(for ruleID: String) -> String {
        switch ruleID {
        case "exposure.leaked": return Icons.alert
        case "reuse.exact": return Icons.orderRepeat
        case "auth.totp-missing": return Icons.clock
        default: return Icons.alert
        }
    }

    // MARK: Action

    private func actionLabel(for warning: Warning) -> LocalizedStringResource? {
        switch warning.fix {
        case .password:
            return onUpdatePassword == nil
                ? nil
                : LocalizedStringResource("Update password").inAppLocalized
        case .verificationCode:
            return LocalizedStringResource("Add a verification code").inAppLocalized
        case .none:
            return nil
        }
    }

    private func action(for warning: Warning) -> (() -> Void)? {
        switch warning.fix {
        case .password: return onUpdatePassword
        case .verificationCode: return onEditItem
        case .none: return nil
        }
    }
}
