import SwiftUI

/// One overview row: every finding of one rule, bucketed for display.
/// Built from live findings (post-run) or saved digests (cold open) so the
/// overview renders identically in both cases.
nonisolated struct AuditGroupRow: Identifiable, Sendable {
    enum Bucket: Int, Comparable, Sendable {
        case actNow, improve, maintain
        static func < (l: Bucket, r: Bucket) -> Bool { l.rawValue < r.rawValue }
    }

    let ruleID: String
    let bucket: Bucket
    let findingCount: Int
    let itemIDs: [String]
    var id: String { ruleID }

    static func bucket(for severity: AuditSeverity) -> Bucket {
        switch severity {
        case .critical, .high: return .actNow
        case .medium: return .improve
        case .low, .info: return .maintain
        }
    }

    /// Group by rule, hide user-dismissed fingerprints, bucket by worst severity.
    static func rows(ruleSeverityItems: [(ruleID: String, severity: AuditSeverity,
                                          fingerprint: String, itemIDs: [String])],
                     dismissedFingerprints: Set<String>) -> [AuditGroupRow] {
        var byRule: [String: (severity: AuditSeverity, count: Int, items: [String])] = [:]
        for f in ruleSeverityItems where !dismissedFingerprints.contains(f.fingerprint) {
            var entry = byRule[f.ruleID] ?? (.info, 0, [])
            entry.severity = max(entry.severity, f.severity)
            entry.count += 1
            entry.items += f.itemIDs
            byRule[f.ruleID] = entry
        }
        return byRule.map { ruleID, entry in
            var seen: Set<String> = []
            let uniqueItems = entry.items.filter { seen.insert($0).inserted }
            return AuditGroupRow(ruleID: ruleID, bucket: bucket(for: entry.severity),
                                 findingCount: entry.count, itemIDs: uniqueItems)
        }
        .sorted { ($0.bucket.rawValue, $0.ruleID) < ($1.bucket.rawValue, $1.ruleID) }
    }
}

/// Buckets rows into the three overview sections.
nonisolated struct AuditGroupSections: Sendable {
    let actNow: [AuditGroupRow]
    let improve: [AuditGroupRow]
    let maintain: [AuditGroupRow]

    var isEmpty: Bool { actNow.isEmpty && improve.isEmpty && maintain.isEmpty }
    var actNowCount: Int { actNow.reduce(0) { $0 + $1.findingCount } }
    var improveCount: Int { improve.reduce(0) { $0 + $1.findingCount } }

    init(rows: [AuditGroupRow]) {
        actNow = rows.filter { $0.bucket == .actNow }.sorted { $0.itemIDs.count > $1.itemIDs.count }
        improve = rows.filter { $0.bucket == .improve }.sorted { $0.itemIDs.count > $1.itemIDs.count }
        maintain = rows.filter { $0.bucket == .maintain }.sorted { $0.itemIDs.count > $1.itemIDs.count }
    }

    static func from(report: AuditReport, dismissed: Set<String>) -> AuditGroupSections {
        AuditGroupSections(rows: AuditGroupRow.rows(
            ruleSeverityItems: report.findings.map {
                ($0.ruleID, $0.severity, $0.fingerprint, $0.affectedItemIDs)
            },
            dismissedFingerprints: dismissed))
    }

    static func from(payload: AuditReportPayload, dismissed: Set<String>) -> AuditGroupSections {
        AuditGroupSections(rows: AuditGroupRow.rows(
            ruleSeverityItems: payload.findings.map {
                ($0.ruleID, $0.severity, $0.fingerprint, $0.affectedItemIDs)
            },
            dismissedFingerprints: dismissed))
    }
}

// MARK: - Section view

/// One titled group of finding rows in the Security overview.
struct AuditGroupSectionView: View {
    @Environment(AppEnvironment.self) private var env
    let title: LocalizedStringResource
    let rows: [AuditGroupRow]
    let tintRole: ThemeRole

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s1)

            ThemedCard(cornerRadius: Radius.lg, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        NavigationLink(value: WatchtowerCategory.findingGroup(row.ruleID)) {
                            // No subtitle: the count badge already carries the
                            // number — a "3 items" line under it says it twice.
                            CategoryRow(icon: Self.icon(for: row.ruleID),
                                        tintRole: tintRole,
                                        title: AuditFindingCopy.title(ruleID: row.ruleID),
                                        subtitle: "",
                                        count: row.findingCount)
                        }
                        .buttonStyle(PressableSurfaceStyle(theme: env.theme.active))
                        if row.id != rows.last?.id {
                            ThemedDivider()
                                .padding(.leading, Space.gutter + Metric.iconTile + Space.s3)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
        }
    }

    static func icon(for ruleID: String) -> String {
        switch ruleID {
        case "exposure.leaked": return Icons.shieldAlert
        case "reuse.exact": return Icons.copy
        case let id where id.hasPrefix("quality"): return Icons.lock
        case let id where id.hasPrefix("auth"): return Icons.checkCircle
        case let id where id.hasPrefix("url"): return Icons.globe
        default: return Icons.organization
        }
    }
}
