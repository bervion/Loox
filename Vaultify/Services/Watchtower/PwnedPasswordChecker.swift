import Foundation
import CryptoKit

/// Orchestrates known-leak lookups efficiently and privately:
/// deduplicate passwords → serve fresh cache hits → group misses by 5-char
/// SHA-1 prefix (one range request per prefix, never per item) → randomized
/// request order → bounded concurrency → suffix comparison stays local.
/// Cancellation propagates; completed prefixes are cached, partial ones never.
nonisolated struct PwnedPasswordChecker {
    var session: URLSession = .shared
    var cache: AuditLocalCache?
    var maxConcurrentRequests = 4

    /// Breach counts for every distinct password (0 = not found in the dataset).
    func counts(for passwords: some Collection<String>) async throws -> [String: Int] {
        let unique = Set(passwords).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [:] }

        var results: [String: Int] = [:]
        var misses: [String] = []
        for password in unique {
            if let cached = await cache?.count(for: password) {
                results[password] = cached
            } else {
                misses.append(password)
            }
        }
        guard !misses.isEmpty else { return results }

        // Group by hash prefix: 120 unique passwords usually mean fewer ranges.
        var byPrefix: [String: [(password: String, suffix: String)]] = [:]
        for password in misses {
            let hex = Self.sha1Hex(password)
            byPrefix[String(hex.prefix(5)), default: []]
                .append((password, String(hex.dropFirst(5))))
        }

        // Randomized order: the request sequence must not encode vault order.
        let prefixes = byPrefix.keys.shuffled()
        let fetched = try await withThrowingTaskGroup(
            of: (String, [String: Int]).self,
            returning: [String: [String: Int]].self
        ) { group in
            var pending = prefixes.makeIterator()
            var active = 0
            var out: [String: [String: Int]] = [:]

            func enqueue() {
                guard let prefix = pending.next() else { return }
                active += 1
                group.addTask { (prefix, try await Self.range(prefix: prefix, session: session)) }
            }
            for _ in 0..<maxConcurrentRequests { enqueue() }
            while active > 0 {
                guard let (prefix, ranges) = try await group.next() else { break }
                active -= 1
                out[prefix] = ranges
                try Task.checkCancellation()
                enqueue()
            }
            return out
        }

        var freshlyChecked: [String: Int] = [:]
        for (prefix, members) in byPrefix {
            guard let ranges = fetched[prefix] else { continue }
            for member in members {
                freshlyChecked[member.password] = ranges[member.suffix] ?? 0
            }
        }
        await cache?.store(counts: freshlyChecked)
        return results.merging(freshlyChecked) { _, new in new }
    }

    /// One k-anonymity range request, with a single retry for transient errors.
    /// Response lines are `SUFFIX:COUNT`; padded entries (count 0) fall out
    /// naturally. Throws so the caller can distinguish offline from "not found".
    static func range(prefix: String, session: URLSession) async throws -> [String: Int] {
        func fetch() async throws -> [String: Int] {
            guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.addValue("true", forHTTPHeaderField: "Add-Padding")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            var out: [String: Int] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: ":")
                guard parts.count == 2 else { continue }
                let count = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if count > 0 { out[parts[0].uppercased()] = count }
            }
            return out
        }
        do {
            return try await fetch()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await fetch()
        }
    }

    static func sha1Hex(_ password: String) -> String {
        Insecure.SHA1.hash(data: Data(password.utf8))
            .map { String(format: "%02X", $0) }.joined()
    }
}
