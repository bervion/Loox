import CloudKit
import SwiftUI

/// Read-only projection of ONE share accepted by this account (recipient
/// side). Renders decrypted `shared` values (participant key, ADR-3) and a
/// Request control for the `askEachTime` TOTP capability. Capability, not
/// ownership: nothing here is editable, nothing joins the local vault store,
/// and the owner can revoke future access at any time (already-shown values
/// are retained by design — the UX copy states this at accept time).
struct SharedItemView: View {
    /// Full zone identity — shared-DB zones are namespaced by the sharing
    /// owner; a bare zoneName would resolve to `__defaultOwner__` and miss.
    let route: SharedZoneRoute

    @Environment(AppEnvironment.self) private var env

    private enum LoadState {
        case loading
        case needsFingerprint(grant: AccessGrant, code: String)
        case ready(grant: AccessGrant, values: [String: String])
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    /// Built in `load()` (never during body) and rebuilt only when the grant
    /// id changes — an in-flight WAITING machine survives push-driven reloads
    /// of the SAME grant, but a re-granted share gets fresh models.
    @State private var requestModels: [String: RequestCodeModel] = [:]
    @State private var modelsGrantId: String?

    private var zoneID: CKRecordZone.ID { route.zoneID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                sharedByBadge
                switch loadState {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .needsFingerprint(_, let code):
                    TrustFingerprintView(code: code, recipientLabel: appString("the owner")) {
                        confirmFingerprint()
                    }
                case .ready(let grant, let values):
                    fieldsCard(grant: grant, values: values)
                case .failed(let message):
                    Text(verbatim: message)
                        .vaultType(.callout).themedForeground(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Shared with you")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task(id: env.approvalCoordinator.recipientChangeCounter) { await load() }
    }

    private var sharedByBadge: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.shield, size: Metric.iconInline).themedForeground(.accent)
            Text("Shared with you — you can use what's listed here, but not edit it.")
                .vaultType(.footnote).themedForeground(.secondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func fieldsCard(grant: AccessGrant, values: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Static shared values (retained; decrypted with the participant key).
            ForEach(values.keys.sorted(), id: \.self) { fieldId in
                if let value = values[fieldId] {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Shared value").vaultType(.sectionLabel).themedForeground(.secondary)
                        Text(verbatim: value)
                            .vaultType(.body).themedForeground()
                            .textSelection(.enabled)
                    }
                }
            }
            // Ask-each-time TOTP capabilities → the request state machine.
            ForEach(askEachTimeFieldIds(grant), id: \.self) { fieldId in
                if let model = requestModels[fieldId] {
                    RequestCodeView(model: model, deviceId: recipientDeviceId)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func askEachTimeFieldIds(_ grant: AccessGrant) -> [String] {
        grant.capabilities.filter { $0.value.isAskEachTimeTOTP }.keys.sorted()
    }

    /// Rebuild models only on a grant change (M1: state writes happen in
    /// `load()`, not while body renders; M2: no stale-grant snapshots).
    private func rebuildModelsIfNeeded(grant: AccessGrant) {
        guard modelsGrantId != grant.id else { return }
        modelsGrantId = grant.id
        requestModels = Dictionary(uniqueKeysWithValues:
            askEachTimeFieldIds(grant).map { fieldId in
                (fieldId, RequestCodeModel(service: env.approvalRecipient, grant: grant,
                                           fieldId: fieldId, zoneID: zoneID))
            })
    }

    /// Stable opaque per-install id for request metadata (not a secret).
    private var recipientDeviceId: String {
        let key = "approval_recipient_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = ApprovalConfig.opaqueName()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    // MARK: Load

    private func load() async {
        let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            let grant = try await env.approvalRecipient.fetchGrant(zoneID: zoneID,
                                                                   nowUnixMs: nowUnixMs)
            // Pre-pin: show the one-time fingerprint ceremony; values and
            // requests stay locked until the code is confirmed (ADR-4).
            guard ApprovalRecipientService.pinnedOwnerKey(zoneID: zoneID) != nil else {
                guard let vaultKey = env.session.vaultKey?.bytes else {
                    loadState = .failed(appString("Unlock your vault to view this share."))
                    return
                }
                let identity = try await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
                let code = TrustFingerprint.code(ownerSigningPubKey: grant.ownerSigningPubKey,
                                                 participantPubKey: identity.publicKeyRaw)
                loadState = .needsFingerprint(grant: grant, code: code)
                return
            }
            guard let vaultKey = env.session.vaultKey?.bytes else {
                loadState = .failed(appString("Unlock your vault to view this share."))
                return
            }
            let identity = try await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
            let raw = try await env.approvalRecipient.fetchSharedFieldValues(
                grant: grant, identity: identity, zoneID: zoneID)
            let values = raw.compactMapValues { String(data: $0, encoding: .utf8) }
            rebuildModelsIfNeeded(grant: grant)
            loadState = .ready(grant: grant, values: values)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            loadState = .failed(appString("The owner stopped sharing this item."))
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func confirmFingerprint() {
        guard case .needsFingerprint(let grant, _) = loadState else { return }
        do {
            try ApprovalRecipientService.pinOwnerKey(grant.ownerSigningPubKey, zoneID: zoneID)
            loadState = .loading
            Task { await load() }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
