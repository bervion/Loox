import Foundation

/// A recognized local search operator. NO AI, NO network — every predicate
/// below reads only properties already present on decrypted-in-memory
/// `VaultItem`s (or the pre-computed `SearchOperators.Context`).
///
/// Operators only ever *narrow* whatever pool they're applied to — callers
/// (see `SearchResultsList` in `SearchScreen.swift`) apply them to an
/// already-scoped item set. Nothing here fetches or ranges over a wider pool.
nonisolated enum SearchOperator: Hashable, Sendable {
    case hasTOTP
    case weakPassword
    case reusedPassword
    case hasPasskey
    case category(ItemCategory)
    /// `prefix:value` operators (`type:ssh`, `host:github.com`,
    /// `env:production`, `expires:<30d`) — parsed from colon tokens, never
    /// from bare keywords.
    case typed(String)
    case host(String)
    case environment(String)
    case expiresWithinDays(Int)

    static var allCases: [SearchOperator] {
        [.hasTOTP, .weakPassword, .reusedPassword, .hasPasskey] + ItemCategory.allCases.map(SearchOperator.category)
    }

    /// EN + VI synonyms that select this operator when typed as a standalone
    /// word/phrase in the search field. Compared case- and diacritic-insensitively
    /// (`SearchOperators.normalize`), so "yếu" and "yeu" both match. A keyword may
    /// be a multi-word phrase (e.g. "ssh key", "đăng nhập") — matched as a
    /// contiguous run of words, not a substring.
    var keywords: [String] {
        switch self {
        case .hasTOTP:
            return ["2fa", "otp", "mfa", "totp", "code", "mã"]
        case .weakPassword:
            return ["weak", "yếu"]
        case .reusedPassword:
            return ["reused", "reuse", "duplicate", "trùng", "lặp"]
        case .hasPasskey:
            return ["passkey", "passkeys"]
        case .category(let category):
            switch category {
            case .login: return ["login", "logins", "đăng nhập"]
            case .note: return ["note", "notes", "ghi chú"]
            case .card: return ["card", "cards", "thẻ thanh toán"]
            case .identity: return ["identity", "identities", "danh tính"]
            case .sshKey: return ["ssh", "sshkey", "ssh key", "khóa ssh"]
            case .recoveryCodes: return ["recovery", "recoverycodes", "recovery codes", "mã khôi phục"]
            case .securityQuestions: return ["security", "securityquestions", "security questions", "câu hỏi bảo mật"]
            case .custom: return ["custom", "tùy chỉnh"]
            }
        case .typed, .host, .environment, .expiresWithinDays:
            return [] // colon-syntax only, never bare keywords
        }
    }
}

