import SwiftUI

/// Quick-link flow (Loox Link): the owner picks which fields the link shows
/// and how long it lives; the snapshot is encrypted on device and uploaded as
/// ciphertext only — the decryption key exists solely in the produced URL's
/// fragment. Also manages this item's active links (device-local revoke).
struct QuickLinkView: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case config
        case creating
        case result(LooxLinkService.CreatedLink)
        case failed(String)
    }

    @State private var step: Step = .config
    @State private var selectedFieldIDs: Set<String> = []
    @State private var expiry: LooxLinkConfig.ExpiryPreset = .oneDay
    /// Burn after read — the link dies on its first open (server-enforced).
    @State private var oneTime = false
    @State private var seeded = false
    /// Link pending the destructive revoke confirmation.
    @State private var revokeTarget: LooxLinkRecord?
    @State private var paywallContext: LooxPaywallContext?

    private var item: VaultItem? { env.repository.item(id: itemID) }

    var body: some View {
        content
            .task {
                guard !seeded, let item else { return }
                seeded = true
                selectedFieldIDs = LooxLinkEnvelope.defaultSelectedFieldIDs(of: item)
            }
            .confirmationDialog("Revoke link?", isPresented: revokeDialogBinding,
                                titleVisibility: .visible) {
                Button("Revoke Link", role: .destructive) {
                    if let target = revokeTarget {
                        Task { await revoke(target) }
                    }
                }
            } message: {
                Text("Anyone who has the link loses access immediately.")
            }
    }

    private var revokeDialogBinding: Binding<Bool> {
        Binding(get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } })
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .config:
            configForm
        case .creating:
            VStack(spacing: Space.s4) {
                ProgressView()
                Text("Encrypting and creating your link…")
                    .vaultType(.callout).themedForeground(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let link):
            QuickLinkResultView(link: link) { step = .config }
        case .failed(let message):
            VStack(spacing: Space.s4) {
                PolarisIcon(Icons.alert, size: Metric.iconTile)
                    .themedForeground(.destructive)
                Text(verbatim: message)
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    step = .config
                } label: {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var configForm: some View {
        Form {
            if let item {
                Section {
                    ForEach(LooxLinkEnvelope.shareableFields(of: item)) { field in
                        QuickLinkFieldRow(field: field, isSelected: binding(for: field))
                    }
                } header: {
                    Text("What the link shows")
                } footer: {
                    Text("Only the fields you select are included. One-time codes and extra-protected values can never be shared in a link.")
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                Toggle(isOn: $oneTime.animation()) {
                    Text("One-time link")
                }
                // A one-time link has ONE lifetime story: it dies on first
                // open (fixed 24h safety net if never opened). Showing the
                // expiry picker alongside reads as two competing timers.
                if !oneTime {
                    Picker("Link expires after", selection: $expiry) {
                        ForEach(LooxLinkConfig.ExpiryPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                }
            } footer: {
                Text(oneTime
                     ? "The link disappears the first time it's opened. If nobody opens it, it expires on its own after 24 hours. The viewer asks for a tap first, so link previews can't use it up."
                     : "Everything is encrypted on this iPhone. The server stores only ciphertext; the decryption key travels inside the link and is never sent to any server.")
            }
            .listRowBackground(VaultColors.surface)

            let active = env.looxLinks.records.records(forItem: itemID)
            if !active.isEmpty {
                Section {
                    ForEach(active) { record in
                        LabeledContent {
                            Text("Expires \(record.expiresAt.formatted(Date.RelativeFormatStyle(presentation: .named).locale(appResourceLocale)))")
                                .vaultType(.footnote).themedForeground(.secondary)
                        } label: {
                            HStack(spacing: Space.s2) {
                                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .vaultType(.body).themedForeground()
                                if record.oneTime {
                                    Text("One-time")
                                        .vaultType(.caption).themedForeground(.accentText)
                                        .padding(.horizontal, Space.s2)
                                        .padding(.vertical, 2)
                                        .background(VaultColors.fill)
                                        .vaultCornerRadius(Radius.xs)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                revokeTarget = record
                            } label: {
                                Label("Revoke", image: Icons.trash)
                            }
                        }
                    }
                } header: {
                    Text("Active links")
                } footer: {
                    Text("This link can only be revoked from this device.")
                }
                .listRowBackground(VaultColors.surface)
            }

            // Create gates on capability availability; existing local link
            // history above stays visible in every state (INV-CAP-05/10).
            let createState = env.capabilities.availability(.shareLink, operation: .create)
            Section {
                switch createState {
                case .available:
                    createButton.disabled(selectedFieldIDs.isEmpty)
                case .offline:
                    Text("Connect to the internet to create a share link.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                default:
                    createButton.disabled(true)
                    Text(verbatim: shareStateFootnote(createState))
                        .vaultType(.footnote).themedForeground(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            // Over-quota upsell gate (§5.3): only successful creates in the
            // rolling window count (§3.2); revoking/expiry never refunds.
            // Managing or revoking existing links never gates.
            if LooxMembership.purchasesEnabled,
               case .needsUpgrade = LooxGate.canCreateLink(
                   tier: env.entitlements.tier, createdIn30d: linkCreates30d) {
                paywallContext = .linkQuota
            } else {
                Task { await create() }
            }
        } label: {
            Text("Create Link")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }
    }

    /// Device-local approximation of the rolling 30-day create count — the
    /// backend counter is the enforcement authority once it exists.
    private var linkCreates30d: Int {
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 3600)
        return env.looxLinks.records.records.filter { $0.createdAt >= cutoff }.count
    }

    private func shareStateFootnote(_ state: CapabilityAvailability) -> String {
        switch state {
        case .maintenance:
            return appString("Creating and managing links is temporarily paused. Your vault continues to work normally.")
        case .retired:
            return appString("Share Links are no longer offered. Your saved vault items are unchanged.")
        case .disabledByUser:
            return appString("Share Links are turned off in Settings.")
        default:
            return appString("Share Links are temporarily unavailable. Your vault is not affected.")
        }
    }

    private func binding(for field: DynamicField) -> Binding<Bool> {
        Binding(get: { selectedFieldIDs.contains(field.id) },
                set: { on in
                    if on { selectedFieldIDs.insert(field.id) }
                    else { selectedFieldIDs.remove(field.id) }
                })
    }

    private func create() async {
        // Re-entrancy guard: a double-tap queues two MainActor tasks; the
        // second must not mint a second link.
        guard case .config = step, let item else { return }
        step = .creating
        do {
            let link = try await env.looxLinks.createLink(
                item: item, selectedFieldIDs: selectedFieldIDs,
                expirySeconds: oneTime ? LooxLinkConfig.oneTimeFallbackExpirySeconds
                                       : expiry.seconds,
                oneTime: oneTime)
            step = .result(link)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func revoke(_ record: LooxLinkRecord) async {
        do {
            try await env.looxLinks.revoke(record)
        } catch {
            step = .failed(error.localizedDescription)
        }
        revokeTarget = nil
    }
}

extension LooxLinkConfig.ExpiryPreset {
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .oneDay: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
        return base.inAppLocalized
    }
}
