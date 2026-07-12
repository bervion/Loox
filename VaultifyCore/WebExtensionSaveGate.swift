import Foundation

/// Native-side policy for the Safari web extension's signup-assist flow:
/// the OS-version gate that defers saving to the system's own save sheet,
/// the per-host "never save" opt-out list, and a light rate limit on
/// password generation.
///
/// SECURITY: everything here is non-secret metadata (an OS version check,
/// bare hostnames, timestamps). Nothing in this file touches the Vault Key
/// or vault contents.
nonisolated enum WebExtensionSaveGate {

    // MARK: - Native save-sheet gate

    /// iOS version from which the OS shows its own native "Save password"
    /// sheet for our credential provider (`SupportsSavePasswordCredentials`).
    /// From here the web extension suppresses its in-page save overlay so the
    /// user never faces two save prompts for one signup.
    static let nativeSaveFloor = OperatingSystemVersion(majorVersion: 26,
                                                        minorVersion: 2,
                                                        patchVersion: 0)

    /// True when the system save-password path owns the save UX on this device.
    static func nativeSavePathActive(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.isOperatingSystemAtLeast(nativeSaveFloor)
    }

    // MARK: - Never-save hosts

    static func isNeverSaved(host: String, defaults: UserDefaults) -> Bool {
        neverSaveHosts(defaults: defaults).contains(normalizeHost(host))
    }

    static func addNeverSave(host: String, defaults: UserDefaults) {
        let normalized = normalizeHost(host)
        guard !normalized.isEmpty else { return }
        var hosts = neverSaveHosts(defaults: defaults)
        guard !hosts.contains(normalized) else { return }
        hosts.append(normalized)
        defaults.set(hosts.sorted(), forKey: SharedConfig.webExtensionNeverSaveHostsKey)
    }

    static func neverSaveHosts(defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: SharedConfig.webExtensionNeverSaveHostsKey) ?? []
    }

    private static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - generatePassword rate limit

    /// At most `generateLimit` generated passwords per `generateWindow`.
    /// Defense in depth: the command is popup-gated in the background page,
    /// but a compromised renderer scripting the messaging surface should not
    /// be able to spin the generator freely. The handler process is
    /// short-lived, so the window persists as timestamps in shared defaults —
    /// timestamps only, never a generated value.
    static let generateLimit = 5
    static let generateWindow: TimeInterval = 60

    static func allowGenerate(now: Date = .now, defaults: UserDefaults) -> Bool {
        let key = SharedConfig.webExtensionGenerateStampsKey
        let cutoff = now.timeIntervalSince1970 - generateWindow
        let stored = defaults.array(forKey: key) as? [Double] ?? []
        var stamps = stored.filter { $0 > cutoff }
        guard stamps.count < generateLimit else {
            defaults.set(stamps, forKey: key)
            return false
        }
        stamps.append(now.timeIntervalSince1970)
        defaults.set(stamps, forKey: key)
        return true
    }
}
