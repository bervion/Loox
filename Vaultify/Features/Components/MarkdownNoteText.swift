import SwiftUI

/// Lightweight Markdown rendering for note fields: headings, bullet and
/// numbered lines, plus inline emphasis (bold, italic, code, links) — the
/// Markdown people actually write in notes, without a web view or a full
/// document parser. Unknown syntax falls back to the literal text.
struct MarkdownNoteText: View {
    let text: String

    private struct Block: Identifiable {
        enum Kind {
            case heading(level: Int)
            case bullet
            case numbered(label: String)
            case paragraph
            case blank
        }
        let id: Int
        let kind: Kind
        let content: AttributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    Text(block.content)
                        .vaultType(level == 1 ? .headline : .body)
                        .fontWeight(level == 1 ? .semibold : .medium)
                        .padding(.top, block.id == 0 ? 0 : Space.s1)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: "•")
                        Text(block.content)
                    }
                    .vaultType(.body)
                case .numbered(let label):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: label).monospacedDigit()
                        Text(block.content)
                    }
                    .vaultType(.body)
                case .paragraph:
                    Text(block.content).vaultType(.body)
                case .blank:
                    // A deliberate empty line — half a row of air, not a
                    // zero-height collapse that glues paragraphs together.
                    Spacer().frame(height: Space.s1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").enumerated().map { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return Block(id: index, kind: .blank, content: AttributedString())
            }
            if let headingBody = heading(of: trimmed) {
                return Block(id: index, kind: .heading(level: headingBody.level),
                             content: inline(headingBody.text))
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return Block(id: index, kind: .bullet,
                             content: inline(String(trimmed.dropFirst(2))))
            }
            if let numbered = numberedItem(of: trimmed) {
                return Block(id: index, kind: .numbered(label: numbered.label),
                             content: inline(numbered.text))
            }
            return Block(id: index, kind: .paragraph, content: inline(trimmed))
        }
    }

    private func heading(of line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...3).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return (hashes.count, String(rest.dropFirst()))
    }

    /// "1. text" / "12. text" — the label keeps the author's own number.
    private func numberedItem(of line: String) -> (label: String, text: String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return ("\(digits).", String(rest.dropFirst(2)))
    }

    /// Inline emphasis only — block structure is handled above, and
    /// whitespace inside a line must survive as typed.
    private func inline(_ line: String) -> AttributedString {
        (try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line)
    }
}
