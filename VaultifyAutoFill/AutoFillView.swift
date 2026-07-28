import SwiftUI

/// Unlock then pick a login to fill (or create a new one). Items whose website matches the
/// requesting app/site are shown first. Unlock is handled by the shared `UnlockGate`.
struct AutoFillView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    /// The presentation's single vault store, opened by the hosting controller
    /// (a load failure cancels the request before any UI shows).
    let store: VaultStore
    /// Set when another flow already unlocked (passkey → password fallback):
    /// skips the second Face ID prompt for the same key.
    var presetKey: SecureBytes? = nil
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        UnlockGate(title: "Loox", presetKey: presetKey, onCancel: onCancel) { vaultKey in
            CredentialListView(serviceIdentifiers: serviceIdentifiers,
                               preferredRecordID: preferredRecordID,
                               store: store,
                               vaultKey: vaultKey,
                               onSelect: onSelect,
                               onCancel: onCancel)
        }
    }
}

/// One row in the picker — an owned vault login or a recipient-side shared credential
/// (from `SharedCredentialsCache`, never from `VaultStore`). Kept as an enum rather than
/// merging into `VaultItem` so a shared entry can never be mistaken for something this
/// extension could save/edit/re-seal.
private enum CredentialRow: Identifiable {
    case owned(VaultItem)
    case shared(SharedCredentialEntry)

    var id: String {
        switch self {
        case .owned(let item): return item.id
        case .shared(let entry): return entry.itemID
        }
    }

    var title: String {
        switch self {
        case .owned(let item): return item.title
        case .shared(let entry): return entry.title
        }
    }

    var username: String? {
        switch self {
        case .owned(let item):
            guard let field = item.usernameField, !field.isExtraProtected else { return nil }
            return field.value
        case .shared(let entry): return entry.username
        }
    }

    /// True when the login's username or password is sealed under Extra
    /// Protection — the extension can't produce plaintext, so the row shows
    /// locked instead of filling raw ciphertext into the website.
    var isSealedLogin: Bool {
        guard case .owned(let item) = self else { return false }
        return item.passwordField?.isExtraProtected == true
            || item.usernameField?.isExtraProtected == true
    }

    var isShared: Bool { if case .shared = self { return true }; return false }

    /// The grant's `askEachTime` TOTP field id, if this shared entry has one — drives
    /// the "Request code" affordance. Always nil for owned rows.
    var sharedTOTPFieldId: String? {
        if case .shared(let entry) = self { return entry.askEachTimeTOTPFieldId }
        return nil
    }

    var sharedEntry: SharedCredentialEntry? {
        if case .shared(let entry) = self { return entry }
        return nil
    }

    var ownedItem: VaultItem? {
        if case .owned(let item) = self { return item }
        return nil
    }

    func matches(serviceIdentifiers: [String]) -> Bool {
        switch self {
        case .owned(let item): return item.matchesAutoFill(serviceIdentifiers: serviceIdentifiers)
        case .shared(let entry): return entry.matchesAutoFill(serviceIdentifiers: serviceIdentifiers)
        }
    }

    var credential: (user: String, password: String) {
        switch self {
        case .owned(let item):
            guard !isSealedLogin else { return ("", "") }
            return (item.usernameField?.value ?? "", item.passwordField?.value ?? "")
        case .shared(let entry): return (entry.username ?? "", entry.password ?? "")
        }
    }
}

