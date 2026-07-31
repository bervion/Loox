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
    @Environment(AppEnvironment.self) private var env

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
    /// Called after a warning is silenced, so the caller re-reads its audit findings
    /// (an ignored fingerprint drops out of the next load).
    let onIgnored: () -> Void

    var body: some View {
        if let top = warnings.first {
            VaultExpandableBanner(
                top.variant,
                icon: top.icon,
                title: top.title,
                count: warnings.count,
                actionLabel: actionLabel(for: top),
                action: action(for: top),
                secondaryLabel: LocalizedStringResource("Ignore").inAppLocalized,
                secondaryAction: { ignore(top) },
                detail: { detailStack }
            )
        }
    }

    /// One line per warning. The LEAD warning's title is already the banner
    /// header, so its sentence renders alone — repeating it directly under the
    /// header read as a doubled title. Only the trailing warnings, whose titles
    /// appear nowhere else, carry theirs.
    private var detailStack: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(warnings) { warning in
                VStack(alignment: .leading, spacing: 2) {
                    if warning.id != warnings.first?.id {
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
        /// Where the warning came from — decides where Ignore records the decision.
        let source: Source
    }

    private enum Fix { case password, verificationCode, details, none }

    private enum Source {
        /// Live signal: silenced device-locally, keyed to the password it was about.
        case live(kind: String)
        /// Audit finding: silenced as a real `FindingStatus.ignored`, so Watchtower
        /// stops listing it too.
        case audit(QueuedFinding)
    }

    /// Rule IDs the item detail speaks for. Everything else the audit finds
    /// (URL hygiene, duplicates, staleness) belongs to Watchtower's report, not on
    /// top of the fields the user came here to use. `quality.weak` is deliberately
    /// absent: the live weak-password warning below says the same thing without
    /// needing an audit to have run. Missing details IS here: the Watchtower
    /// group lands the user on this screen, which must then name the gap.
    private static let surfacedRuleIDs: Set<String> = [
        "exposure.leaked", "reuse.exact", "auth.totp-missing",
        "maintenance.missing-metadata",
    ]

    // MARK: Missing-details gaps (live mirrors of `MissingMetadataRule`)

    /// No URL field carries a value — same read as the rule's `rawURLs` check,
    /// recomputed live so filling the field clears the warning immediately.
    private var missingURL: Bool {
        item.fields.filter { $0.kind == .url }.allSatisfy(\.isEmpty)
    }

    private var missingUsername: Bool {
        item.fields.filter { $0.kind == .username || $0.kind == .email }.allSatisfy(\.isEmpty)
    }

    /// Names the CURRENT gap, not the audited one — the finding only says
    /// "details missing", and stating which field is what makes it actionable.
    private var missingDetailsTitle: LocalizedStringResource {
        let base: LocalizedStringResource = if missingURL && missingUsername {
            "Website and username not saved"
        } else if missingURL {
            "Website not saved"
        } else {
            "Username not saved"
        }
        return base.inAppLocalized
    }

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
        let warning: Warning = switch reason {
        case .weak:
            Warning(
                id: "weak", rank: 1, variant: .error, icon: Icons.alert,
                title: LocalizedStringResource("Weak password").inAppLocalized,
                detail: LocalizedStringResource("This password is easy to guess. Generate a stronger one.").inAppLocalized,
                fix: .password, source: .live(kind: "weak"))
        case .overdue:
            Warning(
                id: "overdue", rank: 3, variant: .error, icon: Icons.clock,
                title: LocalizedStringResource("Password change overdue").inAppLocalized,
                detail: rotationStatus.label, fix: .password, source: .live(kind: "overdue"))
        case .soon:
            Warning(
                id: "soon", rank: 4, variant: .warning, icon: Icons.clock,
                title: LocalizedStringResource("Password change due soon").inAppLocalized,
                detail: rotationStatus.label, fix: .password, source: .live(kind: "soon"))
        case .stale:
            Warning(
                id: "stale", rank: 4, variant: .warning, icon: Icons.clock,
                title: LocalizedStringResource("Password unchanged for a long time").inAppLocalized,
                detail: rotationStatus.label, fix: .password, source: .live(kind: "stale"))
        }
        return env.settings.isItemWarningDismissed(dismissKey(warning.id)) ? [] : [warning]
    }

    /// Dismissal identity for a live warning: the item, the kind, and the password
    /// baseline the warning was about. A later password produces a different key, so
    /// silencing one weak password never silences the next one.
    private func dismissKey(_ kind: String) -> String {
        let baseline = Int((item.passwordChangedAt ?? item.createdAt).timeIntervalSince1970)
        return "\(item.id)|\(kind)|\(baseline)"
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
        case "maintenance.missing-metadata":
            // The verdict is about gaps in the SAVED fields: recompute from the
            // live item, so filling in the website or username clears it here
            // without waiting for the next audit.
            return item.category == .login
                && item.passwordField?.value.isEmpty == false
                && (missingURL || missingUsername)
        default:
            return true
        }
    }

    private func warning(for finding: QueuedFinding) -> Warning {
        let fix: Fix = switch finding.ruleID {
        case "auth.totp-missing": .verificationCode
        case "maintenance.missing-metadata": .details
        default: .password
        }
        return Warning(
            id: finding.fingerprint,
            rank: rank(for: finding),
            variant: variant(for: finding),
            icon: icon(for: finding.ruleID),
            title: finding.ruleID == "maintenance.missing-metadata"
                ? missingDetailsTitle
                : AuditFindingCopy.itemTitle(ruleID: finding.ruleID),
            detail: AuditFindingCopy.explanation(ruleID: finding.ruleID),
            fix: fix,
            source: .audit(finding))
    }

    /// Interleaved with the live warnings' ranks: leak first, then a weak password,
    /// then reuse, then the rotation states, and the 2FA opportunity last (it is an
    /// improvement, not a problem with what is saved).
    private func rank(for finding: QueuedFinding) -> Int {
        switch finding.ruleID {
        case "exposure.leaked": return 0
        case "reuse.exact": return 2
        case "auth.totp-missing": return 5
        // Hygiene, not danger: always after the security warnings.
        case "maintenance.missing-metadata": return 6
        default: return 7
        }
    }

    private func variant(for finding: QueuedFinding) -> VaultInfoBanner.Variant {
        switch finding.ruleID {
        case "exposure.leaked": return .error
        case "reuse.exact": return finding.severity >= .high ? .error : .warning
        // An available verification code is an opportunity, not a fault: info
        // tone — and missing details degrade AutoFill, not security.
        case "auth.totp-missing", "maintenance.missing-metadata": return .info
        default: return .warning
        }
    }

    private func icon(for ruleID: String) -> String {
        switch ruleID {
        case "exposure.leaked": return Icons.alert
        case "reuse.exact": return Icons.orderRepeat
        case "auth.totp-missing": return Icons.clock
        case "maintenance.missing-metadata": return Icons.info
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
        case .details:
            return LocalizedStringResource("Add the missing details").inAppLocalized
        case .none:
            return nil
        }
    }

    private func action(for warning: Warning) -> (() -> Void)? {
        switch warning.fix {
        case .password: return onUpdatePassword
        case .verificationCode, .details: return onEditItem
        case .none: return nil
        }
    }

    // MARK: Ignore

    /// Silence the warning the banner currently leads with. Ignoring the top one
    /// reveals the next, so a credential with several problems is answered one
    /// decision at a time rather than all of them by one tap.
    private func ignore(_ warning: Warning) {
        switch warning.source {
        case .live(let kind):
            env.settings.dismissItemWarning(dismissKey(kind))
        case .audit(let finding):
            ignoreAuditFinding(finding)
        }
        Haptics.tap()
        onIgnored()
    }

    /// Records the decision where Watchtower already reads it, so an item ignored
    /// here stops being listed there too. Rule version comes from the report that
    /// produced the finding: a later rule version resurfaces it for a fresh look
    /// (`AuditReportStore.effectiveStatus`).
    private func ignoreAuditFinding(_ finding: QueuedFinding) {
        guard let key = env.session.vaultKey else { return }
        let record = AuditFinding(
            ruleID: finding.ruleID,
            ruleVersion: auditFindings.ruleVersions[finding.ruleID] ?? 1,
            severity: finding.severity, category: .quality,
            affectedItemIDs: finding.itemIDs, fingerprint: finding.fingerprint,
            titleKey: "", detail: nil, remediation: .reviewItem,
            estimatedFixSeconds: 0, detectedAt: .now)
        try? AuditReportStore(store: env.store)
            .setState(.ignored, reason: "ignored", for: record,
                      personaID: env.repository.activePersona?.id, key: key)
    }
}
