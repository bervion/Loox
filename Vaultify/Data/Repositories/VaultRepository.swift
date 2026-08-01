import Foundation
import SwiftData
import UserNotifications

/// Decrypts vault records into an in-memory cache on unlock and performs CRUD,
/// re-sealing payloads under the Vault Key. The cache is cleared on lock.
@MainActor @Observable final class VaultRepository {
    // Internal (not private) so the `+Folders` extension in a sibling file can
    // reach the store/session; the item seal/decrypt helpers stay private.
    let store: VaultStore
    let session: VaultSession
    /// False for deterministic UI/snapshot composition so repository mutations
    /// cannot reach credential identities, shared containers or notifications.
    private let externalSideEffectsEnabled: Bool

    private(set) var items: [VaultItem] = []
    private(set) var trashed: [VaultItem] = []
    private(set) var archived: [VaultItem] = []
    private(set) var folders: [Folder] = []
    private(set) var passkeys: [PasskeyInfo] = []
    private(set) var personas: [Persona] = []
    private(set) var aliases: [EmailAlias] = []
    /// Internal(set) — `ensureProfileInboxes` (extension) patches it in place
    /// during reload, the same "never reload() from within reload" rule the
    /// persona helpers follow.
    var forwardingInboxes: [ForwardingInbox] = []

    init(
        store: VaultStore,
        session: VaultSession,
        externalSideEffectsEnabled: Bool = true
    ) {
        self.store = store
        self.session = session
        self.externalSideEffectsEnabled = externalSideEffectsEnabled
    }

    var isEmpty: Bool { items.isEmpty && trashed.isEmpty && archived.isEmpty }

    func clear() {
        items = []
        trashed = []
        archived = []
        folders = []
        passkeys = []
        personas = []
        aliases = []
        forwardingInboxes = []
        if externalSideEffectsEnabled {
            CredentialIdentityService.clear()
        }
    }

    /// Load and decrypt all live records into the in-memory caches.
    func reload() {
        guard let key = session.vaultKey else { clear(); return }
        let descriptor = FetchDescriptor<ItemRecord>(
            predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return }
        var active: [VaultItem] = []
        var trash: [VaultItem] = []
        var arch: [VaultItem] = []
        for record in records {
            guard let item = try? decrypt(record, key: key) else { continue }
            // Trash wins over archive when an item is both; archived items stay out
            // of every normal surface but remain reachable in the Archive screen.
            if item.isTrashed { trash.append(item) }
            else if item.archived { arch.append(item) }
            else { active.append(item) }
        }
        items = active.sorted { $0.updatedAt > $1.updatedAt }
        trashed = trash.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
        archived = arch.sorted { $0.updatedAt > $1.updatedAt }
        folders = loadFolders(key: key)
        let passkeyVault = PasskeyVault(store: store)
        let migration = passkeyVault.prepareEnvelopeOnUnlock(key: key)
        if !migration.quarantinedSites.isEmpty {
            SharedConfig.queuePasskeyQuarantineNotice(sites: migration.quarantinedSites)
        }
        passkeys = passkeyVault.all(key: key)
        if externalSideEffectsEnabled {
            CredentialIdentityService.refresh(items: items, passkeys: passkeys)
        }
        normalizeDefaultIdentity()
        // Seed-folder convergence runs ONLY after a remote pull: two locally-created
        // identical-looking folders are a deliberate user choice, but the same pair
        // arriving via sync is the two-device double-seed to converge.
        if pendingSeedFolderMerge {
            pendingSeedFolderMerge = false
            mergeDuplicateSeedFolders(key: key)
        }
        // Personas load AFTER folders + identity so the seed can link the default
        // identity + primary Space. Both helpers patch state in place — never reload().
        personas = loadPersonas(key: key)
        ensurePersonaExists(key: key)
        normalizeDefaultPersona()
        migratePartition(key: key)
        mirrorActivePersonaContext()
        aliases = loadAliases(key: key)
        // Inboxes load after personas + items so profile-email derivation sees
        // the persona's card; derivation patches the cache in place.
        forwardingInboxes = loadInboxes(key: key)
        ensureProfileInboxes(key: key)
    }

