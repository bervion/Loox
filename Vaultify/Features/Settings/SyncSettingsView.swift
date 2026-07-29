import SwiftUI
#if DEBUG && canImport(UIKit)
import UIKit
#endif

/// iCloud sync controls. Sync is opt-in; it uploads only sealed ciphertext.
struct SyncSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showPairSheet = false
    #if DEBUG
    @State private var spikeEmail = ""
    @State private var inboxDiagnostics = ""
    #endif

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { env.settings.iCloudSyncEnabled },
            set: { isOn in
                env.settings.iCloudSyncEnabled = isOn
                // Logged here, not in the store didSet — erase/onboarding set the
                // flag programmatically and must not read as user toggles.
                AnalyticsEngine.shared.log(.icloudSyncToggled(enabled: isOn))
                AnalyticsEngine.shared.setUserProperty(.icloudSync, isOn ? "on" : "off")
                if isOn { env.syncNow() }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: syncBinding) {
                    // SF icloud: Polaris has no honest iCloud glyph (the generic
                    // sync arrows read as "refresh", not the iCloud feature).
                    Label { Text("iCloud Sync") } icon: { Image(systemName: "icloud.fill") }
                }
            } footer: {
                // Honest scope: secrets are sealed; a small set of organizational
                // metadata (folder icon/color/order, flags, timestamps) is not.
                Text("Your items are end-to-end encrypted before they sync. iCloud never sees titles, passwords, or notes. Organizational details like folder icons, colors, and timestamps sync as regular metadata.")
            }
            .listRowBackground(VaultColors.surface)

            if !CloudSyncService.isConfigured {
                Section {
                    VaultInfoBanner(.warning,
                                    text: "To use iCloud Sync, enable the iCloud capability (CloudKit) for the app target in Xcode and sign in to iCloud on this device.")
                        .inList()
                }
            }

            if env.settings.iCloudSyncEnabled {
                Section {
                    // Sync runs on its own; this is the manual nudge, so it takes
                    // the quiet inline rank. A bare Form button would inherit the
                    // app-wide primary tint and read as a static label.
                    Button { env.syncNow() } label: {
                        Label { Text("Sync Now") } icon: { Image(systemName: "arrow.clockwise.icloud") }
                    }
                    .buttonStyle(.themedCompact)
                    .disabled(env.cloudSync.status == .syncing)
                    statusRow
                } footer: {
                    // Passkeys whose credential id is too long for a CloudKit record
                    // name never reach iCloud. Stating it beats letting them look
                    // synced. Explanatory copy on this screen lives in the footer,
                    // never as a footnote row inside the card of controls.
                    if env.cloudSync.passkeysExcludedFromSync > 0 {
                        Text("Some passkeys stay on this device. Their credential IDs are too long for iCloud to store.")
                    }
                }
                .listRowBackground(VaultColors.surface)

                if CloudSyncService.isConfigured {
                    Section {
                        // The one filled action on this screen: pairing is the
                        // real destination here, syncing is upkeep.
                        Button { showPairSheet = true } label: {
                            Label { Text("Pair New Device") } icon: {
                                VaultIcon(Icons.scanCode, size: Metric.iconCompact)
                            }
                        }
                        .buttonStyle(.themedCompactProminent)
                        .disabled(env.session.state != .unlocked)
                    } footer: {
                        Text("Scan the QR code on a new iPhone, iPad, or Mac to give it access to this vault. The key transfers end-to-end encrypted.")
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
            #if DEBUG
            approvalSpikeSection
            inviteInboxDebugSection
            #endif
        }
        .themedFormBackground()
        .navigationTitle("iCloud Sync")
        .platformNavigationBarTitleDisplayMode(.inline)
        // Full screen: the flow opens straight into the camera, and a viewfinder
        // inset in a card fights the aiming it exists for. The scaffold carries
        // its own Cancel, so losing drag-to-dismiss costs no way out.
        .platformFullScreenCover(isPresented: $showPairSheet) { PairDeviceSheet() }
    }

    #if DEBUG
    /// Throwaway Phase-1 latency gating spike (two iCloud accounts). Plain
    /// unlocalized strings on purpose — DEBUG-only, deleted after the gate.
    private var approvalSpikeSection: some View {
        Section("Approval Spike (DEBUG)") {
            TextField("Participant iCloud email", text: $spikeEmail)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("1. Owner: create share") {
                Task { await ApprovalSpike.shared.startOwner(participantEmail: spikeEmail,
                                                             settings: env.settings) }
            }
            .disabled(!spikeEmail.contains("@"))
            if let url = ApprovalSpike.shared.shareURL {
                ShareLink("Send share link to participant", item: url)
            }
            Button("2. Requester: send request") {
                Task { await ApprovalSpike.shared.sendRequest(settings: env.settings) }
            }
            Button("3. Owner: approve pending") {
                Task { await ApprovalSpike.shared.approvePending() }
            }
            Text(ApprovalSpike.shared.status).font(.footnote).themedForeground(.secondary)
            Button("Reset owner spike", role: .destructive) {
                Task { await ApprovalSpike.shared.resetOwner() }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    /// Rendezvous invite-inbox QA panel (DEBUG; plain unlocalized strings).
    /// The app deliberately has no Files-app sharing, so diagnostics live
    /// here instead of a Documents log file.
    private var inviteInboxDebugSection: some View {
        Section("Invite Inbox (DEBUG V1.1)") {
            Button("Arm / re-arm inbox (B)") {
                Task {
                    guard let identity = await debugIdentity() else { return }
                    await env.inviteInbox.rearm(identity: identity)
                    inboxDiagnostics = await env.inviteInbox.diagnose()
                }
            }
            Button("Reconcile now (B)") {
                Task {
                    guard let identity = await debugIdentity() else { return }
                    let found = await env.inviteInbox.reconcile(identity: identity)
                    inboxDiagnostics = "reconcile returned \(found.count) NEW invite(s)\n"
                        + (await env.inviteInbox.diagnose())
                }
            }
            Button("Run diagnostics") {
                Task { inboxDiagnostics = await env.inviteInbox.diagnose() }
            }
            if !inboxDiagnostics.isEmpty {
                Text(verbatim: inboxDiagnostics)
                    .font(.system(size: 11, design: .monospaced))
                    .themedForeground(.secondary)
                    .textSelection(.enabled)
                #if os(iOS)
                Button("Copy report") { UIPasteboard.general.string = inboxDiagnostics }
                #endif
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    /// Vault-key-gated participant identity for the debug buttons.
    private func debugIdentity() async -> ParticipantIdentity? {
        guard let vaultKey = env.session.vaultKey?.bytes else {
            inboxDiagnostics = "vault is locked, unlock first"
            return nil
        }
        guard let identity = try? await env.participantEscrow.ensureIdentity(vaultKey: vaultKey) else {
            inboxDiagnostics = "participant identity unavailable (escrow failed)"
            return nil
        }
        return identity
    }
    #endif

    @ViewBuilder private var statusRow: some View {
        switch env.cloudSync.status {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: Space.s2) { ProgressView(); Text("Syncing…").themedForeground(.secondary) }
        case .success(let date):
            LabeledContent("Last sync", value: date.formatted(date: .omitted, time: .shortened))
        case .error(let message):
            Text(message).vaultType(.footnote)
                .foregroundStyle(env.theme.active.color(.destructive))
        case .configurationError(let message):
            // A schema gap is not a network blip: it never clears by retrying, so it
            // gets the banner treatment and names the plane that stopped syncing.
            VaultInfoBanner(.warning, verbatimText: message).inList()
        }
    }
}
