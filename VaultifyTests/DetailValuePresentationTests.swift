import XCTest
@testable import Vaultify

/// Detail rendering resolves SECRET POLICY before presentation kind. The two
/// shipped disclosure cases — SSH private key and recovery codes, both
/// `protected` multiline template fields — must never reach the Markdown
/// (plaintext-first) branch again.
final class DetailValuePresentationTests: XCTestCase {

    func testProtectedMultilineNeverRendersMarkdown() {
        let presentation = DetailValuePresentation.resolve(
            kind: .multiline, isProtected: true, isCardNumber: false)
        XCTAssertEqual(presentation, .protectedMultiline)
        XCTAssertNotEqual(presentation, .markdownNote)
    }

    func testPlainNoteStillRendersMarkdown() {
        XCTAssertEqual(DetailValuePresentation.resolve(
            kind: .multiline, isProtected: false, isCardNumber: false), .markdownNote)
    }

    /// Regression pin for the two disclosure cases exactly as their templates
    /// create them (sshKey "Private Key", recoveryCodes "Recovery Codes").
    func testShippedTemplateSecretsAreMaskedBeforeReveal() {
        for category in [ItemCategory.sshKey, .recoveryCodes] {
            for field in category.fieldTemplate where field.protected {
                let presentation = DetailValuePresentation.resolve(
                    kind: field.kind, isProtected: field.protected,
                    isCardNumber: false)
                XCTAssertTrue(presentation == .protectedMultiline || presentation == .secretGlyphs,
                              "\(category) '\(field.label)' must render masked, got \(presentation)")
            }
        }
    }

    /// Every protected field of every template must resolve into a masked
    /// presentation — no future template can silently opt out of masking.
    func testEveryProtectedTemplateFieldResolvesMasked() {
        for category in ItemCategory.allCases {
            for field in category.fieldTemplate where field.protected {
                let presentation = DetailValuePresentation.resolve(
                    kind: field.kind, isProtected: true,
                    isCardNumber: category == .card && field.kind == .monospace && field.label == "Card Number")
                XCTAssertNotEqual(presentation, .markdownNote,
                                  "\(category)/\(field.label) leaked into Markdown")
                XCTAssertNotEqual(presentation, .plainText,
                                  "\(category)/\(field.label) leaked into plain text")
            }
        }
    }

    func testNonSecretKindsKeepTheirPresentation() {
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .url, isProtected: false, isCardNumber: false), .url)
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .totp, isProtected: true, isCardNumber: false), .totpCode)
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .text, isProtected: false, isCardNumber: false), .plainText)
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .monospace, isProtected: true, isCardNumber: true), .cardNumber)
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .password, isProtected: true, isCardNumber: false), .secretGlyphs)
        // A user-protected plain text field masks too.
        XCTAssertEqual(DetailValuePresentation.resolve(kind: .text, isProtected: true, isCardNumber: false), .secretGlyphs)
    }
}