    /// Reload after a CloudKit pull — same as `reload()` plus the duplicate
    /// seed-folder convergence pass (see above). Used by the sync callback.
    func reloadAfterRemoteSync() {
        pendingSeedFolderMerge = true
        reload()
    }

    private var pendingSeedFolderMerge = false

    /// Signal that local vault data changed so the sync coordinator can schedule a
    /// debounced push. Internal so the `+Folders` extension can post it too.
    func noteLocalMutation() {
        NotificationCenter.default.post(name: .vaultLocalMutation, object: nil)
    }

    // MARK: Duplicate seed-folder convergence

    /// Two devices that each ran first-run onboarding both seed a first Space with
    /// fresh UUIDs; merging vaults by record id leaves BOTH folders. Converge: among
    /// duplicates carrying an untouched seed signature (ANY historical localized seed
    /// name + seed icon + seed color — the name set spans languages and copy renames,
    /// because the stored name froze at seed time in the then-active language, while
    /// icon + color stay deliberately narrow so a user's own identical-looking folders
    /// are never collapsed), keep the earliest-created, re-point the losers' items at
    /// it (re-sealed, `updatedAt` bumped so the move propagates), and tombstone the
    /// losers. Patches the freshly-built in-memory state in place — never `reload()`.
    private func mergeDuplicateSeedFolders(key: SecureBytes) {
        guard folders.count > 1 else { return }
        // Sentinel a TextField value can never equal (NUL byte), so a user-named
        // folder can't collide with the folded seed-name group.
        let seedNameKey = "\u{0}seed"
        // Icon parts go through `SeedSpaceIcon.dedupeKey`, which folds every
        // spelling a shipped seed ever stored — `ic_lock_filled` (via
        // `canonical`) and the SF-era `sf:lock.fill` — so stores seeded by any
        // build match without rewriting bytes.
        let seedSignature = "\(seedNameKey)|\(SeedSpaceIcon.dedupeKey(IconCatalog.seedSpaceIcon))|\(FolderColor.blue.rawValue)"
        let groups = Dictionary(grouping: folders) {
            let namePart = SeedSpaceName.isSeedName($0.name) ? seedNameKey : $0.name
            return "\(namePart)|\(SeedSpaceIcon.dedupeKey($0.iconAsset))|\($0.color.rawValue)"
        }
        var loserIds: Set<String> = []
        for (signature, group) in groups where group.count > 1 && signature == seedSignature {
            let ordered = group.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            guard let winner = ordered.first else { continue }
            for loser in ordered.dropFirst() {
                repointItems(fromFolder: loser.id, to: winner.id, key: key)
                if let record = store.folderRecord(id: loser.id) {
                    record.deletedAt = .now
                    record.updatedAt = .now
                    record.dirty = true
                }
                loserIds.insert(loser.id)
            }
        }
        guard !loserIds.isEmpty else { return }
        folders.removeAll { loserIds.contains($0.id) }
        try? store.context.save()
        noteLocalMutation()
    }

    /// Re-seal every cached item filed under `fromFolder` with `to` as its folder.
    /// Covers active, trashed, and archived caches (all carry `folderId`).
    private func repointItems(fromFolder: String, to winnerId: String, key: SecureBytes) {
        func repoint(_ cache: inout [VaultItem]) {
            for index in cache.indices where cache[index].folderId == fromFolder {
                cache[index].folderId = winnerId
                cache[index].updatedAt = .now
                guard let record = store.record(id: cache[index].id),
                      let sealed = try? seal(cache[index], key: key) else { continue }
                record.sealed = sealed
                record.updatedAt = cache[index].updatedAt
                record.dirty = true
            }
        }
        repoint(&items)
        repoint(&trashed)
        repoint(&archived)
    }

    // MARK: Default identity (single-active invariant)

