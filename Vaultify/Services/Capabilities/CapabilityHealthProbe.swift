import Foundation

/// Contextual, non-blocking health probe — fired when a capability's screen
/// opens (never at app startup, INV-CAP-02). Reads each worker's
/// `/health/ready` report (`{ready, state, checks}`) and feeds the store:
/// a verified `state` updates operator policy; transport failure marks an
/// outage (INV-CAP-07: it never touches the operator mode).
@MainActor enum CapabilityHealthProbe {

    /// Lightweight service-state endpoints (BE handoff §3) — poll on screen
    /// open, never per-action and never at startup.
    static func readyURL(for id: CapabilityID) -> URL {
        switch id {
        case .privateEmail: return URL(string: "https://api-relay.looxpassword.com/v1/relay/service-state")!
        case .shareLink: return LooxLinkConfig.defaultAPIBase.appending(path: "/v1/link/service-state")
        // The shortener runs in the same worker until it grows a dedicated
        // state route — repoint when the short-link service ships one.
        case .shortLink: return LooxLinkConfig.defaultAPIBase.appending(path: "/v1/link/service-state")
        }
    }

    /// Parse a ready-report body. Pure + static for tests.
    nonisolated static func parseState(_ data: Data) -> CapabilityServiceMode? {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (body?["state"] as? String).flatMap(CapabilityServiceMode.init(rawValue:))
    }

    static func probe(_ id: CapabilityID, store: CapabilityStore) async {
        guard store.allowRequest(id) else { return }   // breaker open — don't poke
        var request = URLRequest(url: readyURL(for: id))
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            store.noteInfrastructureFailure(id)
            return
        }
        // Any HTTP answer means the service is alive; a parseable state is a
        // verified operator signal. An unparseable body changes nothing.
        if let state = parseState(data) {
            store.noteOperatorSignal(id, .init(mode: state, retryAfter: nil))
        } else if (200...299).contains(http.statusCode) {
            store.noteServiceResponded(id)
        } else if (502...504).contains(http.statusCode) {
            store.noteInfrastructureFailure(id)
        }
    }
}
