import Foundation
import Security
import CryptoKit

/// Extracts display metadata from a DER or PEM X.509 certificate. Local
/// parsing only: nothing here evaluates trust, checks revocation, or talks
/// to a network.
nonisolated enum CertificateInspector {
    static let maxInputBytes = 1024 * 1024
    static let maxDERDepth = 10
    static let maxDERElements = 4096

    struct Result: Equatable, Sendable {
        let subjectSummary: String?
        let serialNumberHex: String?
        /// SHA-256 of the DER bytes, uppercase colon-separated hex.
        let sha256Fingerprint: String
        let notBefore: Date?
        let notAfter: Date?
        /// True when the validity window was derived from the certificate's
        /// own DER bytes. Local parsing only — never a trust decision.
        let verified: Bool
    }

    static func inspect(_ data: Data) -> Result? {
        guard data.count <= maxInputBytes else { return nil }
        let der: Data
        if let text = String(data: data, encoding: .utf8),
           let body = PEMArmor.derBody(of: text, label: "CERTIFICATE") {
            der = body
        } else {
            der = data
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }

        let summary = (SecCertificateCopySubjectSummary(certificate) as String?)
            .map(Sanitize.displayString)
        let serial = (SecCertificateCopySerialNumberData(certificate, nil) as Data?)
            .map { hex($0, separator: "") }
        let fingerprint = hex(Data(SHA256.hash(data: der)), separator: ":")

        let validity = validityDates(der: der)
        return Result(subjectSummary: summary,
                      serialNumberHex: serial,
                      sha256Fingerprint: fingerprint,
                      notBefore: validity?.notBefore,
                      notAfter: validity?.notAfter,
                      verified: validity != nil)
    }

    /// `SecCertificateCopyValues` is macOS-only, so on iOS the validity window
    /// comes from a bounded DER walk to the TBSCertificate's Validity
    /// sequence. Any structural surprise returns nil rather than guessing.
    private static func validityDates(der: Data) -> (notBefore: Date, notAfter: Date)? {
        guard let scanner = BoundedDERScanner(der: der, maxBytes: maxInputBytes,
                                              maxDepth: maxDERDepth, maxElements: maxDERElements),
              let outer = scanner.topLevel(), outer.tag == 0x30,
              let outerFields = scanner.children(of: outer, depth: 0),
              let tbs = outerFields.first, tbs.tag == 0x30,
              var fields = scanner.children(of: tbs, depth: 1)
        else { return nil }

        // The explicit [0] version wrapper is optional (absent = v1).
        if fields.first?.tag == 0xA0 { fields.removeFirst() }
        // serialNumber INTEGER, signature SEQUENCE, issuer SEQUENCE, validity SEQUENCE.
        guard fields.count >= 4,
              fields[0].tag == 0x02, fields[1].tag == 0x30,
              fields[2].tag == 0x30, fields[3].tag == 0x30,
              let times = scanner.children(of: fields[3], depth: 2),
              times.count == 2,
              let notBefore = DEREncoding.date(tag: times[0].tag, content: scanner.content(of: times[0])),
              let notAfter = DEREncoding.date(tag: times[1].tag, content: scanner.content(of: times[1]))
        else { return nil }
        return (notBefore, notAfter)
    }

    private static func hex(_ data: Data, separator: String) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
