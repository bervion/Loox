import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

/// One parsed row: the item plus the folder NAME it should join (if any).
///
/// Top level (not nested in the view) and `Sendable` on purpose: parsing happens
/// off the main actor, so the result has to cross an actor boundary to reach the
/// preview list.
nonisolated struct ParsedImportRow: Identifiable, Sendable {
    let item: VaultItem
    let folderName: String?
    var id: String { item.id }
}

/// Ceilings applied to a file BEFORE it is read into memory or written into the
/// vault.
///
/// The author of a backup chooses everything in it and hands the passphrase to
/// the victim, so "the file came from the user" is not a size guarantee. A
/// multi-gigabyte file, or a payload holding millions of rows, is a jetsam kill
/// dressed up as an import.
///
/// The two byte ceilings are sized so this app's OWN heaviest legal export still
/// round-trips: `ExportLimits.maxArtifactBytes` of attachments base64 into
/// roughly 1.34x inside the sealed payload and roughly 1.78x in the finished
/// file, so both limits sit comfortably above that with margin to spare.
nonisolated enum ImportLimits {
    /// Largest file this app will read into memory at all.
    static let maxFileBytes = 128 * 1024 * 1024

    /// Largest sealed payload inside an encrypted envelope. Bounds what
    /// AES-GCM will allocate when the envelope is opened, and bites before the
    /// file ceiling would on a file that is almost entirely ciphertext.
    static let maxSealedBytes = 96 * 1024 * 1024

    /// Row ceilings. Each restored record is a Core Data insert plus a seal, so
    /// these bound work as much as memory.
    static let maxItems = 20_000
    static let maxPasskeys = 5_000
    static let maxArtifacts = 2_000

    static func fits(fileByteCount: Int) -> Bool { fileByteCount <= maxFileBytes }

    static func fits(sealedByteCount: Int) -> Bool { sealedByteCount <= maxSealedBytes }

    static func fits(items: Int, passkeys: Int, artifacts: Int) -> Bool {
        items <= maxItems && passkeys <= maxPasskeys && artifacts <= maxArtifacts
    }
}

/// Why an import will leave level2-sealed field values unreadable.
///
/// Adoption of a backup's Level-2 wrap is silent by nature: it writes a Keychain
/// bundle nobody sees. Each non-adopting outcome strands every sealed value in
/// the payload, and the user discovers it days later as "Couldn't decrypt this
/// field", so the decision has to be spoken before the import runs and reported
/// after it.
nonisolated enum Level2ImportWarning: Equatable, Sendable {
    /// This device already has its own Extra Password, so the backup's wrap is
    /// kept out. Values sealed under a DIFFERENT key stay closed.
    case deviceHasOwnWrap
    /// The wrap was refused (out-of-policy Argon2 parameters, a salt Argon2
    /// would reject, an empty wrap, or no key bundle to write into).
    case wrapRefused
    /// The payload has sealed values but carries no Level-2 wrap at all.
    case noWrapInBackup

    /// `adoption` is the outcome of `VaultSession.level2Adoption` — the
    /// prediction before the import, the real result after it. Both feed the
    /// same evaluation so the warning and the report can never disagree.
    static func evaluate(sealedFieldCount: Int, hasWrap: Bool,
                         adoption: VaultSession.Level2AdoptionResult?) -> Level2ImportWarning? {
        guard sealedFieldCount > 0 else { return nil }
        guard hasWrap else { return .noWrapInBackup }
        switch adoption {
        case .some(.adopted), .none: return nil
        case .some(.skippedDeviceHasOwnWrap): return .deviceHasOwnWrap
        case .some(.refusedInvalidPolicy): return .wrapRefused
        }
    }

    /// Deliberately says "will not open here" rather than "is lost": a user
    /// re-importing their OWN backup onto a device that still holds the same
    /// Extra Password reads `deviceHasOwnWrap` and their fields do open.
    var message: LocalizedStringKey {
        switch self {
        case .deviceHasOwnWrap:
            return "This device already has its own Extra Password. Any value this backup sealed with a different one will not open here."
        case .wrapRefused:
            return "The Extra Password settings in this backup were refused, so values it sealed will not open here."
        case .noWrapInBackup:
            return "This backup has sealed values but not the Extra Password key for them, so they will not open here."
        }
    }
}

