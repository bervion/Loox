import Foundation

/// Extracts display metadata from a `.mobileprovision` file (a CMS envelope
/// wrapping an XML plist). The plist bytes are located by a bounded scan and
/// read with `PropertyListSerialization`, treating every field as optional —
/// the envelope is untrusted input, not a schema we control.
nonisolated enum ProvisioningProfileInspector {
    static let maxInputBytes = 2 * 1024 * 1024

    struct Result: Equatable, Sendable {
        var parsed = false
        /// Always false in v1: the embedded plist is read without verifying
        /// the surrounding CMS signature, so no field here is authenticated.
        let signatureChecked = false
        var uuid: String?
        var name: String?
        var appIDName: String?
        var applicationIdentifier: String?
        var teamIdentifier: String?
        var expirationDate: Date?
        var creationDate: Date?
        var platforms: [String] = []
        var provisionsAllDevices = false
        var provisionedDeviceCount: Int?
        var getTaskAllow: Bool?

        static let unparsed = Result()
    }

    static func inspect(_ data: Data) -> Result {
        guard data.count <= maxInputBytes,
              let plistRange = embeddedPlistRange(in: data),
              let object = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: plistRange), options: [], format: nil),
              let dict = object as? [String: Any]
        else { return .unparsed }

        var result = Result()
        result.parsed = true
        result.uuid = sanitizedString(dict["UUID"])
        result.name = sanitizedString(dict["Name"])
        result.appIDName = sanitizedString(dict["AppIDName"])
        result.expirationDate = dict["ExpirationDate"] as? Date
        result.creationDate = dict["CreationDate"] as? Date
        result.platforms = (dict["Platform"] as? [Any])?.compactMap(sanitizedString) ?? []
        result.provisionsAllDevices = dict["ProvisionsAllDevices"] as? Bool ?? false
        result.provisionedDeviceCount = (dict["ProvisionedDevices"] as? [Any])?.count
        result.teamIdentifier = (dict["TeamIdentifier"] as? [Any])
            .flatMap(\.first)
            .flatMap(sanitizedString)
        if let entitlements = dict["Entitlements"] as? [String: Any] {
            result.applicationIdentifier = sanitizedString(entitlements["application-identifier"])
            result.getTaskAllow = entitlements["get-task-allow"] as? Bool
        }
        return result
    }

    private static func embeddedPlistRange(in data: Data) -> Range<Int>? {
        let xmlOpen = Data("<?xml".utf8)
        let plistClose = Data("</plist>".utf8)
        guard let start = data.range(of: xmlOpen),
              let end = data.range(of: plistClose, options: [], in: start.upperBound..<data.endIndex)
        else { return nil }
        return start.lowerBound..<end.upperBound
    }

    private static func sanitizedString(_ value: Any?) -> String? {
        (value as? String).map(Sanitize.displayString)
    }
}
