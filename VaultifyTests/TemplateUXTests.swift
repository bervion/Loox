import XCTest
@testable import Vaultify

/// Template-driven UX contracts: picker targets stamp semantics, semantic
/// subtitles never leak secrets, prefixed search operators parse and match on
/// stable identity, and Git snippets are copy-safe.
final class TemplateUXTests: XCTestCase {

    // MARK: New-item targets

    func testNewFromTemplateStampsSemantics() throws {
        let template = try XCTUnwrap(ItemTemplateRegistry.definition(for: .apiSecret))
        guard case .draft(let item) = EditorTarget.newFromTemplate(template) else {
            return XCTFail("template creation must produce a prefilled draft")
        }
        XCTAssertEqual(item.kindID, .apiSecret)
        XCTAssertEqual(item.semantics?.templateVersion, template.version)
        XCTAssertEqual(item.category, template.legacyCategory)
        // Every default field carries its role and section.
        XCTAssertTrue(item.fields.allSatisfy { $0.semantics?.sectionID != nil })
        XCTAssertTrue(item.fields.contains { $0.roleID == .apiToken && $0.protected })
    }

    func testEveryTemplateProducesNonEmptyDefaults() {
        for template in ItemTemplateRegistry.all {
            XCTAssertFalse(template.defaultFields.isEmpty, template.kindID.rawValue)
        }
    }

    // MARK: Semantic subtitles

    func testSubtitlePrefersTemplateRoleAndNeverLeaksSecrets() {
        let template = ItemTemplateRegistry.definition(for: .apiSecret)!
        var item = VaultItem(category: .custom, title: "Stripe", fields: template.defaultFields)
        item.semantics = template.newItemSemantics
        if let index = item.fields.firstIndex(where: { $0.roleID == .apiEnvironment }) {
            item.fields[index].value = "production"
        }
        if let index = item.fields.firstIndex(where: { $0.roleID == .apiToken }) {
            item.fields[index].value = "sk_live_secret"
        }
        XCTAssertEqual(item.subtitle, "production")

        // A protected subtitle-role value must never surface.
        if let index = item.fields.firstIndex(where: { $0.roleID == .apiEnvironment }) {
            item.fields[index].protected = true
        }
        XCTAssertNotEqual(item.subtitle, "production")
        XCTAssertNotEqual(item.subtitle, "sk_live_secret")
    }

    // MARK: Prefixed search operators

    func testPrefixedOperatorParsing() {
        let parsed = SearchOperators.parse("type:ssh host:github.com env:prod expires:<30d deploy")
        XCTAssertTrue(parsed.operators.contains(.typed("ssh")))
        XCTAssertTrue(parsed.operators.contains(.host("github.com")))
        XCTAssertTrue(parsed.operators.contains(.environment("prod")))
        XCTAssertTrue(parsed.operators.contains(.expiresWithinDays(30)))
        XCTAssertEqual(parsed.freeTextTokens, ["deploy"])
        // Unknown prefixes and empty values stay free text.
        let unknown = SearchOperators.parse("foo:bar type:")
        XCTAssertTrue(unknown.operators.isEmpty)
        XCTAssertEqual(unknown.freeTextTokens, ["foo:bar", "type:"])
    }

    func testTypeOperatorMatchesStableIdentityNotLabels() {
        var ssh = VaultItem(category: .sshKey, title: "Máy chủ deploy",
                            fields: ItemCategory.sshKey.fieldTemplate)
        ssh = LegacySemanticsInference.applied(to: ssh)
        XCTAssertTrue(SearchOperators.matches(ssh, operators: [.typed("ssh")], context: .empty))
        XCTAssertFalse(SearchOperators.matches(ssh, operators: [.typed("card")], context: .empty))

        let template = ItemTemplateRegistry.definition(for: .apiSecret)!
        var api = VaultItem(category: .custom, title: "T", fields: template.defaultFields)
        api.semantics = template.newItemSemantics
        XCTAssertTrue(SearchOperators.matches(api, operators: [.typed("api-secret")], context: .empty))
    }

    func testEnvironmentAndExpiryOperators() {
        let template = ItemTemplateRegistry.definition(for: .apiSecret)!
        var api = VaultItem(category: .custom, title: "T", fields: template.defaultFields)
        api.semantics = template.newItemSemantics
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        if let index = api.fields.firstIndex(where: { $0.roleID == .apiEnvironment }) {
            api.fields[index].value = "Production"
        }
        if let index = api.fields.firstIndex(where: { $0.roleID == .apiToken }) {
            var semantics = api.fields[index].semantics ?? FieldSemantics()
            semantics.lifecycle = FieldLifecycle(expiresAt: now.addingTimeInterval(10 * 86_400))
            api.fields[index].semantics = semantics
        }
        var context = SearchOperators.Context.empty
        context.now = now
        XCTAssertTrue(SearchOperators.matches(api, operators: [.environment("prod")], context: context))
        XCTAssertTrue(SearchOperators.matches(api, operators: [.expiresWithinDays(30)], context: context))
        XCTAssertFalse(SearchOperators.matches(api, operators: [.expiresWithinDays(5)], context: context))
    }

    // MARK: Git snippets

    func testGitSnippetsRequireExplicitRepoForClone() {
        let template = ItemTemplateRegistry.definition(for: .gitAccount)!
        var item = VaultItem(category: .custom, title: "GitHub", fields: template.defaultFields)
        item.semantics = template.newItemSemantics
        func set(_ role: FieldRoleID, _ value: String) {
            if let index = item.fields.firstIndex(where: { $0.roleID == role }) {
                item.fields[index].value = value
            } else {
                let descriptor = template.sections.flatMap(\.fields).first { $0.roleID == role }!
                var field = descriptor.makeField(sectionID: nil)
                field.value = value
                item.fields.append(field)
            }
        }
        set(.gitHost, "github.com")
        set(.gitUsername, "bervion")
        let accountOnly = GitSnippets.setupSnippet(for: item)!
        XCTAssertTrue(accountOnly.contains("ssh -T git@github.com"))
        XCTAssertFalse(accountOnly.contains("git clone"), "no clone promise without a repo path")

        set(.gitRepoPath, "bervion/vaultify")
        let withRepo = GitSnippets.setupSnippet(for: item)!
        XCTAssertTrue(withRepo.contains("git clone git@github.com:bervion/vaultify.git"))
    }

    func testGitSnippetShellQuotingCannotBreakOut() {
        XCTAssertEqual(GitSnippets.shellQuoted("ben'; rm -rf ~"),
                       "'ben'\\''; rm -rf ~'")
    }
}
