import CloudKit
import Foundation

/// Single source of truth for assembling and publishing an Approval-Mode grant
/// (fields + passkeys + device scope + display envelope). Both the create
/// ceremony (`ShareAccessSheet`) and the edit sheet (`ShareRecipientDetailSheet`)
/// publish THROUGH here, so passkey and device-scope handling can never drift —
/// the class of bug where the edit path silently dropped passkeys and downgraded
/// single-device to multi.
enum SharedGrantComposer {
    /// Recipient identity material the grant seals to (subset of the published
    /// participant profile).
    struct RecipientProfile {
        let participantPubKey: Data
        let deviceSigningKeys: [Data]
        let deviceHPKEDirectory: [DeviceHPKEDirectoryEntry]
    }

    enum ComposeError: LocalizedError {
        case singleDeviceUnavailable
        /// A granted passkey's key material couldn't be resolved at publish
        /// time (vault key momentarily unavailable, or the stored credential
        /// failed to decode). Publishing anyway would hand the recipient a
        /// signed grant that NAMES a passkey with no display metadata or
        /// sealed key behind it — the silent way shares lose passkeys — so
        /// the ceremony fails loudly and stays retryable.
        case passkeyMaterialUnavailable

        var errorDescription: String? {
            switch self {
            case .singleDeviceUnavailable:
                return appString("Single-device sharing needs the recipient to update Loox first.")
            case .passkeyMaterialUnavailable:
                return appString("The passkey couldn't be prepared for sharing. Lock the app, unlock it, then try again.")
            }
        }
    }

    // MARK: Pure mapping (unit-tested; no IO)

    /// Which recipient devices a single-device grant seals to — the
    /// first-enrolled device, deterministically. Multi-device seals to none
    /// (the participant key). An empty directory under single-device is an
    /// error (never silently widen to multi — INV-04).
    nonisolated static func allowedDevices(
        scope: DeviceScope, directory: [DeviceHPKEDirectoryEntry]
    ) throws -> [DeviceHPKEDirectoryEntry] {
        guard scope == .single else { return [] }
        guard let first = directory.min(by: {
            ($0.addedAtUnixMs, $0.deviceKeyID.hexString)
                < ($1.addedAtUnixMs, $1.deviceKeyID.hexString)
        }) else { throw ComposeError.singleDeviceUnavailable }
        return [first]
    }

    /// Passkey display metadata (every granted mode — the recipient renders +
    /// registers QuickType from it) and hand-over sealed blobs (mode `.shared`
    /// only — INV-07/08), from resolved secrets + the chosen capabilities.
    nonisolated static func passkeyArtifacts(
        secretsBySlot: [(slot: String, secret: PasskeySecret)],
        capabilities: [String: FieldCapability]
    ) -> (display: [SharedDisplayEnvelope.PasskeyMeta], shared: [String: Data]) {
        var display: [SharedDisplayEnvelope.PasskeyMeta] = []
        var shared: [String: Data] = [:]
        for (slot, secret) in secretsBySlot {
            guard case .passkey(let mode)? = capabilities[slot], mode != .none else { continue }
            display.append(SharedDisplayEnvelope.PasskeyMeta(
                slotId: slot, relyingParty: secret.relyingParty,
                userName: secret.userName, userHandle: secret.userHandle,
                credentialID: secret.credentialID, flags: secret.flags))
            if mode == .shared, let blob = try? JSONEncoder().encode(secret) {
                shared[slot] = blob
            }
        }
        return (display, shared)
    }

    /// Passkey display metadata for every slot a LIVE grant opens, from the
    /// owner's passkey list. For the item-edit republish, which has no vault
    /// key: `PasskeyInfo` carries every public field the envelope needs. nil
    /// when a granted slot has no passkey behind it. Resealing the envelope
    /// without that slot would drop the passkey on the recipient, so the
    /// caller keeps the envelope already published instead.
    nonisolated static func displayPasskeys(
        capabilities: [String: FieldCapability], passkeys: [PasskeyInfo]
    ) -> [SharedDisplayEnvelope.PasskeyMeta]? {
        let granted = grantedPasskeySlots(capabilities)
        let metas = passkeys.compactMap { passkey -> SharedDisplayEnvelope.PasskeyMeta? in
            let slot = PasskeySlot.slotId(credentialID: passkey.credentialID)
            guard granted.contains(slot) else { return nil }
            return SharedDisplayEnvelope.PasskeyMeta(
                slotId: slot, relyingParty: passkey.relyingParty,
                userName: passkey.userName, userHandle: passkey.userHandle,
                credentialID: passkey.credentialID, flags: passkey.flags)
        }
        return Set(metas.map(\.slotId)) == granted ? metas : nil
    }

