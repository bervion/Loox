import Foundation

/// Content-sniffs a PEM PKCS#8 private key (`.p8` as downloaded from App
/// Store Connect / APNs). Classification comes ONLY from the decoded DER
/// bytes — never from a filename or extension — so a mislabeled file cannot
/// masquerade as an Apple key.
nonisolated enum P8KeyInspector {
    /// Real ASC/APNs `.p8` files are a few hundred bytes; anything past this
    /// ceiling is rejected before any decoding happens.
    static let maxInputBytes = 64 * 1024
    static let maxDERDepth = 8
    static let maxDERElements = 4096

    enum KeyType: Equatable, Sendable {
        /// id-ecPublicKey + prime256v1 — the shape Apple issues for ASC API
        /// keys and APNs authentication keys.
        case ecP256
        case other(oid: String)
    }

    struct Result: Equatable, Sendable {
        let isPKCS8: Bool
        let keyType: KeyType?
        /// True only when the classification came from a successful bounded
        /// DER walk of the decoded body. Says nothing about whether the key
        /// is usable or matches any account.
        let verified: Bool

        static let notPKCS8 = Result(isPKCS8: false, keyType: nil, verified: false)
    }

    private static let idECPublicKey: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let prime256v1: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]

    static func inspect(_ data: Data) -> Result {
        guard data.count <= maxInputBytes,
              let text = String(data: data, encoding: .utf8),
              let der = PEMArmor.derBody(of: text, label: "PRIVATE KEY")
        else { return .notPKCS8 }

        guard let scanner = BoundedDERScanner(der: der, maxBytes: maxInputBytes,
                                              maxDepth: maxDERDepth, maxElements: maxDERElements),
              let outer = scanner.topLevel(), outer.tag == 0x30,
              let fields = scanner.children(of: outer, depth: 0),
              fields.count >= 3,
              fields[0].tag == 0x02,       // version INTEGER
              fields[1].tag == 0x30,       // AlgorithmIdentifier SEQUENCE
              fields[2].tag == 0x04,       // privateKey OCTET STRING
              let algorithm = scanner.children(of: fields[1], depth: 1),
              let algorithmOID = algorithm.first, algorithmOID.tag == 0x06
        else { return .notPKCS8 }

        let algorithmBytes = scanner.content(of: algorithmOID)
        let parameterOID: [UInt8]? = {
            guard algorithm.count >= 2, algorithm[1].tag == 0x06 else { return nil }
            return scanner.content(of: algorithm[1])
        }()

        let keyType: KeyType
        if algorithmBytes == idECPublicKey, parameterOID == prime256v1 {
            keyType = .ecP256
        } else if algorithmBytes == idECPublicKey, let curve = parameterOID,
                  let curveString = DEREncoding.oidString(curve) {
            keyType = .other(oid: curveString)
        } else if let algorithmString = DEREncoding.oidString(algorithmBytes) {
            keyType = .other(oid: algorithmString)
        } else {
            return .notPKCS8
        }
        return Result(isPKCS8: true, keyType: keyType, verified: true)
    }
}