/// What one import actually did, per category.
///
/// A restore touches five independent stores (the Level-2 Keychain bundle,
/// items, Spaces, artifact files, passkeys) and a failure in any of them leaves
/// the others already written. Reporting a single "imported" or "failed" for
/// that is a lie in both directions, so every category carries its own
/// imported/total pair and the screen shows them.
nonisolated struct ImportReport: Equatable, Sendable {
    var itemsTotal = 0
    var itemsImported = 0
    var foldersCreated = 0
    var artifactsTotal = 0
    var artifactsImported = 0
    var passkeysTotal = 0
    var passkeysImported = 0
    var sealedFieldCount = 0
    var hasLevel2Wrap = false
    var level2: VaultSession.Level2AdoptionResult?

    var recordsImported: Int { itemsImported + passkeysImported }

    var level2Warning: Level2ImportWarning? {
        Level2ImportWarning.evaluate(sealedFieldCount: sealedFieldCount,
                                     hasWrap: hasLevel2Wrap, adoption: level2)
    }

    /// Everything the file offered is in the vault and openable. Anything less
    /// keeps the screen open with the numbers on it.
    var isComplete: Bool {
        itemsImported == itemsTotal
            && artifactsImported == artifactsTotal
            && passkeysImported == passkeysTotal
            && level2Warning == nil
    }
}

/// Reading and classifying an import file, off the main actor.
///
/// `Data(contentsOf:)` is unbounded and `parseCSVWithFolders` walks every
/// character, so both belong on a background executor behind a size gate.
nonisolated enum ImportProbe {
    enum Outcome: Sendable {
        case encrypted(Data)
        case rows([ParsedImportRow])
        case tooLarge
        case unreadable
        /// A Loox envelope this app cannot open: rejected Argon2 parameters, a
        /// salt Argon2 would refuse, or an empty payload. Naming it separately
        /// is the whole point — it must never reach the user as "wrong
        /// password".
        case damaged
        case emptyCSV
        case unsupported
        case tooManyRecords
    }

    /// The envelope fields that decode WITHOUT `KdfParams`. When the full
    /// `EncryptedBackup` decode fails but this one succeeds, the file is a Loox
    /// backup whose parameters were rejected — damaged, not "not ours".
    private struct EnvelopeProbe: Decodable {
        var version: Int
        var salt: Data
        var sealed: Data
    }

    static func read(_ url: URL) -> Outcome {
        guard let size = byteCount(of: url) else { return .unreadable }
        guard ImportLimits.fits(fileByteCount: size) else { return .tooLarge }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return classify(data)
    }

    /// Split from `read` so the classification rules can be exercised without a
    /// file on disk.
    static func classify(_ data: Data) -> Outcome {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(VaultBackup.EncryptedBackup.self, from: data)
            guard ImportLimits.fits(sealedByteCount: envelope.sealed.count),
                  ImportLimits.fits(sealedByteCount: envelope.wrappedCK?.count ?? 0)
            else { return .tooLarge }
            // The envelope's own salt never passes through `KdfParams`'
            // validating decoder, and a short one makes Argon2 return
            // ARGON2_SALT_TOO_SHORT — which used to surface as "couldn't
            // decrypt" and was indistinguishable from a bad passphrase.
            guard KdfParams.isAcceptableSalt(envelope.salt),
                  !envelope.sealed.isEmpty, envelope.version >= 1
            else { return .damaged }
            return .encrypted(data)
        } catch {
            if (try? decoder.decode(EnvelopeProbe.self, from: data)) != nil { return .damaged }
        }
        guard let text = String(data: data, encoding: .utf8) else { return .unsupported }
        // A JSON document is not a CSV. Without this the row parser happily
        // turns arbitrary JSON into junk items, because braces and commas parse.
        guard let first = text.first(where: { !$0.isWhitespace }),
              first != "{", first != "[" else { return .unsupported }
        let rows = VaultBackup.parseCSVWithFolders(text)
        guard !rows.isEmpty else { return .emptyCSV }
        guard rows.count <= ImportLimits.maxItems else { return .tooManyRecords }
        return .rows(rows.map { ParsedImportRow(item: $0.item, folderName: $0.folderName) })
    }

    /// File size from metadata, so an oversized file is refused before a single
    /// byte of it is resident.
    private static func byteCount(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}