    /// Ensure exactly one ACTIVE identity carries the default marker. Converges sync
    /// conflicts (two devices each picked a default → a transient double-default) and
    /// promotes a replacement when the old default leaves the active set. Runs at the
    /// tail of `reload()`; writes only when the active identities are inconsistent and
    /// **never calls `reload()`** (it patches the freshly-built `items` in place).
    private func normalizeDefaultIdentity() {
        let identities = items.filter { $0.category == .identity }
        guard !identities.isEmpty else { return }
        guard identities.filter(\.isDefaultIdentity).count != 1 else { return }
        // Winner = most recently touched (`updatedAt`), `createdAt` as the final tiebreak.
        guard let winner = identities.max(by: {
            ($0.updatedAt, $0.createdAt) < ($1.updatedAt, $1.createdAt)
        }) else { return }
        let now = Date()
        var didWrite = false
        for identity in identities {
            let shouldBeDefault = identity.id == winner.id
            guard identity.isDefaultIdentity != shouldBeDefault else { continue }
            writeIdentityDefault(id: identity.id, isDefault: shouldBeDefault, now: now)
            if let idx = items.firstIndex(where: { $0.id == identity.id }) {
                items[idx].isDefaultIdentity = shouldBeDefault
                items[idx].updatedAt = now
            }
            didWrite = true
        }
        if didWrite { try? store.context.save() }
    }

    /// Set the default-identity marker on a record and bump `updatedAt` so the change
    /// propagates through the whole-record LWW CloudKit sync (a column-only write is
    /// dropped on pull). Marks the record dirty. Caller is responsible for save + reload.
    /// Internal so the `+Identity` extension can drive `setDefaultIdentity`.
    func writeIdentityDefault(id: String, isDefault: Bool, now: Date) {
        guard let record = store.record(id: id) else { return }
        record.isDefaultIdentity = isDefault
        record.updatedAt = now
        record.dirty = true
    }

    // MARK: Persona invariants (run at the tail of reload(); patch in place)

    /// Seed the bootstrap Personal persona when none exists — covers both a fresh
    /// install and an existing vault upgrading to personas. Idempotent and
    /// multi-device-safe: the fixed bootstrap id means two devices seeding offline
    /// collide on one record (sync LWW merges them, no duplicate-merge pass needed).
    /// Links the current default identity + primary Space. Patches `personas` in
    /// place and never calls `reload()` (mirrors `normalizeDefaultIdentity`).
    func ensurePersonaExists(key: SecureBytes) {
        guard personas.isEmpty else { return }
        let now = Date()
        let persona = Persona(id: Persona.bootstrapPersonalID,
                              displayName: appString("Personal"),
                              kind: .personal,
                              primaryProfileItemID: defaultIdentity?.id,
                              primarySpaceID: folders.first?.id,
                              isDefault: true,
                              createdAt: now, updatedAt: now)
        guard let sealed = try? sealPersona(persona, key: key) else { return }
        let record = PersonaRecord(id: persona.id, sealed: sealed, isDefault: true,
                                   sortIndex: 0, createdAt: now, updatedAt: now)
        store.context.insert(record)
        try? store.context.save()
        personas = [persona]
        noteLocalMutation()
    }

    /// Converge to exactly one default persona (sync can transiently produce zero
    /// or two; winner = most recently touched). Carries `isDefault` in the content
    /// gate (bumps `updatedAt`) so the change survives the whole-record LWW pull.
    /// Patches `personas` in place; never `reload()`.
    func normalizeDefaultPersona() {
        guard !personas.isEmpty else { return }
        guard personas.filter(\.isDefault).count != 1 else { return }
        guard let winner = personas.max(by: {
            ($0.updatedAt, $0.createdAt) < ($1.updatedAt, $1.createdAt)
        }) else { return }
        let now = Date()
        var didWrite = false
        for persona in personas {
            let shouldBeDefault = persona.id == winner.id
            guard persona.isDefault != shouldBeDefault else { continue }
            writePersonaDefault(id: persona.id, isDefault: shouldBeDefault, now: now)
            if let idx = personas.firstIndex(where: { $0.id == persona.id }) {
                personas[idx].isDefault = shouldBeDefault
                personas[idx].updatedAt = now
            }
            didWrite = true
        }
        if didWrite { try? store.context.save() }
    }

