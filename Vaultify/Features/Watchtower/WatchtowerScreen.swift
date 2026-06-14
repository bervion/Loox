import SwiftUI

/// The Watchtower tab: offline weak/reused analysis plus optional HIBP breach
/// checking (k-anonymity). Tapping an issue opens the item.
struct WatchtowerScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var health = VaultHealth.empty
    @State private var pwned: [VaultIssue] = []
    @State private var checking = false

    private var allClear: Bool {
        health.analyzedCount > 0 && health.issueCount == 0 && pwned.isEmpty
    }

    private var hibpBinding: Binding<Bool> {
        Binding(
            get: { env.settings.hibpEnabled },
            set: { isOn in
                env.settings.hibpEnabled = isOn
                if isOn { Task { await runHIBP() } } else { pwned = [] }
            })
    }

    var body: some View {
        NavigationStack {
            List {
                Section { HealthGauge(score: health.score, issueCount: health.issueCount + pwned.count) }
                .listRowBackground(VaultColors.surface)

                issueSection("Weak Passwords", "Short or low-entropy — easy to crack.", health.weak)
                issueSection("Reused Passwords", "The same password protects multiple items.", health.reused)
                if env.settings.hibpEnabled {
                    issueSection("Found in Data Breaches", "Change these as soon as possible.", pwned)
                }

                if allClear {
                    Section {
                        Label { Text("Every password is strong and unique.") } icon: {
                            PolarisIcon(Icons.checkCircle).foregroundStyle(VaultColors.strengthStrong)
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }

                Section {
                    Toggle(isOn: hibpBinding) { Text("Check for known breaches") }
                } footer: {
                    Text("Uses k-anonymity — only the first five characters of each password’s SHA-1 hash are sent. Passwords never leave your device.")
                }
                .listRowBackground(VaultColors.surface)
            }
            .scrollContentBackground(.hidden)
            .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
            .navigationTitle("Watchtower")
            .navigationDestination(for: String.self) { ItemDetailScreen(itemID: $0) }
            .overlay { if checking { checkingOverlay } }
            .refreshable { await fullAudit() }
            .task { await fullAudit() }
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.items)
            }
        }
    }

    @ViewBuilder
    private func issueSection(_ title: LocalizedStringResource, _ subtitle: LocalizedStringResource, _ issues: [VaultIssue]) -> some View {
        if !issues.isEmpty {
            Section {
                ForEach(issues) { issue in
                    NavigationLink(value: issue.itemID) { WatchtowerIssueRow(issue: issue) }
                }
            } header: {
                Text(title)
            } footer: {
                Text(subtitle)
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private var checkingOverlay: some View {
        ProgressView("Checking breaches…")
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func fullAudit() async {
        health = PasswordAudit.analyze(env.repository.items)
        if env.settings.hibpEnabled { await runHIBP() }
    }

    private func runHIBP() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var cache: [String: Int] = [:]
        var results: [VaultIssue] = []
        for item in env.repository.items {
            guard let password = item.passwordField?.value, !password.isEmpty else { continue }
            let count: Int
            if let cached = cache[password] {
                count = cached
            } else {
                count = await HIBPService.pwnedCount(password: password)
                cache[password] = count
            }
            if count > 0 {
                results.append(PasswordAudit.issue(item, kind: .pwned, detail: "Seen \(count) times in breaches"))
            }
        }
        pwned = results
    }
}