/// Telling a wrong passphrase apart from a file that could never be opened.
///
/// Only an authentication failure means "this key is not the key". Everything
/// else — a rejected decode, a refused artifact path, an Argon2 refusal — is a
/// property of the FILE, and reporting it as a password problem sends the user
/// to retype a passphrase that was right the first time.
nonisolated enum ImportFailureMessage {
    static func text(for error: any Error) -> String {
        if let failure = error as? CryptoKitError {
            if case .authenticationFailure = failure { return wrongPassword }
            return damaged
        }
        if error is DecodingError || error is VaultBackup.BackupFailure
            || error is Argon2.Failure || error is PasskeyEnvelope.Failure
            || error is AESGCM.Failure {
            return damaged
        }
        return wrongPassword
    }

    static var damaged: String { appString("This backup file is damaged and can’t be opened.") }
    static var wrongPassword: String { appString("Couldn’t decrypt, check the password.") }
}

/// Import from a CSV export (1Password / Bitwarden / Chrome) or a Vaultify
/// encrypted backup. Folder names in the file are resolved to Spaces on import
/// (matched by name, created if missing); tags are restored too.
struct ImportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var parsed: [ParsedImportRow] = []
    @State private var parsedPasskeys: [PasskeySecret] = []
    /// The backup's Level-2 wrap (if any) — adopted on import when this device
    /// has none, so restored sealed fields stay openable with the Extra Password.
    @State private var parsedLevel2: VaultBackup.Level2Wrap?
    /// Validated artifact plaintexts from a v2 backup, re-sealed under THIS
    /// vault's key hierarchy at import time.
    @State private var parsedArtifacts: [VaultBackup.ArtifactPayload] = []
    /// Counted once when the payload is parsed: recomputing it in `body` would
    /// walk every field of every item on each render.
    @State private var sealedFieldCount = 0
    /// What adoption WOULD do, computed from this device's key bundle at parse
    /// time so the warning can be shown before the Import button is tapped.
    @State private var level2Prediction: VaultSession.Level2AdoptionResult?
    @State private var encryptedData: Data?
    @State private var passphrase = ""
    @State private var error: String?
    @State private var working = false
    @State private var loadTask: Task<Void, Never>?
    @State private var decryptTask: Task<Void, Never>?
    @State private var confirmStranding = false
    @State private var report: ImportReport?

    var body: some View {
        Form {
            Section {
                // Quiet rank on purpose: this row stays on screen next to the
                // Decrypt / Import primaries, so it must never be a second
                // filled CTA. A bare Form button would inherit the app-wide
                // primary tint and read as a static label instead of a control.
                Button { showPicker = true } label: {
                    Label { Text("Choose File…") } icon: {
                        VaultIcon(Icons.importData, size: Metric.iconInline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
                .disabled(working)
            } footer: {
                Text("Supports CSV exports and Loox encrypted backups (.vaultify).")
            }
            .listRowBackground(VaultColors.surface)

            if let encryptedData {
                Section("Encrypted backup") {
                    RevealableSecureField(title: "Backup password", text: $passphrase, inList: true)
                    // The primary for this state: the preview (and its Import
                    // primary) only exists once the backup is open.
                    Button { startDecrypt(encryptedData) } label: {
                        Text("Decrypt").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .disabled(passphrase.isEmpty || working)
                }
                .listRowBackground(VaultColors.surface)
            }

            // Opening a backup runs a deliberately slow key derivation, and
            // reading a large file is not instant either. Without this the only
            // way out of a long wait is to kill the app.
            if working {
                Section {
                    Button(role: .cancel) { cancelWork() } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedTinted)
                }
                .listRowBackground(VaultColors.surface)
            }

            if !parsed.isEmpty || !parsedPasskeys.isEmpty {
                Section("Preview (\(parsed.count + parsedPasskeys.count))") {
                    ForEach(parsed.prefix(6)) { VaultItemRow(item: $0.item) }
                    if parsed.count > 6 { Text("and \(parsed.count - 6) more…").vaultType(.footnote).themedForeground(.secondary) }
                    if !parsedPasskeys.isEmpty {
                        Label {
                            Text("\(parsedPasskeys.count) passkeys")
                        } icon: {
                            VaultIcon(Icons.passkey)
                        }
                    }
                }
                .listRowBackground(VaultColors.surface)

                if let warning = pendingLevel2Warning {
                    Section {
                        VaultInfoBanner(.warning, icon: Icons.alert,
                                        title: "Protected values may stay locked",
                                        text: warning.message)
                            .inList()
                    }
                }

                Section {
                    Button { performImport() } label: {
                        Text("Import \(parsed.count + parsedPasskeys.count) Records").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .disabled(working)
                }
                .listRowBackground(VaultColors.surface)
            }

            if let report { reportSection(report) }

            if let error {
                Section {
                    VaultInfoBanner(.error, verbatimText: error).inList()
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("Import")
        .platformNavigationBarTitleDisplayMode(.inline)
        // Non-interactive on purpose: the Cancel row below has to stay reachable
        // through it.
        .overlay { if working { ProgressView().controlSize(.large).allowsHitTesting(false) } }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .json, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            handle(result)
        }
        .confirmationDialog("Import anyway?", isPresented: $confirmStranding,
                            titleVisibility: .visible) {
            Button("Import Anyway") { commitImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let warning = pendingLevel2Warning { Text(warning.message) }
        }
        .onDisappear {
            loadTask?.cancel()
            decryptTask?.cancel()
        }
    }

    // MARK: Result

    @ViewBuilder
    private func reportSection(_ report: ImportReport) -> some View {
        Section {
            resultRow("Items", imported: report.itemsImported, total: report.itemsTotal)
            if report.foldersCreated > 0 {
                resultRow("Spaces created", imported: report.foldersCreated,
                          total: report.foldersCreated)
            }
            if report.artifactsTotal > 0 {
                resultRow("Attachments", imported: report.artifactsImported,
                          total: report.artifactsTotal)
            }
            if report.passkeysTotal > 0 {
                resultRow("Passkeys", imported: report.passkeysImported,
                          total: report.passkeysTotal)
            }
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        } header: {
            Text("Import result")
        }
        .listRowBackground(VaultColors.surface)

        if let warning = report.level2Warning {
            Section {
                VaultInfoBanner(.warning, icon: Icons.alert,
                                title: "Protected values may stay locked",
                                text: warning.message)
                    .inList()
            }
        }
    }

    /// "3 of 5" whenever a category came up short, a plain count when it did
    /// not. A bare number next to a partial restore would read as success.
    @ViewBuilder
    private func resultRow(_ title: LocalizedStringKey, imported: Int, total: Int) -> some View {
        HStack {
            Text(title).vaultType(.body)
            Spacer(minLength: Space.s3)
            if imported == total {
                Text(imported, format: .number)
                    .vaultType(.body).themedForeground(.secondary)
            } else {
                Text("\(imported) of \(total)")
                    .vaultType(.body)
                    .foregroundStyle(env.theme.active.color(.warning))
            }
        }
    }

    // MARK: File intake

    private func handle(_ result: Result<[URL], Error>) {
        resetParsedState()
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(failure) = result {
                error = failure.localizedDescription
                Haptics.error()
            }
            return
        }
        loadTask?.cancel()
        working = true
        loadTask = Task { await load(url) }
    }

    private func load(_ url: URL) async {
        // Both the security-scoped bracket and the read happen on the same
        // background executor: `Task.detached` is the only form that leaves the
        // main actor under approachable concurrency, where a plain `nonisolated`
        // async call would run right back on the caller.
        let outcome = await Task.detached(priority: .userInitiated) { () -> ImportProbe.Outcome in
            guard url.startAccessingSecurityScopedResource() else { return .unreadable }
            defer { url.stopAccessingSecurityScopedResource() }
            return ImportProbe.read(url)
        }.value
        guard !Task.isCancelled else { return }
        working = false
        loadTask = nil
        apply(outcome)
    }

    private func apply(_ outcome: ImportProbe.Outcome) {
        switch outcome {
        case let .encrypted(data):
            encryptedData = data
        case let .rows(rows):
            parsed = rows
            sealedFieldCount = Self.sealedFieldCount(in: rows)
        case .tooLarge:
            fail(appString("This file is too large to import safely."))
        case .unreadable:
            fail(appString("Couldn’t read the file."))
        case .damaged:
            fail(ImportFailureMessage.damaged)
        case .emptyCSV:
            fail(appString("No items found in that file."))
        case .unsupported:
            fail(appString("Unsupported file format."))
        case .tooManyRecords:
            fail(appString("This file holds more records than one import can restore safely."))
        }
    }

    private func fail(_ message: String) {
        error = message
        Haptics.error()
    }

    // MARK: Decrypt

    private func startDecrypt(_ data: Data) {
        decryptTask?.cancel()
        working = true
        error = nil
        report = nil
        decryptTask = Task { await decrypt(data) }
    }

    private func decrypt(_ data: Data) async {
        do {
            let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)
            guard !Task.isCancelled else { return }
            guard ImportLimits.fits(items: imported.items.count,
                                    passkeys: imported.passkeys.count,
                                    artifacts: imported.artifacts.count) else {
                fail(appString("This file holds more records than one import can restore safely."))
                working = false
                decryptTask = nil
                return
            }
            let rows = imported.items.map { ParsedImportRow(item: $0.item, folderName: $0.folderName) }
            parsed = rows
            parsedPasskeys = imported.passkeys
            parsedLevel2 = imported.level2
            parsedArtifacts = imported.artifacts
            sealedFieldCount = Self.sealedFieldCount(in: rows)
            // The adoption decision is made from this device's own key bundle,
            // so it is knowable now — long before anything is written — and the
            // user can be warned while cancelling still costs nothing.
            level2Prediction = imported.level2.map {
                VaultSession.level2Adoption(for: VaultKeyBundle.load(),
                                            wrappedL2SK: $0.wrappedL2SK, salt: $0.salt, kdf: $0.kdf)
            }
            encryptedData = nil
            passphrase = ""
            if parsed.isEmpty && parsedPasskeys.isEmpty {
                fail(appString("Backup contained no records."))
            }
        } catch {
            guard !Task.isCancelled else { return }
            fail(ImportFailureMessage.text(for: error))
        }
        working = false
        decryptTask = nil
    }

    /// Cancelling returns the screen, not the CPU: Argon2 runs in vendored C
    /// with no cancellation points, so the derivation already under way finishes
    /// on its own and its result is discarded.
    private func cancelWork() {
        loadTask?.cancel()
        loadTask = nil
        decryptTask?.cancel()
        decryptTask = nil
        working = false
    }

    private func resetParsedState() {
        error = nil
        report = nil
        parsed = []
        parsedPasskeys = []
        parsedArtifacts = []
        parsedLevel2 = nil
        level2Prediction = nil
        sealedFieldCount = 0
        encryptedData = nil
    }

    // MARK: Import

    private var pendingLevel2Warning: Level2ImportWarning? {
        Level2ImportWarning.evaluate(sealedFieldCount: sealedFieldCount,
                                     hasWrap: parsedLevel2 != nil,
                                     adoption: level2Prediction)
    }

    private static func sealedFieldCount(in rows: [ParsedImportRow]) -> Int {
        rows.reduce(0) { total, row in
            total + row.item.fields.reduce(0) { $0 + ($1.isExtraProtected ? 1 : 0) }
        }
    }

    private func performImport() {
        error = nil
        report = nil
        guard parsedPasskeys.isEmpty || env.session.vaultKey != nil else {
            fail(appString("Unlock your vault before importing passkeys."))
            return
        }
        // Stranding is permanent and undoable (turning Extra Protection off
        // needs the password the wrap belongs to), so it is not something to
        // discover in a result screen.
        guard pendingLevel2Warning == nil else {
            confirmStranding = true
            return
        }
        commitImport()
    }

    private func commitImport() {
        var result = ImportReport()
        result.itemsTotal = parsed.count
        result.artifactsTotal = parsedArtifacts.count
        result.passkeysTotal = parsedPasskeys.count
        result.sealedFieldCount = sealedFieldCount
        result.hasLevel2Wrap = parsedLevel2 != nil

        // 1. Level-2 FIRST. Its outcome decides whether every sealed value in
        //    this payload will ever open again, and that has to be known before
        //    a single item is written.
        if let level2 = parsedLevel2 {
            result.level2 = env.session.adoptLevel2WrapIfAbsent(
                wrappedL2SK: level2.wrappedL2SK, salt: level2.salt, kdf: level2.kdf)
        }

        var folderCache: [String: String] = [:]   // lowercased name → folder id
        var foldersCreated = 0
        var itemsImported = 0
        var artifactsImported = 0
        var itemsFailed = false
        // Bulk: one vault_imported summary below, never per-item events.
        AnalyticsEngine.shared.runSuppressed {
            // 2. Items (and the Spaces they name). Rows the repository would
            //    drop are filtered here instead, so they can be counted rather
            //    than vanishing inside a bulk insert that reports nothing.
            var eligible: [VaultItem] = []
            for row in parsed {
                var item = row.item
                guard item.sharedOrigin == nil, !item.id.hasPrefix("shared::") else { continue }
                if let name = row.folderName, !name.isEmpty {
                    item.folderId = resolveFolder(name, cache: &folderCache, created: &foldersCreated)
                }
                eligible.append(item)
            }
            do {
                try env.repository.addAll(eligible)
                itemsImported = eligible.count
            } catch {
                // A throw from the bulk insert can leave records inserted into
                // the context but unsaved. Every later step here saves the same
                // context, so stopping is what keeps a failed item pass from
                // being committed by an artifact or passkey write.
                itemsFailed = true
                return
            }
            // 3. Artifacts. `restoreAll` is all-or-nothing inside the store, so
            //    this is genuinely "all of them or none of them".
            guard !parsedArtifacts.isEmpty else { return }
            do {
                try env.artifactStore.restoreAll(parsedArtifacts)
                artifactsImported = parsedArtifacts.count
            } catch {
                artifactsImported = 0
            }
        }
        result.foldersCreated = foldersCreated
        result.itemsImported = itemsImported
        result.artifactsImported = artifactsImported

        // 4. Passkeys, one at a time: one bad credential must not cost the rest.
        if !itemsFailed, !parsedPasskeys.isEmpty, let key = env.session.vaultKey {
            let vault = PasskeyVault(store: env.store)
            for passkey in parsedPasskeys {
                if (try? vault.save(passkey, key: key)) != nil { result.passkeysImported += 1 }
            }
            env.repository.reload()
            // A passkey-only restore has no item add to schedule the debounced
            // push for it — imported credentials should reach CloudKit without
            // waiting for the next foreground sync.
            env.repository.noteLocalMutation()
        }

        // The payload is spent. Clearing it drops the preview and its Import
        // button, which would otherwise re-insert everything that just landed,
        // and releases the artifact plaintexts this screen was holding.
        parsed = []
        parsedPasskeys = []
        parsedArtifacts = []
        parsedLevel2 = nil
        level2Prediction = nil
        sealedFieldCount = 0
        encryptedData = nil

        AnalyticsEngine.shared.log(.vaultImported(
            countBucket: AnalyticsBucket.count(result.recordsImported)))
        if result.isComplete {
            Haptics.success()
            dismiss()
        } else {
            // Everything that DID land stays; the screen now says exactly what
            // did not, instead of dismissing on a half-restored vault.
            report = result
            Haptics.warning()
        }
    }

    /// Match a folder by name (case-insensitive), creating it if it doesn't exist.
    private func resolveFolder(_ name: String, cache: inout [String: String],
                               created: inout Int) -> String? {
        let key = name.lowercased()
        if let id = cache[key] { return id }
        if let existing = env.repository.folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            cache[key] = existing.id
            return existing.id
        }
        if let id = try? env.repository.addFolder(name: name, icon: "ic_folder", color: .blue) {
            cache[key] = id
            created += 1
            return id
        }
        return nil
    }
}