    /// Set the default marker on a persona record + bump `updatedAt` (content-gate)
    /// so the converged default propagates through whole-record LWW. Marks dirty.
    /// Internal so the `+Personas` extension can drive `setDefaultPersona`.
    func writePersonaDefault(id: String, isDefault: Bool, now: Date) {
        guard let record = store.personaRecord(id: id) else { return }
        record.isDefault = isDefault
        record.updatedAt = now
        record.dirty = true
    }

    /// Populate the persona↔Space partition in place (never `reload()`). Backfills
    /// any Space with no owner to the default persona, and repoints a persona's
    /// `primarySpaceID` that dangles into a Space it doesn't own (the pre-partition
    /// leak where `addPersona` seeded `folders.first`). Idempotent — writes only on
    /// real change; re-seals bump `updatedAt` so ownership rides whole-record LWW.
    private func migratePartition(key: SecureBytes) {
        guard let defaultID = defaultPersona?.id else { return }
        var didWrite = false

        // F1: backfill unowned Spaces → default persona.
        for index in folders.indices where folders[index].personaId == nil {
            var updated = folders[index]
            updated.personaId = defaultID
            updated.updatedAt = .now
            guard let record = store.folderRecord(id: updated.id),
                  let sealed = try? sealFolder(updated, key: key) else { continue }
            record.sealed = sealed
            record.updatedAt = updated.updatedAt
            record.dirty = true
            folders[index] = updated
            didWrite = true
        }

        // F2: reconcile a primarySpaceID that points at a Space the persona doesn't own.
        for index in personas.indices {
            let persona = personas[index]
            guard let sid = persona.primarySpaceID else { continue }
            let ownerOfPrimary = folders.first { $0.id == sid }?.personaId ?? defaultID
            guard ownerOfPrimary != persona.id else { continue }
            let newPrimary = folders.first { ($0.personaId ?? defaultID) == persona.id }?.id
            var updated = persona
            updated.primarySpaceID = newPrimary
            updated.updatedAt = .now
            guard let record = store.personaRecord(id: persona.id),
                  let sealed = try? sealPersona(updated, key: key) else { continue }
            record.sealed = sealed
            record.updatedAt = updated.updatedAt
            record.dirty = true
            personas[index] = updated
            didWrite = true
        }

        // F3: link a persona with no (or a dangling) profile card to the first
        // identity item IT OWNS — covers personas created before profile cards
        // existed and a card later added by hand from Profile. Never a write when
        // no owned candidate exists (no churn), never a cross-persona link.
        for index in personas.indices {
            let persona = personas[index]
            guard profileItem(for: persona) == nil,
                  let candidate = items(for: persona).first(where: { $0.category == .identity })
            else { continue }
            var updated = persona
            updated.primaryProfileItemID = candidate.id
            updated.updatedAt = .now
            guard let record = store.personaRecord(id: persona.id),
                  let sealed = try? sealPersona(updated, key: key) else { continue }
            record.sealed = sealed
            record.updatedAt = updated.updatedAt
            record.dirty = true
            personas[index] = updated
            didWrite = true
        }

        if didWrite {
            try? store.context.save()
            noteLocalMutation()
        }
    }

    /// Mirror the active persona's isolation policy + profile item id + Space
    /// context into the App Group so the AutoFill extension (which can't read the
    /// app's local `activePersonaID` / `SettingsStore`) honors isolation and defaults
    /// a newly saved login into the right Space. Only opaque ids/flags cross over —
    /// no identity-bearing plaintext; the extension resolves names under the Vault
    /// Key. Called on every reload, every active-persona switch, AND every Home
    /// Space selection change (see `HomeScreen`'s `onChange(of: selectedFolderId)`).
    func mirrorActivePersonaContext() {
        guard externalSideEffectsEnabled else { return }
        let defaults = SharedConfig.sharedDefaults
        let persona = activePersona
        defaults.set(persona?.isolationPolicy.rawValue, forKey: SharedConfig.activePersonaPolicyKey)
        defaults.set(persona?.primaryProfileItemID, forKey: SharedConfig.activePersonaProfileItemKey)
        defaults.set(persona?.id, forKey: SharedConfig.activePersonaIdKey)
        defaults.set(persona?.isDefault ?? false, forKey: SharedConfig.activePersonaIsDefaultKey)
        defaults.set(persona?.primarySpaceID, forKey: SharedConfig.activePersonaPrimarySpaceKey)
        let lastSpace = persona.flatMap { session.settings.lastSelectedSpace(persona: $0.id) }
        defaults.set(lastSpace, forKey: SharedConfig.activePersonaLastSpaceKey)
    }

