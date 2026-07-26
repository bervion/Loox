import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lightweight Markdown rendering for note fields: headings, bullet and
/// numbered lines, plus inline emphasis (bold, italic, code, links) — the
/// Markdown people actually write in notes, without a web view or a full
/// document parser. Unknown syntax falls back to the literal text.
///
/// iOS renders the parsed document in a native `UITextView`: SwiftUI's
/// `.textSelection` can only grab a whole `Text` at once, and dragging its
/// handles is clumsy — notes deserve the real loupe-and-handles selection.
/// macOS keeps the SwiftUI stack (pointer selection already feels native).
struct MarkdownNoteText: View {
    let text: String
    @Environment(AppEnvironment.self) private var env

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
        #if os(iOS)
        SelectableNoteView(document: attributedDocument(),
                           linkColor: UIColor(env.theme.active.color(.accentText)))
        #else
        stackBody
        #endif
    }

    private var stackBody: some View {
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

    #if os(iOS)

    // MARK: UIKit document (concrete fonts — a text view doesn't interpret
    // the markdown parser's presentation intents the way SwiftUI Text does)

    /// The whole note as one attributed document: same block/inline treatment
    /// as the SwiftUI stack, expressed through fonts and paragraph styles.
    private func attributedDocument() -> NSAttributedString {
        let theme = env.theme.active
        let bodyColor = UIColor(Color(rgb: theme.primaryText))
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString()
        // Blank source lines become breathing room on the FOLLOWING paragraph
        // (a literal empty line in a text view costs a full line height).
        var spacingBefore: CGFloat = 0
        for block in blocks {
            if case .blank = block.kind { spacingBefore += Space.s1; continue }

            let font: UIFont
            var prefix = ""
            switch block.kind {
            case .heading(let level):
                font = level == 1
                    ? .preferredFont(forTextStyle: .headline)
                    : UIFontMetrics(forTextStyle: .body)
                        .scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
                if result.length > 0 { spacingBefore += Space.s1 }
            case .bullet:
                font = bodyFont
                prefix = "•  "
            case .numbered(let label):
                font = bodyFont
                prefix = "\(label) "
            case .paragraph, .blank:
                font = bodyFont
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = Space.s1
            paragraph.paragraphSpacingBefore = spacingBefore
            if !prefix.isEmpty {
                // Wrapped bullet/numbered lines align under the text, not the marker.
                paragraph.headIndent = ceil((prefix as NSString)
                    .size(withAttributes: [.font: font]).width)
            }
            spacingBefore = 0

            let line = NSMutableAttributedString()
            if !prefix.isEmpty {
                line.append(NSAttributedString(string: prefix, attributes: [
                    .font: font, .foregroundColor: bodyColor,
                ]))
            }
            line.append(resolvedInline(block.content, baseFont: font, color: bodyColor))
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
            }
            line.addAttribute(.paragraphStyle, value: paragraph,
                              range: NSRange(location: 0, length: line.length))
            result.append(line)
        }
        return result
    }

    /// Turns the markdown parser's inline intents (bold / italic / code /
    /// links) into concrete UIKit attributes on the base font.
    private func resolvedInline(_ content: AttributedString,
                                baseFont: UIFont, color: UIColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in content.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            if intent.contains(.code) {
                font = UIFontMetrics(forTextStyle: .body)
                    .scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
            } else {
                var traits = font.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    font = UIFont(descriptor: descriptor, size: 0)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color,
            ]
            if let link = run.link { attributes[.link] = link }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: String(content[run.range].characters),
                                          attributes: attributes))
        }
        return out
    }

    /// Non-editable, non-scrolling `UITextView` sized by SwiftUI's width
    /// proposal — native selection (loupe, draggable handles) and link taps.
    private struct SelectableNoteView: UIViewRepresentable {
        let document: NSAttributedString
        let linkColor: UIColor

        func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isScrollEnabled = false
            view.backgroundColor = .clear
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.adjustsFontForContentSizeCategory = true
            view.dataDetectorTypes = [.link]
            return view
        }

        func updateUIView(_ view: UITextView, context: Context) {
            view.attributedText = document
            view.linkTextAttributes = [.foregroundColor: linkColor]
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                          context: Context) -> CGSize? {
            guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
            let fitted = uiView.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: ceil(fitted.height))
        }
    }

    #endif
}