/// Post-unlock login picker. Loads logins + the default-identity prefill once, then auto-selects a
/// preferred record (the QuickType path) or shows the list with a "Create new login" entry. Shared
/// credentials (`SharedCredentialsCache`) are merged in read-only, marked with a "Shared" tag as a
/// separate label (not an interpunct-joined string).
private struct CredentialListView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let store: VaultStore
    let vaultKey: SecureBytes
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var items: [VaultItem] = []
    @State private var sharedEntries: [SharedCredentialEntry] = []
    @State private var defaultUsername = ""
    @State private var loaded = false
    /// Layer A for the shared-credential gate (INV-02): offline hides shared
    /// rows entirely; a satisfied path still needs the live check below.
    @State private var reachability = NetworkReachabilityMonitor()
    /// Non-nil while the pre-fill live grant check runs (INV-11).
    @State private var verifyingRowID: String?
    @State private var fillBlockedMessage: String?
    /// The shared askEachTime TOTP ceremony, run in a sheet OVER this picker
    /// so the fill session survives it.
    @State private var codeRequest: SharedCodeRequest?

    var body: some View {
        Group {
            if loaded { list } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .overlay { if verifyingRowID != nil { ProgressView().controlSize(.large) } }
        .disabled(verifyingRowID != nil)
        .alert(Text(verbatim: fillBlockedMessage ?? ""),
               isPresented: Binding(get: { fillBlockedMessage != nil },
                                    set: { if !$0 { fillBlockedMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $codeRequest) { request in
            RequestSharedCodeView(entry: request.entry, fieldId: request.fieldId,
                                  onClose: { codeRequest = nil },
                                  onOpenApp: { openInApp(itemID: request.entry.itemID) })
        }
        .task {
            guard !loaded else { return }
            items = VaultReader.logins(store: store, vaultKey: vaultKey)
            defaultUsername = VaultReader.autofillPrefillUsername(store: store, vaultKey: vaultKey)
            sharedEntries = SharedCredentialsCache.load(vaultKey: vaultKey)
            loaded = true
            if let preferredRecordID {
                if let hit = sharedEntries.first(where: { $0.itemID == preferredRecordID }) {
                    // Same gated path as a manual tap — QuickType must not
                    // bypass the live check (INV-11).
                    select(.shared(hit))
                } else if let hit = items.first(where: { $0.id == preferredRecordID }) {
                    select(.owned(hit))
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    CreateLoginView(host: serviceIdentifiers.first ?? "",
                                    defaultUsername: defaultUsername,
                                    store: store,
                                    vaultKey: vaultKey,
                                    onSaved: onSelect)
                } label: {
                    Text("＋ Create new login")
                }
            }
            if matched.isEmpty && !others.isEmpty {
                Section("All logins") { ForEach(others, content: row) }
            } else {
                if !matched.isEmpty { Section("For this app") { ForEach(matched, content: row) } }
                if !others.isEmpty { Section("Other logins") { ForEach(others, content: row) } }
            }
            if rows.isEmpty { Text("No logins found").foregroundStyle(.secondary) }
            if !reachability.hasSatisfiedNetworkPath && !sharedEntries.isEmpty {
                Text("Shared items need an internet connection.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Offline ⇒ shared credentials are not offered at all (absolute online
    /// gate — same rule the app applies).
    private var visibleSharedEntries: [SharedCredentialEntry] {
        reachability.hasSatisfiedNetworkPath ? sharedEntries : []
    }

    private var rows: [CredentialRow] {
        items.map(CredentialRow.owned) + visibleSharedEntries.map(CredentialRow.shared)
    }
    private var matched: [CredentialRow] { rows.filter { $0.matches(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [CredentialRow] {
        serviceIdentifiers.isEmpty ? rows : rows.filter { !$0.matches(serviceIdentifiers: serviceIdentifiers) }
    }

    private func row(_ row: CredentialRow) -> some View {
        HStack {
            Button { select(row) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title.isEmpty ? "Untitled" : row.title).foregroundStyle(.primary)
                    if let user = row.username, !user.isEmpty {
                        HStack(spacing: 4) {
                            Text(user).font(.caption).foregroundStyle(.secondary)
                            if row.isShared {
                                Text("Shared").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if row.isShared {
                        Text("Shared").font(.caption).foregroundStyle(.secondary)
                    }
                    if row.isSealedLogin {
                        Label("Extra Protection", systemImage: "lock.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            // Alias reuse (owned rows only): the written-back "Private email" field
            // fills instead of the primary username. Read-only vault access — the
            // extension makes NO relay network calls; provisioning stays in the app.
            .contextMenu {
                if let item = row.ownedItem, let alias = item.privateEmailValue,
                   item.passwordField?.isExtraProtected != true {
                    Button {
                        onSelect(alias, item.passwordField?.value ?? "")
                    } label: {
                        Label("Use private email", systemImage: "envelope.badge.shield.half.filled")
                    }
                }
            }
            Spacer()
            // The extension carries the same iCloud container as the app, so the
            // request/response ceremony runs HERE. Deep-linking out used to end
            // the fill session (`onCancel` completes the request with a cancel
            // error and iOS gives no way to resume it), which meant copying a
            // ~30s code in another app and finding your way back by hand.
            if let fieldId = row.sharedTOTPFieldId, let entry = row.sharedEntry {
                Button {
                    codeRequest = SharedCodeRequest(entry: entry, fieldId: fieldId)
                } label: {
                    Label("Request code", systemImage: "arrow.up.right.square")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Request code"))
            }
        }
    }

    private func select(_ row: CredentialRow) {
        // A sealed credential would fill raw `v2g:` ciphertext — explain
        // instead. Revealing needs the Extra Password ceremony in the app.
        if row.isSealedLogin {
            fillBlockedMessage = appString("This login is behind Extra Protection. Open Loox to reveal it.")
            return
        }
        // Shared credentials pass the authoritative gate right before the
        // fill (INV-11): live grant check, fail-closed on every outcome that
        // isn't a verified match. Owned items fill directly as before.
        if let entry = row.sharedEntry {
            guard reachability.hasSatisfiedNetworkPath else {
                fillBlockedMessage = appString("Shared items need an internet connection.")
                return
            }
            verifyingRowID = row.id
            Task {
                let outcome = await SharedGrantLiveCheck.verify(
                    zoneName: entry.zoneName, ownerName: entry.ownerName,
                    expectedGrantId: entry.grantId)
                verifyingRowID = nil
                switch outcome {
                case .authorized:
                    onSelect(entry.username ?? "", entry.password ?? "")
                case .revoked:
                    fillBlockedMessage = appString("The owner has revoked access to this item.")
                case .unavailable:
                    fillBlockedMessage = appString("Couldn't verify access right now.")
                }
            }
            return
        }
        let credential = row.credential
        onSelect(credential.user, credential.password)
    }

    /// The explicit escape hatch, never the default: leaving for the app ENDS
    /// this fill session, so it only happens when the user asks for it.
    private func openInApp(itemID: String) {
        guard let url = SharedItemDeepLink.url(itemID: itemID) else { return }
        codeRequest = nil
        openURL(url)
        onCancel()
    }
}

/// One pending shared-TOTP ceremony. Identified by the item so tapping the
/// same row twice reuses the sheet instead of stacking a second request.
private struct SharedCodeRequest: Identifiable {
    let entry: SharedCredentialEntry
    let fieldId: String
    var id: String { entry.itemID }
}

/// The recipient's ask-and-wait ceremony for one shared `askEachTime` TOTP
/// field, run inside the AutoFill extension.
///
/// Closing this sheet returns to the credential picker with the fill session
/// intact — the user can copy the code into the site's 2FA box and still fill
/// the username and password from the row behind it.
private struct RequestSharedCodeView: View {
    let entry: SharedCredentialEntry
    let fieldId: String
    let onClose: () -> Void
    let onOpenApp: () -> Void

    private enum Phase {
        case idle
        case requesting
        case waiting
        case delivered(code: String, periodEndUnixMs: Int64)
        case failed(message: String, retryable: Bool)
    }

    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    @State private var secondsLeft = 0
    @State private var copied = false

    /// How long the owner has to answer before this gives up
    /// (`SharedAccessTimingPolicy.extensionPollingBudget`).
    private static let budgetSeconds =
        Int(SharedAccessTimingPolicy.standard.extensionPollingBudget.components.seconds)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    content
                } footer: {
                    // States the real constraint on the OTHER device up front,
                    // so a timeout reads as "they never got to it" instead of
                    // a broken feature. Redundant once the code is here.
                    if showsOwnerNote {
                        Text("The owner has to open Loox and approve with Face ID. Nothing is filled until they do.")
                    }
                }
                Section {
                    Button("Open Loox") { onOpenApp() }
                } footer: {
                    Text("Opening Loox ends this fill, so you would have to start it again.")
                }
            }
            .navigationTitle(Text(verbatim: entry.title.isEmpty
                                  ? appString("Request code") : entry.title))
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { task?.cancel(); onClose() }
                }
            }
        }
        .task(id: isWaiting) { await runCountdown() }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Button(action: start) {
                HStack { Spacer(); Text("Request Code").bold(); Spacer() }
            }
        case .requesting:
            HStack(spacing: 8) { ProgressView(); Text("Sending request…") }
        case .waiting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Waiting for the owner to approve…").font(.footnote)
                if secondsLeft > 0 {
                    Text("About \(secondsLeft) seconds left")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Cancel", role: .cancel) { task?.cancel(); phase = .idle }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        case let .delivered(code, periodEndUnixMs):
            DeliveredCodeView(code: code, periodEndUnixMs: periodEndUnixMs,
                              copied: $copied, onExpired: {
                                  phase = .failed(message: appString("The code expired."),
                                                  retryable: true)
                              })
        case let .failed(message, retryable):
            VStack(spacing: 12) {
                Text(verbatim: message)
                    .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                if retryable {
                    Button("Request Again", action: start).buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var isWaiting: Bool { if case .waiting = phase { return true }; return false }

    private var showsOwnerNote: Bool { if case .delivered = phase { return false }; return true }

    private func start() {
        task?.cancel()
        copied = false
        phase = .requesting
        task = Task {
            do {
                let ticket = try await SharedTOTPApprovalTransport.submitRequest(
                    zoneName: entry.zoneName, ownerName: entry.ownerName,
                    expectedGrantId: entry.grantId, fieldId: fieldId)
                phase = .waiting
                let payload = try await SharedTOTPApprovalTransport.awaitApproval(ticket)
                phase = .delivered(code: payload.code,
                                   periodEndUnixMs: payload.periodEndUnixMs)
            } catch is CancellationError {
                phase = .idle
            } catch {
                let outcome = Self.outcome(for: error)
                phase = .failed(message: outcome.message, retryable: outcome.retryable)
            }
        }
    }

    /// Names the actual cause. Only `.rejected` and `.interrupted` mean the
    /// owner saw the request; everything else failed before or after their
    /// device was involved, so none of them may imply a decision was made.
    private static func outcome(for error: any Error) -> (message: String, retryable: Bool) {
        switch error {
        case SharedTOTPApprovalTransport.Failure.rejected:
            return (appString("The owner declined this request."), true)
        case SharedTOTPApprovalTransport.Failure.interrupted:
            return (appString("The owner started to approve, then Loox closed on their device."), true)
        case SharedTOTPApprovalTransport.Failure.timedOut:
            return (appString("No answer from the owner. They may not have Loox open."), true)
        case SharedTOTPApprovalTransport.Failure.grantUnavailable:
            return (appString("Couldn't load this share. It may have been revoked, or you may be offline."), true)
        case SharedTOTPApprovalTransport.Failure.capabilityNotGranted:
            return (appString("This code isn't shared with you anymore."), false)
        case SharedTOTPApprovalTransport.Failure.invalidResponse:
            return (appString("The owner's answer couldn't be verified."), true)
        case SharedTOTPApprovalTransport.Failure.notConfigured:
            return (appString("iCloud sharing isn't available in this version of Loox."), false)
        default:
            return (appString("Couldn't reach iCloud. Check your connection."), true)
        }
    }

    /// Display-only clock for the wait; the transport owns the real deadline.
    private func runCountdown() async {
        guard isWaiting else { return }
        var remaining = Self.budgetSeconds
        while isWaiting, remaining > 0 {
            secondsLeft = remaining
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            remaining -= 1
        }
        secondsLeft = 0
    }
}

/// The delivered code with a copy control and an ADVISORY countdown — the
/// site's own clock is the final authority. The code is never persisted, and
/// the clipboard copy expires with the code's window so a 2FA secret does not
/// outlive its usefulness on the pasteboard.
private struct DeliveredCodeView: View {
    let code: String
    let periodEndUnixMs: Int64
    @Binding var copied: Bool
    let onExpired: () -> Void

    @State private var remainingSeconds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: code)
                    .font(.title2).bold().monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                // Bare numeral plus the SI symbol for seconds — no wording to
                // translate, and it stays legible next to the code.
                Text(verbatim: "\(remainingSeconds)s").font(.footnote)
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Button(copied ? "Copied" : "Copy", action: copy)
                .buttonStyle(.borderedProminent)
            Text("Use it now. It expires with the current window.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await tick() }
    }

    private func copy() {
        // Clears itself when this code's window closes, so a copied OTP never
        // outlives the code it belongs to.
        let remaining = TimeInterval(max(0, periodEndUnixMs - Int64(Date().timeIntervalSince1970 * 1000))) / 1000
        PlatformPasteboard.copySensitive(code, clearAfter: remaining)
        copied = true
    }

    private func tick() async {
        while !Task.isCancelled {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let remaining = max(0, periodEndUnixMs - nowMs)
            remainingSeconds = Int(remaining / 1000)
            if remaining <= 0 { onExpired(); return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
