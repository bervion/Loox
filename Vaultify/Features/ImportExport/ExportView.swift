import SwiftUI

/// Ceilings on what one encrypted backup may carry.
///
/// Every attachment plaintext an export gathers is live in memory at the same
/// time, and `VaultBackup.exportEncrypted` then seals each one and base64s the
/// lot into JSON twice, so peak residency is several times the attachment total.
/// Ten 20 MiB attachments is a jetsam kill in the middle of the one operation a
/// user runs specifically to not lose data. The ceiling is chosen so the whole
/// pipeline stays inside an app's memory budget and so the resulting file still
/// clears `ImportLimits` on the way back in.
nonisolated enum ExportLimits {
    /// Total attachment PLAINTEXT bytes one encrypted backup may carry.
    static let maxArtifactBytes = 48 * 1024 * 1024

    /// The same ceiling in MB, for the message that has to name a number.
    static var maxArtifactMegabytes: Int { maxArtifactBytes / (1024 * 1024) }

    static func fits(artifactBytes: Int) -> Bool { artifactBytes <= maxArtifactBytes }
}

/// Where an export file lives while it waits to be shared, and every way it
/// leaves again.
///
/// A CSV export is the user's entire vault in the clear. Writing it to a fixed
/// name in the temporary directory and never removing it left that file behind
/// after the share, after the screen closed, after the vault locked, and across
/// launches. Each export now gets a fresh directory under one root, so a single
/// removal drops whatever any export ever wrote.
nonisolated enum ExportTempFiles {
    static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "vault-exports")
    }

    /// Remove every export ever written. Safe to call when nothing is there.
    static func purge() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Write one export into its own directory, after dropping any previous
    /// one. The visible filename stays stable (it is what the share sheet
    /// shows); uniqueness lives in the directory above it.
    static func write(_ data: Data, name: String) throws -> URL {
        purge()
        let directory = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// Export the vault as a passphrase-encrypted backup (recommended) or plain CSV.
struct ExportView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case encrypted, csv
        var id: String { rawValue }
        var title: LocalizedStringResource {
            let base: LocalizedStringResource = self == .encrypted ? "Encrypted" : "CSV (plain)"
            return base.inAppLocalized
        }
    }

    /// One artifact this export intends to carry, planned from its manifest
    /// alone so the total size is known before a single plaintext is decrypted.
    private struct PlannedArtifact {
        let record: ArtifactRecord
        let manifest: ArtifactManifest
    }

    private struct ArtifactPlan {
        var planned: [PlannedArtifact] = []
        var totalBytes = 0
        /// Artifacts an item still points at but this device cannot produce:
        /// bytes not synced here, or a manifest that will not open.
        var unavailable = 0
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: Mode = .encrypted
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var exportURL: URL?
    @State private var working = false
    @State private var error: String?
    @State private var confirmPlainExport = false
    @State private var confirmIncompleteAttachments = false
    /// Set only by the user answering the incomplete-attachments dialog. A
    /// backup that quietly drops attachments is a backup that fails at restore,
    /// so the gap is never accepted on the user's behalf.
    @State private var acceptedIncompleteExport = false

    private var canExport: Bool {
        guard !env.repository.items.isEmpty || !env.repository.passkeys.isEmpty else { return false }
        if mode == .encrypted { return passphrase.count >= 8 && passphrase == confirm }
        return true
    }

    var body: some View {
        Form {
            Picker("Format", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { discardExport() }

            if mode == .encrypted {
                Section {
                    RevealableSecureField(title: "Password", text: $passphrase, inList: true)
                    RevealableSecureField(title: "Confirm", text: $confirm, inList: true)
                } header: {
                    Text("Backup password")
                } footer: {
                    Text("The backup is sealed with Argon2id + AES-256-GCM. You’ll need this password to restore it.")
                }
                .listRowBackground(VaultColors.surface)
            } else {
                Section {
                    Label {
                        Text("A CSV export is **not encrypted**. Anyone with the file can read every password. Passkeys are never included in CSV.")
                    } icon: {
                        VaultIcon(Icons.alert).foregroundStyle(VaultColors.strengthWeak)
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                if mode == .csv {
                    // Plaintext export gets deliberate friction: a destructive-styled
                    // CTA plus a confirmation, so it can't be created in passing.
                    Button(role: .destructive) { confirmPlainExport = true } label: {
                        Text("Create Unencrypted Export")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(env.theme.active.color(.destructive))
                    }
                    .disabled(!canExport || working)
                } else {
                    Button { Task { await generate() } } label: {
                        Text("Create Export").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .disabled(!canExport || working)
                }
            } footer: {
                Text("Exports include your archived items. Recently Deleted is not included.")
            }
            .listRowBackground(VaultColors.surface)

            if let exportURL {
                Section {
                    ShareLink(item: exportURL) {
                        Label { Text("Share Export") } icon: { VaultIcon(Icons.share) }
                    }
                } footer: {
                    Text("This file is removed when you leave this screen, when the app is backgrounded, and when the vault locks.")
                }
                .listRowBackground(VaultColors.surface)
            }

            if let error {
                Section {
                    VaultInfoBanner(.error, verbatimText: error).inList()
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("Export")
        .platformNavigationBarTitleDisplayMode(.inline)
        .overlay { if working { ProgressView().controlSize(.large).allowsHitTesting(false) } }
        .confirmationDialog("Create an unencrypted export?",
                            isPresented: $confirmPlainExport, titleVisibility: .visible) {
            Button("Create Unencrypted Export", role: .destructive) { Task { await generate() } }
        } message: {
            Text("Anyone who gets this file can read every password in it. Delete it as soon as you're done.")
        }
        .confirmationDialog("Some attachments can’t be included",
                            isPresented: $confirmIncompleteAttachments, titleVisibility: .visible) {
            Button("Export Without Them") {
                acceptedIncompleteExport = true
                Task { await generate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some attachments could not be read on this device. The backup will restore everything else.")
        }
        // Cleanup triggers. The system share sheet reports no completion to
        // SwiftUI's `ShareLink`, so leaving the screen is the moment that stands
        // in for "done sharing"; the rest close the other ways a plaintext file
        // could outlive its purpose.
        .onAppear {
            // Anything still here belongs to an earlier run of the app.
            if exportURL == nil { ExportTempFiles.purge() }
        }
        .onDisappear { discardExport() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { discardExport() }
        }
        .onChange(of: env.session.state) { _, state in
            if state != .unlocked { discardExport() }
        }
    }

    /// Drop the export file and the link to it in one step, so the UI can never
    /// offer a share for bytes that are gone.
    private func clearExportFile() {
        exportURL = nil
        ExportTempFiles.purge()
    }

    /// `clearExportFile` plus forgetting that the user accepted an incomplete
    /// backup: acceptance belongs to one export attempt, never to the screen.
    private func discardExport() {
        acceptedIncompleteExport = false
        clearExportFile()
    }

    private func generate() async {
        working = true
        error = nil
        clearExportFile()
        defer { working = false }
        do {
            // Archived items are still the user's data — an export that dropped
            // them would read as complete and only reveal the loss at restore.
            // Trash stays out: it is a pending delete, not vault content.
            let items = env.repository.items + env.repository.archived
            let folderNames = Dictionary(env.repository.folders.map { ($0.id, $0.name) },
                                         uniquingKeysWith: { a, _ in a })
            if mode == .encrypted {
                let passkeys = env.session.vaultKey.map { PasskeyVault(store: env.store).secrets(key: $0) } ?? []
                // A backup that silently omits existing passkeys would betray
                // its purpose exactly when it matters (restore) — refuse
                // instead of exporting an incomplete vault.
                if passkeys.count < env.repository.passkeys.count {
                    throw ExportError.passkeysUnavailable
                }
                // Carry the (still-wrapped) Level-2 key: sealed field values are
                // in the items, and without the wrap a restore on a new device
                // could never open them again.
                let level2 = VaultKeyBundle.load().flatMap { bundle -> VaultBackup.Level2Wrap? in
                    guard let wrapped = bundle.wrappedL2SK, let salt = bundle.l2Salt,
                          let kdf = bundle.l2Kdf else { return nil }
                    return VaultBackup.Level2Wrap(wrappedL2SK: wrapped, salt: salt, kdf: kdf)
                }
                adoptLegacyAttachments(in: items)
                // Plan from manifests only: sizes and availability are known
                // before a single attachment is decrypted, so an oversized
                // vault is refused without ever allocating for it.
                let plan = artifactPlan(for: items)
                guard ExportLimits.fits(artifactBytes: plan.totalBytes) else {
                    throw ExportError.attachmentsTooLarge
                }
                if plan.unavailable > 0, !acceptedIncompleteExport {
                    confirmIncompleteAttachments = true
                    return
                }
                let load = await loadArtifacts(plan.planned)
                if load.unreadable > 0, !acceptedIncompleteExport {
                    confirmIncompleteAttachments = true
                    return
                }
                let data = try await VaultBackup.exportEncrypted(items, folderNames: folderNames,
                                                                 passkeys: passkeys, level2: level2,
                                                                 artifacts: load.payloads,
                                                                 passphrase: passphrase)
                exportURL = try ExportTempFiles.write(data, name: "loox-backup.vaultify")
            } else {
                exportURL = try ExportTempFiles.write(
                    Data(VaultBackup.makeCSV(items, folderNames: folderNames).utf8),
                    name: "loox-export.csv")
            }
            // Acceptance was for THIS file. The next export asks again.
            acceptedIncompleteExport = false
            AnalyticsEngine.shared.log(.vaultExported)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }

    /// Legacy sidecar attachments adopt into first-class artifacts at export
    /// time — a backup is exactly the moment their bytes must become portable.
    /// Adoption is idempotent; missing legacy bytes stay honestly absent.
    private func adoptLegacyAttachments(in items: [VaultItem]) {
        for item in items {
            for field in item.fields where field.kind == .fileRef {
                guard let meta = AttachmentMeta.decode(field.value),
                      meta.v2 != true else { continue }
                _ = try? env.artifactStore.adoptLegacyAttachment(
                    meta, ownerItemId: item.id, from: env.attachmentStore)
            }
        }
    }

    /// Which artifacts this export can carry and how many bytes they are, read
    /// from sealed manifests without touching a single blob.
    private func artifactPlan(for items: [VaultItem]) -> ArtifactPlan {
        var plan = ArtifactPlan()
        for item in items {
            for record in env.artifactStore.records(ownerItemId: item.id) {
                guard env.artifactStore.hasBytes(record),
                      let manifest = try? env.artifactStore.manifest(for: record) else {
                    // The item keeps its file reference either way. Counting
                    // this is what turns a silently lossy backup into a choice.
                    plan.unavailable += 1
                    continue
                }
                plan.planned.append(PlannedArtifact(record: record, manifest: manifest))
                plan.totalBytes += manifest.plaintextByteCount
            }
        }
        return plan
    }

    /// Decrypt the planned artifacts one at a time.
    ///
    /// `ArtifactStore` is a main-actor type, so the decrypt itself cannot leave
    /// the main actor; yielding between artifacts is what keeps a large vault
    /// from freezing the run loop for the whole pass. The autorelease pool drops
    /// the Foundation temporaries each decrypt leaves behind instead of letting
    /// them stack up until the loop ends.
    private func loadArtifacts(
        _ planned: [PlannedArtifact]
    ) async -> (payloads: [VaultBackup.ArtifactPayload], unreadable: Int) {
        var payloads: [VaultBackup.ArtifactPayload] = []
        payloads.reserveCapacity(planned.count)
        var unreadable = 0
        for entry in planned {
            let payload: VaultBackup.ArtifactPayload? = autoreleasepool {
                guard let data = try? env.artifactStore.loadPlaintext(entry.record) else { return nil }
                return VaultBackup.ArtifactPayload(id: entry.record.id,
                                                   ownerItemId: entry.record.ownerItemId,
                                                   filename: entry.manifest.filename,
                                                   utiType: entry.manifest.utiType,
                                                   data: data)
            }
            if let payload {
                payloads.append(payload)
            } else {
                unreadable += 1
            }
            await Task.yield()
        }
        return (payloads, unreadable)
    }
}

/// An encrypted export must be COMPLETE to be a backup — a passkey the vault
/// holds but the export can't resolve (vault key unavailable mid-flight, or a
/// credential that fails to decode) would make the file silently lossy,
/// discovered only at restore time.
private enum ExportError: LocalizedError {
    case passkeysUnavailable
    case attachmentsTooLarge

    var errorDescription: String? {
        switch self {
        case .passkeysUnavailable:
            return appString("Passkeys couldn't be included in this export. Lock the app, unlock it, then try again.")
        case .attachmentsTooLarge:
            return appString("The attachments in this vault total more than \(ExportLimits.maxArtifactMegabytes) MB, which is more than one backup can hold. Remove some attachments and try again.")
        }
    }
}
