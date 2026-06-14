import Foundation

/// Encode / decode a `CustomTheme` to a portable `.vaultheme` JSON document for
/// share / import (Phase 06). Presentation-only data — decoded defensively, no
/// trust in embedded paths. The document-picker / share-sheet UI lands later.
nonisolated enum ThemeExchange {
    static let fileExtension = "vaultheme"
    static let currentSchema = 1

    struct Document: Codable, Sendable, Equatable {
        var schema: Int
        var theme: CustomTheme
    }

    enum ExchangeError: Error { case unsupportedSchema }

    static func encode(_ theme: CustomTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(schema: currentSchema, theme: theme))
    }

    /// Decode + validate. Returns a copy with a fresh `id` so importing never
    /// collides with an existing saved theme.
    static func decode(_ data: Data) throws -> CustomTheme {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schema <= currentSchema else { throw ExchangeError.unsupportedSchema }
        var theme = document.theme
        theme.id = UUID()
        return theme
    }
}