    /// Every passkey slot the grant opens (any non-none mode). Each one must
    /// have its artifacts behind it: a slot named by the signed grant with
    /// nothing behind it renders as "nothing arrived" on the recipient, with
    /// no error anywhere.
    nonisolated static func grantedPasskeySlots(_ capabilities: [String: FieldCapability]) -> Set<String> {
        Set(capabilities.compactMap { slot, capability -> String? in
            guard case .passkey = capability, capability.grantsAnything else { return nil }
            return slot
        })
    }

    /// Whether a field's display metadata rides the envelope: a value the
    /// grant ships, or an ask-each-time code the recipient requests. Every
    /// other field stays out, label included.
    nonisolated static func carriesDisplayMeta(_ capability: FieldCapability?) -> Bool {
        capability?.isSharedValue == true || capability?.isAskEachTimeTOTP == true
    }

    /// Field plaintext the grant seals: every field whose capability ships
    /// its value (shared values and the TOTP seed hand-over). The central
    /// share policy is enforced at this producer boundary too, so even a stale
    /// capability naming a non-shareable field (key material, Level-2) never
    /// serializes its value.
    nonisolated static func sharedFieldValues(
        item: VaultItem, capabilities: [String: FieldCapability]
    ) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            guard capabilities[field.id]?.isSharedValue == true,
                  ItemCapabilityResolver.capabilities(for: field, in: item).approvalShare
            else { return nil }
            return (field.id, Data(field.value.utf8))
        })
    }

    // MARK: Publish

    /// Assemble every `publishGrant` argument identically for create + edit,
    /// then publish. Field values + hand-over passkey secrets are sealed;
    /// display metadata (fields + passkeys) rides the sealed envelope;
    /// single-device scope is preserved via `allowedDevices`.
    @MainActor
    static func publish(
        service: ApprovalShareService,
        store: VaultStore,
        item: VaultItem,
        capabilities: [String: FieldCapability],
        itemPasskeys: [PasskeyInfo],
        vaultKey: SecureBytes?,
        profile: RecipientProfile,
        deviceScope: DeviceScope,
        epoch: UInt32,
        zoneID: CKRecordZone.ID,
        nowUnixMs: Int64
    ) async throws -> AccessGrant {
        var sharedValues = sharedFieldValues(item: item, capabilities: capabilities)
        var displayPasskeys: [SharedDisplayEnvelope.PasskeyMeta] = []
        let grantedSlots = grantedPasskeySlots(capabilities)
        if let vaultKey {
            let vault = PasskeyVault(store: store)
            let secretsBySlot: [(slot: String, secret: PasskeySecret)] = itemPasskeys.compactMap { pk in
                guard let secret = vault.secret(credentialID: pk.credentialID, key: vaultKey)
                else { return nil }
                return (PasskeySlot.slotId(credentialID: pk.credentialID), secret)
            }
            let unresolved = grantedSlots.subtracting(secretsBySlot.map(\.slot))
            guard unresolved.isEmpty else { throw ComposeError.passkeyMaterialUnavailable }
            let artifacts = passkeyArtifacts(secretsBySlot: secretsBySlot, capabilities: capabilities)
            displayPasskeys = artifacts.display
            for (slot, blob) in artifacts.shared { sharedValues[slot] = blob }
            // Hand-over additionally needs its sealed key blob (a failed
            // secret encode would otherwise be skipped silently).
            for slot in grantedSlots
            where capabilities[slot]?.isSharedValue == true && sharedValues[slot] == nil {
                throw ComposeError.passkeyMaterialUnavailable
            }
        } else if !grantedSlots.isEmpty {
            throw ComposeError.passkeyMaterialUnavailable
        }
        let displayFields = Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            carriesDisplayMeta(capabilities[field.id])
                ? (field.id, SharedDisplayEnvelope.FieldMeta(label: field.label,
                                                             kind: field.kind.rawValue,
                                                             protected: field.protected))
                : nil
        })
        let allowed = try allowedDevices(scope: deviceScope, directory: profile.deviceHPKEDirectory)
        return try await service.publishGrant(
            itemId: item.id,
            capabilities: capabilities,
            sharedValues: sharedValues,
            displayTitle: item.title.isEmpty ? appString("Shared item") : item.title,
            displayWebsiteHost: item.urlField?.value.isEmpty == false
                ? URL(string: item.urlField!.value)?.host : nil,
            displayFields: displayFields,
            participantPubKey: profile.participantPubKey,
            pinnedDeviceSigningKeys: profile.deviceSigningKeys,
            epoch: epoch, zoneID: zoneID, nowUnixMs: nowUnixMs,
            deviceScope: deviceScope, allowedDevices: allowed,
            displayPasskeys: displayPasskeys,
            // The share renders as WHAT IT IS on the recipient — an unknown
            // category item forwards its original raw value, never a fallback.
            displayCategory: item.unknownCategoryRaw ?? item.category.rawValue)
    }
}