/// Pure query parsing + item predicates for the local search-operator grammar
/// (Loox Design DNA #10 — "search superpower"). Kept free of repository/
/// environment access so it's trivially unit-testable; callers supply the
/// scoped item pool and any derived signals via `Context`.
nonisolated enum SearchOperators {

    /// Result of splitting a raw query into recognized operators + the
    /// remaining free-text tokens (already normalized/lowercased, matching the
    /// existing `VaultRepository.search` token model).
    struct ParsedQuery: Equatable {
        var operators: [SearchOperator]
        var freeTextTokens: [String]
    }

    /// External signals an operator predicate needs beyond the item itself,
    /// e.g. `PasswordAudit` output. Computed by the caller ONCE per query over
    /// the already-scoped pool (never the whole vault) — see phase-04 §3: audit
    /// runs on the scoped pool, so "reused" is scoped-relative by design.
    struct Context: Equatable {
        var weakItemIDs: Set<String> = []
        var reusedItemIDs: Set<String> = []
        var passkeyItemIDs: Set<String> = []
        /// Reference clock for `expires:` windows — injected for determinism.
        var now: Date = .now
        static let empty = Context()
    }

    /// Case- and diacritic-fold for locale-agnostic keyword matching (so VI
    /// input works with or without the on-screen-keyboard's tone marks).
    static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
    }

    /// Split `query` into recognized operators + remaining free text. Each
    /// operator claims at most one keyword match; matched words are removed so
    /// they never re-enter free text (e.g. "weak gmail" → `[.weakPassword]` +
    /// `["gmail"]`).
    ///
    /// Two parallel token streams: `folded` drives keyword recognition (case +
    /// diacritic insensitive, so "yeu" matches "yếu"), while `literal` keeps
    /// the user's lowercased words intact for free-text matching —
    /// `VaultItem.searchText` is lowercased but NOT diacritic-folded, so a
    /// folded token would silently miss every accented title ("ngan" never
    /// appears in "ngân hàng acb"). Both arrays split on the same whitespace,
    /// so keyword ranges line up index-for-index.
    ///
    /// A recognized keyword can still be the user's literal search term
    /// ("security", "mã") — callers handle that by falling back to a plain
    /// free-text search when the operator reading returns nothing.
    static func parse(_ query: String) -> ParsedQuery {
        var folded = normalize(query).split(separator: " ").map(String.init)
        var literal = query.lowercased().split(separator: " ").map(String.init)
        var operators: [SearchOperator] = []
        // Colon operators claim their tokens first (`type:ssh`,
        // `host:github.com`, `env:production`, `expires:<30d`). Unrecognized
        // prefixes and empty values stay in free text untouched.
        var index = 0
        while index < literal.count {
            if let op = prefixedOperator(from: literal[index]) {
                operators.append(op)
                literal.remove(at: index)
                folded.remove(at: index)
            } else {
                index += 1
            }
        }
        for op in SearchOperator.allCases {
            // Longest phrase first so "ssh key" is tried before the shorter "ssh".
            let keywordWordLists = op.keywords
                .map { normalize($0).split(separator: " ").map(String.init) }
                .sorted { $0.count > $1.count }
            for keyword in keywordWordLists {
                if let range = firstRange(of: keyword, in: folded) {
                    folded.removeSubrange(range)
                    literal.removeSubrange(range)
                    operators.append(op)
                    break
                }
            }
        }
        return ParsedQuery(operators: operators, freeTextTokens: literal)
    }

    /// Parses one `prefix:value` token, or nil when it isn't one.
    static func prefixedOperator(from token: String) -> SearchOperator? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let prefix = String(token[..<colon])
        let value = String(token[token.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        switch prefix {
        case "type", "loai": return .typed(normalize(value))
        case "host": return .host(normalize(value))
        case "env": return .environment(normalize(value))
        case "expires":
            // `<30d`, `30d`, or `30`: anything expiring within N days.
            var digits = value
            if digits.hasPrefix("<") { digits.removeFirst() }
            if digits.hasSuffix("d") { digits.removeLast() }
            guard let days = Int(digits), (1...3650).contains(days) else { return nil }
            return .expiresWithinDays(days)
        default: return nil
        }
    }

    /// Whether `item` satisfies every recognized operator (AND across operators,
    /// mirroring the free-text AND-across-tokens model).
    static func matches(_ item: VaultItem, operators: [SearchOperator], context: Context) -> Bool {
        operators.allSatisfy { op in
            switch op {
            case .hasTOTP: return item.totpField != nil
            case .weakPassword: return context.weakItemIDs.contains(item.id)
            case .reusedPassword: return context.reusedItemIDs.contains(item.id)
            case .hasPasskey: return context.passkeyItemIDs.contains(item.id)
            case .category(let category): return item.category == category
            case .typed(let needle):
                // Stable identity only — kind ID or category raw value; never
                // an editable label.
                let kind = item.kindID ?? ItemTemplateRegistry.legacyKind(for: item.category)
                return normalize(kind.rawValue).contains(needle)
                    || normalize(item.category.rawValue).contains(needle)
            case .host(let needle):
                return item.autofillHosts.contains { normalize($0).contains(needle) }
                    || item.fields.contains {
                        $0.roleID == .gitHost && !$0.protected && normalize($0.value).contains(needle)
                    }
            case .environment(let needle):
                return item.fields.contains {
                    $0.roleID == .apiEnvironment && !$0.protected && normalize($0.value).contains(needle)
                }
            case .expiresWithinDays(let days):
                let deadline = context.now.addingTimeInterval(TimeInterval(days) * 86_400)
                return item.fields.contains {
                    guard let expiry = $0.semantics?.lifecycle?.expiresAt else { return false }
                    return expiry <= deadline
                }
            }
        }
    }

    /// First contiguous index range in `haystack` equal to `needle`, or nil.
    private static func firstRange(of needle: [String], in haystack: [String]) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return start..<(start + needle.count)
        }
        return nil
    }
}
