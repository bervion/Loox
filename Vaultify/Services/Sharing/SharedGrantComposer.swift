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
        var errorDescription: String? {
            appString("Single-device sharing needs the recipient to update Loox first.")
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
        var sharedValues: [String: Data] = Dictionary(uniqueKeysWithValues:
            item.fields.compactMap { field in
                guard capabilities[field.id]?.isSharedValue == true,
                      !field.isExtraProtected else { return nil }
                return (field.id, Data(field.value.utf8))
            })
        var displayPasskeys: [SharedDisplayEnvelope.PasskeyMeta] = []
        if let vaultKey {
            let vault = PasskeyVault(store: store)
            let secretsBySlot: [(slot: String, secret: PasskeySecret)] = itemPasskeys.compactMap { pk in
                guard let secret = vault.secret(credentialID: pk.credentialID, key: vaultKey)
                else { return nil }
                return (PasskeySlot.slotId(credentialID: pk.credentialID), secret)
            }
            let artifacts = passkeyArtifacts(secretsBySlot: secretsBySlot, capabilities: capabilities)
            displayPasskeys = artifacts.display
            for (slot, blob) in artifacts.shared { sharedValues[slot] = blob }
        }
        let displayFields = Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            capabilities[field.id]?.isSharedValue == true
                || capabilities[field.id]?.isAskEachTimeTOTP == true
                ? (field.id, SharedDisplayEnvelope.FieldMeta(label: field.label,
                                                             kind: field.kind.rawValue))
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
            displayPasskeys: displayPasskeys)
    }
}