    // MARK: CRUD

    func add(_ item: VaultItem) throws {
        // A shared projection must NEVER be persisted: it is someone else's
        // data, sealed under their trust — storing it would sync/back it up
        // as owned and outlive revocation (V1.2 review C1, defense in depth
        // behind the UI gates).
        guard item.sharedOrigin == nil, !item.id.hasPrefix("shared::") else { return }
        guard let key = session.vaultKey else { throw AuthError.locked }
        let record = ItemRecord(id: item.id,
                                sealed: try seal(item, key: key),
                                favorite: item.favorite,
                                createdAt: item.createdAt,
                                updatedAt: item.updatedAt,
                                trashedAt: item.trashedAt)
        record.pinned = item.pinned
        record.archived = item.archived
        record.useCount = item.useCount
        record.isDefaultIdentity = item.isDefaultIdentity
        record.rotateDays = item.rotateDays
        // New items: baseline is createdAt (caller provides it).
        record.passwordChangedAt = item.createdAt
        store.context.insert(record)
        try store.context.save()
        reload()
        noteLocalMutation()
        AnalyticsEngine.shared.log(.itemCreated(item.category))
        if externalSideEffectsEnabled,
           SettingsStore.isRotationRemindersEnabled() {
            RotationNotificationService.shared.schedule(item: item, passwordChangedAt: record.passwordChangedAt)
        }
    }

    func update(_ item: VaultItem) throws {
        // Same guard as `add` — the missing-record fallback below upserts.
        guard item.sharedOrigin == nil, !item.id.hasPrefix("shared::") else { return }
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = try record(id: item.id) else { return try add(item) }
        var updated = item
        updated.updatedAt = .now

        // Detect a real password change by comparing decrypted old password to new.
        // We re-seal regardless; the comparison is purely for the timestamp.
        let oldPassword = passwordValue(for: record, key: key)
        let newPassword = item.passwordField?.value

        record.sealed = try seal(updated, key: key)
        record.favorite = updated.favorite
        record.trashedAt = updated.trashedAt
        record.updatedAt = updated.updatedAt
        record.rotateDays = updated.rotateDays
        record.dirty = true

        if oldPassword != newPassword {
            // Password value changed — reset the baseline so rotation tracking is accurate.
            record.passwordChangedAt = .now
        }

        try store.context.save()
        reload()
        noteLocalMutation()
        AnalyticsEngine.shared.log(.itemUpdated(item.category))
        if externalSideEffectsEnabled,
           SettingsStore.isRotationRemindersEnabled() {
            RotationNotificationService.shared.schedule(
                item: updated, passwordChangedAt: record.passwordChangedAt)
        }
    }

    func toggleFavorite(_ item: VaultItem) throws {
        var updated = item
        updated.favorite.toggle()
        try update(updated)
    }

    /// Pin/unpin (Home "Pinned"). Column-only — no re-seal, no `updatedAt` bump,
    /// so it never pollutes "Recently Modified".
    func togglePin(_ item: VaultItem) { setColumn(item.id) { $0.pinned.toggle() } }

    /// Archive / unarchive — keeps the item out of normal lists without deleting
    /// it. Same column-only contract as pin.
    func archive(_ item: VaultItem) { setColumn(item.id) { $0.archived = true } }
    func unarchive(_ item: VaultItem) { setColumn(item.id) { $0.archived = false } }

