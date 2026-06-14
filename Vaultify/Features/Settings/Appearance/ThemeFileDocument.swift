import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The `.vaultheme` exported document type (declared in Project.swift Info.plist).
    static let vaultTheme = UTType(exportedAs: "com.bervion.vaultify.theme")
}

/// `FileDocument` wrapper so a custom theme can be exported / imported via the system
/// document UI. Encoding/decoding + validation lives in `ThemeExchange` (VaultifyCore).
struct ThemeFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.vaultTheme] }

    var theme: CustomTheme

    init(theme: CustomTheme) { self.theme = theme }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        theme = try ThemeExchange.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try ThemeExchange.encode(theme))
    }
}
