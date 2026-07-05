import CloudKit
import Foundation

/// Phase-2 kernel artifacts ↔ `CKRecord`. Signed artifacts travel as ONE
/// opaque `blob` field carrying their canonical bytes — the transported bytes
/// ARE the signed bytes, so a CKRecord round-trip can never mutate what the
/// signature covers. Only opaque linkage ids ride as cleartext fields
/// (documented side-channel: record counts + linkage, never content).
nonisolated enum ApprovalRecordMapping {

    enum Field {
        static let blob = "blob"
        static let requestName = "requestName"
        static let grantId = "grantId"
        static let fieldId = "fieldId"
        static let participantPubKey = "participantPubKey"
        static let deviceSigningKeys = "deviceSigningKeys"
        static let createdAtMs = "createdAtMs"
        static let sealed = "sealed"
        static let expiresAtMs = "expiresAtMs"
    }

    // MARK: Grant (singleton per zone)

    static func grantRecord(_ grant: AccessGrant, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.grantRecordType,
                              recordID: CKRecord.ID(recordName: ApprovalConfig.grantRecordName,
                                                    zoneID: zoneID))
        record[Field.blob] = grant.encoded() as CKRecordValue
        return record
    }

    static func grant(from record: CKRecord) -> AccessGrant? {
        guard record.recordType == ApprovalConfig.grantRecordType,
              let blob = record[Field.blob] as? Data else { return nil }
        return try? AccessGrant.decode(blob)
    }

    // MARK: Request / response (opaque random names)

    static func requestRecord(_ request: ApprovalRequest, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.requestRecordType,
                              recordID: CKRecord.ID(recordName: request.requestId, zoneID: zoneID))
        record[Field.blob] = request.encoded() as CKRecordValue
        return record
    }

    static func request(from record: CKRecord) -> ApprovalRequest? {
        guard record.recordType == ApprovalConfig.requestRecordType,
              let blob = record[Field.blob] as? Data else { return nil }
        return try? ApprovalRequest.decode(blob)
    }

    static func responseRecord(_ response: ApprovalResponse, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.responseRecordType,
                              recordID: CKRecord.ID(recordName: ApprovalConfig.opaqueName(),
                                                    zoneID: zoneID))
        record[Field.blob] = response.encoded() as CKRecordValue
        // Cleartext linkage so the requester can find its answer without
        // decoding every response blob; the id itself is opaque.
        record[Field.requestName] = response.requestId as CKRecordValue
        return record
    }

    static func response(from record: CKRecord) -> ApprovalResponse? {
        guard record.recordType == ApprovalConfig.responseRecordType,
              let blob = record[Field.blob] as? Data else { return nil }
        return try? ApprovalResponse.decode(blob)
    }

    // MARK: Shared field blobs

    static func sharedFieldRecord(sealedBlob: Data, grantId: String, fieldId: String,
                                  zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.sharedFieldRecordType,
                              recordID: CKRecord.ID(recordName: ApprovalConfig.opaqueName(),
                                                    zoneID: zoneID))
        record[Field.blob] = sealedBlob as CKRecordValue
        record[Field.grantId] = grantId as CKRecordValue
        record[Field.fieldId] = fieldId as CKRecordValue
        return record
    }

    static func sharedField(from record: CKRecord) -> (grantId: String, fieldId: String, blob: Data)? {
        guard record.recordType == ApprovalConfig.sharedFieldRecordType,
              let blob = record[Field.blob] as? Data,
              let grantId = record[Field.grantId] as? String,
              let fieldId = record[Field.fieldId] as? String else { return nil }
        return (grantId, fieldId, blob)
    }

    // MARK: Participant profile (singleton per zone, written by B)

    /// Trust in these keys is anchored by the out-of-band fingerprint compare
    /// (ADR-4) and the owner pinning them into the signed grant — the record
    /// itself is just the delivery vehicle. Last writer wins (singleton name +
    /// `createdAtMs` lets the owner detect a newer profile).
    static func participantProfileRecord(participantPubKey: Data, deviceSigningKeys: [Data],
                                         createdAtUnixMs: Int64,
                                         zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.participantProfileRecordType,
                              recordID: CKRecord.ID(recordName: ApprovalConfig.participantProfileRecordName,
                                                    zoneID: zoneID))
        record[Field.participantPubKey] = participantPubKey as CKRecordValue
        record[Field.deviceSigningKeys] = deviceSigningKeys as CKRecordValue
        record[Field.createdAtMs] = createdAtUnixMs as CKRecordValue
        return record
    }

    static func participantProfile(from record: CKRecord)
        -> (participantPubKey: Data, deviceSigningKeys: [Data], createdAtUnixMs: Int64)? {
        guard record.recordType == ApprovalConfig.participantProfileRecordType,
              let pubKey = record[Field.participantPubKey] as? Data,
              let signingKeys = record[Field.deviceSigningKeys] as? [Data],
              let createdAt = record[Field.createdAtMs] as? Int64 else { return nil }
        return (pubKey, signingKeys, createdAt)
    }

    // MARK: Nonce marker (create-if-not-exists)

    static func nonceRecordID(nonce: Data, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        let hex = nonce.map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "n" + hex, zoneID: zoneID)
    }

    static func nonceRecord(nonce: Data, expiresAtUnixMs: Int64,
                            zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.nonceRecordType,
                              recordID: nonceRecordID(nonce: nonce, zoneID: zoneID))
        record[Field.expiresAtMs] = expiresAtUnixMs as CKRecordValue
        return record
    }
}
