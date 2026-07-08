import CryptoKit
import XCTest
@testable import Vaultify

/// GATE QV-1 acceptance oracle: byte-for-byte parity against the FROZEN
/// vectors generated from the production TypeScript encoders
/// (`workers/loox-quick-view/schemas/*.json`,
/// `workers/loox-config/schemas/quick-view-signer-keyset-vectors-v1.json`).
/// Every artifact: session envelope, SAS, KDF/AAD transcripts, upload
/// assertion, signer keyset. A failure here means the app's wire bytes have
/// drifted from what the real backend/browser will compute — never adjust
/// the fixture to make a failure go away; the fixture is the oracle.
final class QuickViewParityTests: XCTestCase {

    private func bundle() -> Bundle { Bundle(for: QuickViewParityTests.self) }

    private func loadJSON<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(bundle().url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: - 1. LOOX-QUICK-VIEW-SESSION-V1

    private struct SessionVectorFile: Decodable {
        let public_key_b64: String
        let vectors: [Vector]
        struct Vector: Decodable {
            let name: String
            let envelope: QuickViewSessionEnvelope
            let canonical_bytes_hex: String
            let canonical_sha256_hex: String
            let signature_b64: String
            let expect_verify: Bool
        }
    }

    func testSessionEnvelopeTranscriptParityAndSignatureAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-session-vectors-v1", as: SessionVectorFile.self)
        XCTAssertEqual(file.vectors.count, 6)
        let publicKey = try XCTUnwrap(Data(base64Encoded: file.public_key_b64))
        let key = try P256.Signing.PublicKey(x963Representation: publicKey)
        for vector in file.vectors {
            let transcript = vector.envelope.transcript
            XCTAssertEqual(transcript.hexString, vector.canonical_bytes_hex,
                           "session vector '\(vector.name)' transcript drifted")
            XCTAssertEqual(Data(SHA256.hash(data: transcript)).hexString, vector.canonical_sha256_hex,
                           "session vector '\(vector.name)' sha256 drifted")
            let rawSignature = try XCTUnwrap(Data(base64Encoded: vector.signature_b64))
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
            let valid = key.isValidSignature(signature, for: transcript)
            XCTAssertEqual(valid, vector.expect_verify,
                           "session vector '\(vector.name)' expect_verify mismatch")
        }
    }