    /// Mutate a plaintext metadata column, mark dirty for sync, and reload —
    /// without re-sealing or bumping `updatedAt` (keeps "Recently Modified" clean).
    /// Bumps `metaUpdatedAt` instead: the pull merge applies pinned/archived by that
    /// separate timestamp, so column-only toggles still propagate across devices.
    private func setColumn(_ id: String, _ mutate: (ItemRecord) -> Void) {
        guard let record = store.record(id: id) else { return }
        mutate(record)
        record.metaUpdatedAt = .now
        record.dirty = true
        try? store.context.save()
        reload()
        noteLocalMutation()
    }

    /// Record an in-app use (copy/reveal) for Recents + Frequently Used. Writes
    /// only the plaintext `lastUsedAt`/`useCount` columns — no re-seal, no
    /// `dirty`, no `reload()` — and patches the in-memory cache in place.
    func markUsed(_ item: VaultItem) {
        guard let record = store.record(id: item.id) else { return }
        record.lastUsedAt = .now
        record.useCount += 1
        try? store.context.save()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].lastUsedAt = record.lastUsedAt
            items[idx].useCount = record.useCount
        }
    }

    func moveToTrash(_ item: VaultItem) throws {
        var updated = item
        updated.trashedAt = .now
        try update(updated)
        if externalSideEffectsEnabled {
            RotationNotificationService.shared.cancel(itemID: item.id)
        }
    }

    func restore(_ item: VaultItem) throws {
        var updated = item
        updated.trashedAt = nil
        try update(updated)
    }

    /// Soft-delete (tombstone) so sync can propagate the deletion. Bumps `updatedAt` —
    /// the pull merge gates on it, so a tombstone that doesn't bump would be dropped on
    /// the other device and a later edit there would resurrect the "deleted" secret.
    func delete(_ item: VaultItem) throws {
        guard let record = try record(id: item.id) else { return }
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
        noteLocalMutation()
        AnalyticsEngine.shared.log(.itemDeleted(item.category))
        if externalSideEffectsEnabled {
            RotationNotificationService.shared.cancel(itemID: item.id)
        }
    }

    func deletePasskey(credentialID: Data) throws {
        try PasskeyVault(store: store).delete(credentialID: credentialID)
        reload()
        // The tombstone must reach CloudKit promptly, like every other vault
        // mutation — not wait for the next foreground sync.
        noteLocalMutation()
    }

    // Needs-Attention assembly lives in `HomeAttention.entries` (Home feature) —
    // it folds in reuse and leak signals the repository cannot know.

    func emptyTrash() throws {
        for item in trashed { try delete(item) }
    }

    // MARK: Sealing

    private func seal(_ item: VaultItem, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(item.secret), key: key)
    }

    private func decrypt(_ record: ItemRecord, key: SecureBytes) throws -> VaultItem {
        let plaintext = try AESGCM.open(record.sealed, key: key)
        let secret = try JSONDecoder().decode(ItemSecret.self, from: plaintext)
        return VaultItem(id: record.id,
                         category: secret.category,
                         title: secret.title,
                         folderId: secret.folderId,
                         fields: secret.fields,
                         favorite: record.favorite,
                         tags: secret.tags,
                         iconAsset: secret.iconAsset,
                         lastUsedAt: record.lastUsedAt,
                         pinned: record.pinned,
                         archived: record.archived,
                         useCount: record.useCount,
                         isDefaultIdentity: record.isDefaultIdentity,
                         rotateDays: record.rotateDays,
                         passwordChangedAt: record.passwordChangedAt,
                         createdAt: record.createdAt,
                         updatedAt: record.updatedAt,
                         trashedAt: record.trashedAt)
    }

    /// Unseal the record and return just the password field value. Returns nil
    /// on any error (key mismatch, missing field). Used only to detect actual
    /// password changes without a separate decrypt path.
    private func passwordValue(for record: ItemRecord, key: SecureBytes) -> String? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        return secret.fields.first { $0.kind == .password }?.value
    }

    private func record(id: String) throws -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try store.context.fetch(descriptor).first
    }
}

extension Notification.Name {
    /// Posted after any local vault mutation so the sync coordinator can schedule a
    /// debounced push (see `SyncCoordinator`).
    static let vaultLocalMutation = Notification.Name("vaultLocalMutation")
}
