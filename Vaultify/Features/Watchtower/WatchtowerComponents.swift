import SwiftUI

/// Circular vault-health gauge.
struct HealthGauge: View {
    let score: Int
    let issueCount: Int

    private var color: Color {
        score >= 80 ? VaultColors.strengthStrong : score >= 50 ? VaultColors.strengthMedium : VaultColors.strengthWeak
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: score)
                VStack(spacing: 0) {
                    Text("\(score)").font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Health").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            Text(issueCount == 0 ? "No issues found" : "^[\(issueCount) issue](inflect: true) to review")
                .font(.subheadline)
                .foregroundStyle(issueCount == 0 ? VaultColors.strengthStrong : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// A row representing a flagged item in a Watchtower section.
struct WatchtowerIssueRow: View {
    let issue: VaultIssue

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: issue.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.itemTitle).font(.body).lineLimit(1)
                if let detail = issue.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            PolarisIcon(Icons.chevronRight, size: 14).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}