    /// Live-wire regression (bug: app once hex-decoded these fields, but the
    /// real `/sessions` response and the `/open` reference client both encode
    /// session_id/hashes/nonces as BASE64URL). A captured staging envelope must
    /// decode cleanly into 32-byte fields; a hex decoder would throw here.
    func testSessionEnvelopeDecodesRealBase64URLWire() throws {
        let liveJSON = """
        {"version":1,"key_id":"qv-session-staging-202607",
        "session_id":"j0khBNcQI4Um-JXKKDPJyRoHBzrydqP7TcYDqQyfhQE",
        "enc_key_hash":"7gywbdHM6nZ1__WD8Uy7CDn-6sz-sqqJc4I-kQPtWVI",
        "sig_key_hash":"WybjAJyu96iuF9VQx8wweKLfJgKviRdhCHto0-cs-og",
        "browser_nonce":"JNIVIkSrwnJzuH7akpU8rv6AZg648SypL9aLnhv4cbU",
        "server_nonce":"XAUB0SQNp6QdgmtzeqD6_QOAtMwE478DKqy1Vh3cbZA",
        "issued_at":1783507317172,"expires_at":1783507497172,"env":"staging",
        "signature":"gIQy/NTZ9BNNiVMWwY5CdPzUP9rGXrYturv9xcK6gTwGfOr5Tr0CcdrwNUdgvTkFdYcskKhgioCH2h2/ka6kPA=="}
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(QuickViewSessionEnvelope.self, from: liveJSON)
        XCTAssertEqual(env.sessionIDBytes.count, 32)
        XCTAssertEqual(env.encKeyHash.count, 32)
        XCTAssertEqual(env.sigKeyHash.count, 32)
        XCTAssertEqual(env.browserNonce.count, 32)
        XCTAssertTrue(env.sessionID.contains(where: { $0 == "-" || $0 == "_" }),
                      "live session_id is base64url (contains -/_), not hex")
    }

    /// End-to-end wiring proof: `QuickViewSessionEnvelopeVerifier.verify` accepts
    /// the golden vector through a resolver mirroring `QuickViewSignerKeysetDocument`.
    func testSessionEnvelopeVerifierAcceptsGoldenVectorEndToEnd() throws {
        let file = try loadJSON("quick-view-session-vectors-v1", as: SessionVectorFile.self)
        let golden = try XCTUnwrap(file.vectors.first { $0.name == "golden" })
        let publicKey = try XCTUnwrap(Data(base64Encoded: file.public_key_b64))
        let envelopeData = try JSONEncoder().encode(golden.envelope)
        let envelope = try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: envelopeData,
            resolveSignerKey: { keyID in keyID == golden.envelope.keyID ? publicKey : nil },
            expectedEnv: "staging",
            expectedEncKeyHash: golden.envelope.encKeyHash,
            expectedSigKeyHash: golden.envelope.sigKeyHash,
            now: Date(timeIntervalSince1970: Double(golden.envelope.issuedAt) / 1000 + 1))
        XCTAssertEqual(envelope.sessionID, golden.envelope.sessionID)
    }

    // MARK: - 2. SAS

    private struct SASVectorFile: Decodable {
        let hkdf_salt: String
        let hkdf_info: String
        let vectors: [Vector]
        struct Vector: Decodable {
            let name: String
            let input: Input
            let words: [String]
            let digits: String
            let display: String
            struct Input: Decodable {
                let session_id: String
                let enc_key_hash: String
                let sig_key_hash: String
            }
        }
    }

    func testSASParityAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-sas-vectors-v1", as: SASVectorFile.self)
        XCTAssertEqual(file.hkdf_salt, QuickViewSAS.hkdfSaltAndInfo)
        XCTAssertEqual(file.hkdf_info, QuickViewSAS.hkdfSaltAndInfo)
        XCTAssertEqual(QuickViewSASWordList.words.count, QuickViewSAS.wordCount,
                       "bundled BIP-39 wordlist must be exactly 2048 entries")
        for vector in file.vectors {
            let sessionID = try XCTUnwrap(Data(hexString: vector.input.session_id))
            let encHash = try XCTUnwrap(Data(hexString: vector.input.enc_key_hash))
            let sigHash = try XCTUnwrap(Data(hexString: vector.input.sig_key_hash))
            let derived = try XCTUnwrap(QuickViewSAS.derive(
                sessionID: sessionID, encKeyHash: encHash, sigKeyHash: sigHash))
            XCTAssertEqual(derived, vector.display, "SAS vector '\(vector.name)' drifted")
            XCTAssertEqual(derived, "\(vector.words[0]) \(vector.words[1]) \(vector.digits)")
        }
        // Every mutation vector must differ from golden (mutation-sensitivity).
        let golden = try XCTUnwrap(file.vectors.first { $0.name == "golden" })
        for vector in file.vectors where vector.name != "golden" {
            XCTAssertNotEqual(vector.display, golden.display,
                              "SAS mutation '\(vector.name)' must differ from golden")
        }
    }

    // MARK: - 3. LOOX-QUICK-VIEW-KDF-V1 + LOOX-QUICK-VIEW-PAYLOAD-V1 (AAD)

    private struct PayloadVectorFile: Decodable {
        let kdf_magic: String
        let aad_magic: String
        let kdf_vectors: [KDFVector]
        let aad_vectors: [AADVector]
        struct KDFVector: Decodable {
            let name: String
            let input: Input
            let canonical_bytes_hex: String
            let canonical_sha256_hex: String
            struct Input: Decodable {
                let session_id: String, browser_enc_key_hash: String
                let browser_sig_key_hash: String, app_eph_pub_hash: String, env: String
            }
        }
        struct AADVector: Decodable {
            let name: String
            let input: Input
            let canonical_bytes_hex: String
            let canonical_sha256_hex: String
            struct Input: Decodable {
                let session_id: String, enc_key_hash: String, approval_id: String
                let field_manifest_hash: String, issued_at: Int64, expires_at: Int64
            }
        }
    }

    func testKDFTranscriptParityAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-payload-vectors-v1", as: PayloadVectorFile.self)
        XCTAssertEqual(file.kdf_magic, QuickViewPayloadSealer.kdfMagic)
        for vector in file.kdf_vectors {
            let i = vector.input
            // The vector's `app_eph_pub_hash` is ALREADY SHA256(app_eph_pub)
            // — `QuickViewPayloadSealer.kdfTranscript(appEphemeralPublicKey:)`
            // takes the raw pubkey and hashes it internally, so it can't be
            // fed a pre-hashed value directly here (that would double-hash).
            // Build the same transcript from the shared wire primitives
            // instead, blobbing the given hash straight in.
            let transcript = Data(QuickViewPayloadSealer.kdfMagic.utf8)
                + QuickViewWire.byte(QuickViewPayloadSealer.cryptoVersion)
                + QuickViewWire.lengthPrefixed(try XCTUnwrap(Data(hexString: i.session_id)))
                + QuickViewWire.lengthPrefixed(try XCTUnwrap(Data(hexString: i.browser_enc_key_hash)))
                + QuickViewWire.lengthPrefixed(try XCTUnwrap(Data(hexString: i.browser_sig_key_hash)))
                + QuickViewWire.lengthPrefixed(try XCTUnwrap(Data(hexString: i.app_eph_pub_hash)))
                + QuickViewWire.lengthPrefixed(i.env)
            XCTAssertEqual(transcript.hexString, vector.canonical_bytes_hex,
                           "kdf vector '\(vector.name)' transcript drifted")
            XCTAssertEqual(Data(SHA256.hash(data: transcript)).hexString, vector.canonical_sha256_hex,
                           "kdf vector '\(vector.name)' sha256 drifted")
        }
    }

    func testAADTranscriptParityAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-payload-vectors-v1", as: PayloadVectorFile.self)
        XCTAssertEqual(file.aad_magic, QuickViewPayloadSealer.payloadMagic)
        for vector in file.aad_vectors {
            let i = vector.input
            let sessionID = try XCTUnwrap(Data(hexString: i.session_id))
            let encHash = try XCTUnwrap(Data(hexString: i.enc_key_hash))
            let approvalID = try XCTUnwrap(Data(hexString: i.approval_id))
            let fieldManifestHash = try XCTUnwrap(Data(hexString: i.field_manifest_hash))
            let aad = QuickViewPayloadSealer.aad(
                sessionID: sessionID, encKeyHash: encHash, approvalID: approvalID,
                fieldManifestHash: fieldManifestHash, issuedAt: i.issued_at, expiresAt: i.expires_at)
            XCTAssertEqual(aad.hexString, vector.canonical_bytes_hex,
                           "aad vector '\(vector.name)' transcript drifted")
            XCTAssertEqual(Data(SHA256.hash(data: aad)).hexString, vector.canonical_sha256_hex,
                           "aad vector '\(vector.name)' sha256 drifted")
        }
    }

    // MARK: - 4. LOOX-APP-ATTEST-QUICK-VIEW-V1 (upload assertion)

    private struct UploadAssertionVectorFile: Decodable {
        let vectors: [Vector]
        struct Vector: Decodable {
            let name: String
            let input: Input
            let client_data_hex: String
            let client_data_hash_hex: String
            struct Input: Decodable {
                let method: String, path: String, challengeId: String
                let session_id: String, aad: String, ciphertext: String, app_eph_pub: String
            }
        }
    }

    func testUploadAssertionParityAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-upload-assertion-vectors-v1", as: UploadAssertionVectorFile.self)
        XCTAssertEqual(file.vectors.count, 9)
        for vector in file.vectors {
            let i = vector.input
            let sessionIDBytes = try XCTUnwrap(Data(hexString: i.session_id))
            let aad = try XCTUnwrap(Data(hexString: i.aad))
            let ciphertext = try XCTUnwrap(Data(hexString: i.ciphertext))
            let appEphPub = try XCTUnwrap(Data(hexString: i.app_eph_pub))
            let body = QuickViewCanonical.canonicalUploadBody(
                aad: aad, ciphertext: ciphertext, appEphemeralPublicKey: appEphPub)
            let clientData = QuickViewCanonical.assertionClientData(
                method: i.method, path: i.path, challengeID: i.challengeId,
                sessionIDBytes: sessionIDBytes, uploadBody: body)
            XCTAssertEqual(clientData.hexString, vector.client_data_hex,
                           "upload-assertion vector '\(vector.name)' client_data drifted")
            let hash = QuickViewCanonical.assertionClientDataHash(
                method: i.method, path: i.path, challengeID: i.challengeId,
                sessionIDBytes: sessionIDBytes, uploadBody: body)
            XCTAssertEqual(hash.hexString, vector.client_data_hash_hex,
                           "upload-assertion vector '\(vector.name)' clientDataHash drifted")
        }
    }

    // MARK: - 5. LOOX-QUICK-VIEW-SIGNER-KEYSET-V1

    private struct SignerKeysetVectorFile: Decodable {
        let vectors: [Vector]
        struct Vector: Decodable {
            let name: String
            let keyset: QuickViewSignerKeysetDocument
            let canonical_bytes_hex: String
            let canonical_sha256_hex: String
        }
    }

    func testSignerKeysetTranscriptParityAgainstFrozenVectors() throws {
        let file = try loadJSON("quick-view-signer-keyset-vectors-v1", as: SignerKeysetVectorFile.self)
        XCTAssertEqual(file.vectors.count, 3)
        for vector in file.vectors {
            let transcript = vector.keyset.transcript
            XCTAssertEqual(transcript.hexString, vector.canonical_bytes_hex,
                           "signer-keyset vector '\(vector.name)' transcript drifted")
            XCTAssertEqual(Data(SHA256.hash(data: transcript)).hexString, vector.canonical_sha256_hex,
                           "signer-keyset vector '\(vector.name)' sha256 drifted")
        }
    }

    func testSignerKeysetEndorsedPublicKeyResolvesActiveAndVerifyOnlyOnly() throws {
        let file = try loadJSON("quick-view-signer-keyset-vectors-v1", as: SignerKeysetVectorFile.self)
        let rotation = try XCTUnwrap(file.vectors.first { $0.name.hasPrefix("rotation overlap") })
        let now = Date(timeIntervalSince1970: Double(rotation.keyset.issuedAt) / 1000 + 1)
        // "active" key resolves.
        XCTAssertNotNil(rotation.keyset.endorsedPublicKey(keyID: "qv-signer-2026-01", expectedEnv: "staging", now: now))
        // "next" key does NOT resolve yet (not currently signing/verifiable).
        XCTAssertNil(rotation.keyset.endorsedPublicKey(keyID: "qv-signer-2026-02", expectedEnv: "staging", now: now))
        // Wrong env never resolves regardless of status.
        XCTAssertNil(rotation.keyset.endorsedPublicKey(keyID: "qv-signer-2026-01", expectedEnv: "production", now: now))
        // Unknown key id never resolves.
        XCTAssertNil(rotation.keyset.endorsedPublicKey(keyID: "does-not-exist", expectedEnv: "staging", now: now))
    }
}
