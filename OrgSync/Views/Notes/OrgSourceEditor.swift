//
//  OrgSourceEditor.swift
//  OrgSync
//
//  Plain-text org editor: a `UITextView` wrapper that live-highlights org syntax
//  (headline stars/keywords/priorities/tags, planning + inline timestamps, block
//  and keyword lines, comments, and inline emphasis) with subtle system colors,
//  plus a keyboard accessory bar with insertion shortcuts (headline, TODO,
//  checkbox, bold, italic, today's timestamp, link template).
//

import SwiftUI
import UIKit

struct OrgSourceEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = OrgSyntaxHighlighter.baseFont
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.typingAttributes = OrgSyntaxHighlighter.typingAttributes
        textView.attributedText = OrgSyntaxHighlighter.highlight(text)
        textView.inputAccessoryView = context.coordinator.makeAccessoryView()
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Only re-sync when an external change diverges from what's on screen.
        if textView.text != text {
            let selection = textView.selectedRange
            textView.attributedText = OrgSyntaxHighlighter.highlight(text)
            textView.selectedRange = selection
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: OrgSourceEditor
        weak var textView: UITextView?

        init(_ parent: OrgSourceEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            rehighlight(textView)
        }

        private func rehighlight(_ textView: UITextView) {
            // Skip while composing (e.g. CJK marked text) to avoid disrupting input.
            guard textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            textView.attributedText = OrgSyntaxHighlighter.highlight(textView.text)
            textView.selectedRange = selection
            textView.typingAttributes = OrgSyntaxHighlighter.typingAttributes
        }

        // MARK: Accessory bar

        func makeAccessoryView() -> UIView {
            let bar = UIToolbar()
            bar.autoresizingMask = .flexibleHeight

            func item(_ symbol: String, _ action: Selector, label: String) -> UIBarButtonItem {
                let button = UIBarButtonItem(image: UIImage(systemName: symbol),
                                             style: .plain, target: self, action: action)
                button.accessibilityLabel = label
                return button
            }
            let flexible = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }

            bar.items = [
                item("number", #selector(insertHeadline), label: "Insert headline"),
                flexible(),
                item("checklist.unchecked", #selector(insertTodo), label: "Insert TODO keyword"),
                flexible(),
                item("checkmark.square", #selector(insertCheckbox), label: "Insert checkbox"),
                flexible(),
                item("bold", #selector(insertBold), label: "Bold"),
                flexible(),
                item("italic", #selector(insertItalic), label: "Italic"),
                flexible(),
                item("calendar", #selector(insertTimestamp), label: "Insert today's date"),
                flexible(),
                item("link", #selector(insertLink), label: "Insert link"),
            ]
            bar.sizeToFit()
            return bar
        }

        @objc private func insertHeadline() { insertAtLineStart("* ") }
        @objc private func insertTodo() { insertAtLineStart("* TODO ") }
        @objc private func insertCheckbox() { insertAtLineStart("- [ ] ") }
        @objc private func insertBold() { wrapSelection("*", "*") }
        @objc private func insertItalic() { wrapSelection("/", "/") }
        @objc private func insertLink() { insertSnippet("[[][]]", caretOffsetFromEnd: 4) }

        @objc private func insertTimestamp() {
            let stamp = OrgTimestamp(date: Date(), isActive: true, includeTime: false).serialize()
            insertSnippet(stamp, caretOffsetFromEnd: 0)
        }

        // MARK: Insertion helpers

        private func insertSnippet(_ snippet: String, caretOffsetFromEnd: Int) {
            guard let textView else { return }
            let range = textView.selectedRange
            replace(range, with: snippet, in: textView)
            let caret = range.location + (snippet as NSString).length - caretOffsetFromEnd
            setCaret(to: caret, in: textView)
            commit(textView)
        }

        private func wrapSelection(_ open: String, _ close: String) {
            guard let textView else { return }
            let range = textView.selectedRange
            let ns = textView.text as NSString
            let selected = ns.substring(with: range)
            let replacement = open + selected + close
            replace(range, with: replacement, in: textView)
            if range.length == 0 {
                setCaret(to: range.location + (open as NSString).length, in: textView)
            } else {
                let end = range.location + (replacement as NSString).length
                setCaret(to: end, in: textView)
            }
            commit(textView)
        }

        private func insertAtLineStart(_ prefix: String) {
            guard let textView else { return }
            let ns = textView.text as NSString
            let caret = textView.selectedRange.location
            let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
            replace(NSRange(location: lineStart, length: 0), with: prefix, in: textView)
            setCaret(to: caret + (prefix as NSString).length, in: textView)
            commit(textView)
        }

        private func replace(_ range: NSRange, with string: String, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            textView.replace(textRange, withText: string)
        }

        private func setCaret(to location: Int, in textView: UITextView) {
            let clamped = max(0, min(location, (textView.text as NSString).length))
            textView.selectedRange = NSRange(location: clamped, length: 0)
        }

        private func commit(_ textView: UITextView) {
            parent.text = textView.text
            rehighlight(textView)
        }
    }
}

// MARK: - Highlighter

enum OrgSyntaxHighlighter {
    static let baseFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private static let boldFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)

    static let typingAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont, .foregroundColor: UIColor.label,
    ]

    static func highlight(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: baseFont, .foregroundColor: UIColor.label]
        )
        let full = text as NSString
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length),
                                 options: .byLines) { line, range, _, _ in
            guard let line else { return }
            styleLine(line, range: range, in: result)
        }
        applyInline(full, into: result)
        return result
    }

    // MARK: Line-level

    private static func styleLine(_ line: String, range: NSRange, in string: NSMutableAttributedString) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let leading = line.count - trimmed.count

        // Headlines: leading run of '*' then a space (or end of line).
        if line.first == "*" {
            let stars = line.prefix(while: { $0 == "*" })
            let afterStars = line.dropFirst(stars.count).first
            if afterStars == nil || afterStars == " " {
                string.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel,
                                    range: NSRange(location: range.location, length: stars.count))
                styleHeadlineBody(line, headingStart: range.location, starCount: stars.count, in: string)
                return
            }
        }

        // Planning lines.
        let planningKeywords = ["SCHEDULED:", "DEADLINE:", "CLOSED:"]
        if planningKeywords.contains(where: { trimmed.hasPrefix($0) }) {
            for keyword in planningKeywords {
                if let subRange = (line as NSString).range(of: keyword) as NSRange?,
                   subRange.location != NSNotFound {
                    string.addAttribute(.foregroundColor, value: UIColor.secondaryLabel,
                                        range: NSRange(location: range.location + subRange.location,
                                                       length: subRange.length))
                }
            }
            return
        }

        // Keyword / block lines (`#+...`).
        if trimmed.hasPrefix("#+") {
            string.addAttribute(.foregroundColor, value: UIColor.systemPurple,
                                range: NSRange(location: range.location + leading,
                                               length: range.length - leading))
            return
        }

        // Comment lines (`# ...`).
        if line == "#" || line.hasPrefix("# ") {
            string.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
        }
    }

    private static func styleHeadlineBody(_ line: String, headingStart: Int,
                                          starCount: Int, in string: NSMutableAttributedString) {
        let ns = line as NSString
        var cursor = starCount
        // Skip spaces after the stars.
        while cursor < ns.length, ns.character(at: cursor) == UInt16(UnicodeScalar(" ").value) {
            cursor += 1
        }
        // TODO keyword: an all-caps word.
        let rest = ns.substring(from: cursor)
        if let word = rest.split(separator: " ", maxSplits: 1).first,
           word.count > 1, word.allSatisfy({ $0.isLetter && $0.isUppercase }) {
            let doneLike: Set<String> = ["DONE", "CANCELLED", "CANCELED"]
            let color = doneLike.contains(String(word)) ? UIColor.systemGreen : UIColor.systemRed
            string.addAttribute(.foregroundColor, value: color,
                                range: NSRange(location: headingStart + cursor, length: word.count))
        }
        // Priority `[#A]`.
        if let priorityRange = ns.range(of: "\\[#[A-Z]\\]", options: .regularExpression) as NSRange?,
           priorityRange.location != NSNotFound {
            string.addAttribute(.foregroundColor, value: UIColor.systemOrange,
                                range: NSRange(location: headingStart + priorityRange.location,
                                               length: priorityRange.length))
        }
        // Trailing tags `:tag:tag:`.
        if let tagsRange = ns.range(of: ":[A-Za-z0-9_@#%:]+:\\s*$", options: .regularExpression) as NSRange?,
           tagsRange.location != NSNotFound {
            string.addAttribute(.foregroundColor, value: UIColor.systemBlue,
                                range: NSRange(location: headingStart + tagsRange.location,
                                               length: tagsRange.length))
        }
    }

    // MARK: Inline

    private static let timestampRegex = try? NSRegularExpression(
        pattern: "<\\d{4}-\\d{2}-\\d{2}[^>\\n]*>|\\[\\d{4}-\\d{2}-\\d{2}[^\\]\\n]*\\]")
    private static let linkRegex = try? NSRegularExpression(pattern: "\\[\\[[^\\]\\n]*\\]\\[[^\\]\\n]*\\]\\]|\\[\\[[^\\]\\n]*\\]\\]")
    private static let boldRegex = try? NSRegularExpression(pattern: "(?<![\\w*])\\*[^*\\s][^*\\n]*\\*(?![\\w*])")
    private static let codeRegex = try? NSRegularExpression(pattern: "~[^~\\n]+~|=[^=\\n]+=")

    private static func applyInline(_ text: NSString, into string: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        color(timestampRegex, in: text, whole: whole, with: UIColor.systemBlue, string: string)
        color(linkRegex, in: text, whole: whole, with: UIColor.systemBlue, string: string)
        color(codeRegex, in: text, whole: whole, with: UIColor.systemTeal, string: string)
        boldRegex?.enumerateMatches(in: text as String, range: whole) { match, _, _ in
            guard let match else { return }
            string.addAttribute(.font, value: boldFont, range: match.range)
        }
    }

    private static func color(_ regex: NSRegularExpression?, in text: NSString, whole: NSRange,
                              with uiColor: UIColor, string: NSMutableAttributedString) {
        regex?.enumerateMatches(in: text as String, range: whole) { match, _, _ in
            guard let match else { return }
            string.addAttribute(.foregroundColor, value: uiColor, range: match.range)
        }
    }
}
