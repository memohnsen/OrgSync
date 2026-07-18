//
//  OrgSourceEditor.swift
//  OrgSync
//
//  Plain-text org editor: a `UITextView` wrapper that live-highlights org syntax
//  (headline stars/keywords/priorities/tags, planning + inline timestamps, block
//  and keyword lines, comments, and inline emphasis) with subtle system colors,
//  plus a horizontally scrolling, configurable keyboard accessory palette for
//  common org insertion and emphasis commands.
//

import SwiftUI
import UIKit

struct OrgSourceEditor: UIViewRepresentable {
    @Binding var text: String
    let commands: [OrgEditorCommand]
    @Binding var isShowingToolbarCustomization: Bool

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
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityLabel = "Org source editor"
        textView.accessibilityHint = "Edit the org-formatted text for this note. Use the keyboard toolbar to insert common org syntax."
        textView.accessibilityIdentifier = "note.sourceEditor"
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.typingAttributes = OrgSyntaxHighlighter.typingAttributes
        textView.attributedText = OrgSyntaxHighlighter.highlight(text)
        textView.inputAccessoryView = context.coordinator.makeAccessoryView()
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.update(parent: self)
        // Only re-sync when an external change diverges from what's on screen.
        if textView.text != text {
            let selection = textView.selectedRange
            textView.attributedText = OrgSyntaxHighlighter.highlight(text)
            textView.selectedRange = selection
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: OrgSourceEditor
        weak var textView: UITextView?
        private var accessoryView: OrgEditorAccessoryView?
        private var pendingToolbarInsertion: OrgEditorToolbarPendingInsertion?

        init(_ parent: OrgSourceEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            pendingToolbarInsertion = nil
            parent.text = textView.text
            rehighlight(textView)
        }

        func update(parent: OrgSourceEditor) {
            self.parent = parent
            accessoryView?.update(commands: parent.commands)
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
            let accessory = OrgEditorAccessoryView(
                commands: parent.commands,
                commandAction: { [weak self] command in self?.perform(command) },
                editAction: { [weak self] in self?.parent.isShowingToolbarCustomization = true }
            )
            accessoryView = accessory
            return accessory
        }

        private func perform(_ command: OrgEditorCommand) {
            guard let textView else { return }
            let hadSelection = textView.selectedRange.length > 0
            let removedMatchingInsertion = resolvePendingInsertion(for: command, in: textView)
            guard !removedMatchingInsertion else { return }
            let textBeforeCommand = textView.text ?? ""

            switch command {
            case .headline: insertAtLineStart("* ")
            case .todo: insertAtLineStart("* TODO ")
            case .checkbox: insertAtLineStart("- [ ] ")
            case .timestamp: insertTimestamp()
            case .scheduled: insertSnippet("SCHEDULED: \(todayStamp())", caretOffsetFromEnd: 0)
            case .deadline: insertSnippet("DEADLINE: \(todayStamp())", caretOffsetFromEnd: 0)
            case .priority: insertSnippet("[#A] ", caretOffsetFromEnd: 0)
            case .tag: insertSnippet(":tag:", caretOffsetFromEnd: 1)
            case .bold: wrapSelection("*", "*")
            case .italic: wrapSelection("/", "/")
            case .underline: wrapSelection("_", "_")
            case .strike: wrapSelection("+", "+")
            case .code: wrapSelection("~", "~")
            case .link: insertSnippet("[[][]]", caretOffsetFromEnd: 4)
            case .comment: insertAtLineStart("# ")
            case .sourceBlock: insertSnippet("#+begin_src\n\n#+end_src", caretOffsetFromEnd: 10)
            }

            if !hadSelection {
                recordPendingInsertion(of: command, from: textBeforeCommand, in: textView)
            }
        }

        /// A generated snippet becomes replaceable only until the user edits the
        /// document themselves. This lets adjacent toolbar choices behave like a
        /// picker instead of leaving a trail of abandoned org syntax behind.
        /// Returns true when tapping the same untouched command removed its
        /// insertion, so the caller should not insert it again.
        private func resolvePendingInsertion(for command: OrgEditorCommand, in textView: UITextView) -> Bool {
            guard let pending = pendingToolbarInsertion,
                  OrgEditorToolbarInsertionPolicy.action(
                    pending: pending,
                    with: command,
                    currentText: textView.text ?? ""
                  ) != .none else {
                if pendingToolbarInsertion?.expectedText != textView.text {
                    pendingToolbarInsertion = nil
                }
                return false
            }

            replace(pending.range, with: "", in: textView)
            setCaret(to: pending.range.location, in: textView)
            commit(textView)
            pendingToolbarInsertion = nil
            return pending.command == command
        }

        private func recordPendingInsertion(of command: OrgEditorCommand, from before: String, in textView: UITextView) {
            let after = textView.text ?? ""
            pendingToolbarInsertion = OrgEditorToolbarInsertionPolicy.pendingInsertion(
                command: command,
                before: before,
                after: after
            )
        }

        private func todayStamp() -> String {
            OrgTimestamp(date: Date(), isActive: true, includeTime: false).serialize()
        }

        private func insertTimestamp() {
            insertSnippet(todayStamp(), caretOffsetFromEnd: 0)
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

private final class OrgEditorAccessoryView: UIToolbar {
    private let scrollView = UIScrollView()
    private let commandAction: (OrgEditorCommand) -> Void
    private let editAction: () -> Void
    private var displayedCommands: [OrgEditorCommand] = []
    private var controls: [UIView] = []

    init(commands: [OrgEditorCommand],
         commandAction: @escaping (OrgEditorCommand) -> Void,
         editAction: @escaping () -> Void) {
        self.commandAction = commandAction
        self.editAction = editAction
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 52))

        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isAccessibilityElement = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.isAccessibilityElement = false
        addSubview(scrollView)
        update(commands: commands)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds.insetBy(dx: 4, dy: 4)

        var x: CGFloat = 8
        let height = scrollView.bounds.height
        for control in controls {
            let width: CGFloat = control.accessibilityIdentifier == "editor.command.separator" ? 1 : 44
            let controlHeight = control.accessibilityIdentifier == "editor.command.separator" ? 26 : height
            control.frame = CGRect(x: x, y: (height - controlHeight) / 2, width: width, height: controlHeight)
            x += width + (control.accessibilityIdentifier == "editor.command.separator" ? 10 : 8)
        }
        scrollView.contentSize = CGSize(width: x, height: height)
    }

    func update(commands: [OrgEditorCommand]) {
        guard commands != displayedCommands else { return }
        displayedCommands = commands
        controls.forEach { $0.removeFromSuperview() }
        controls.removeAll()

        for command in commands {
            var configuration = UIButton.Configuration.gray()
            configuration.image = UIImage(systemName: command.symbol)
            configuration.buttonSize = .medium
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = .label
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.commandAction(command)
            })
            button.accessibilityLabel = command.title
            button.accessibilityHint = "Inserts \(command.title.lowercased()) org syntax."
            button.accessibilityIdentifier = "editor.command.\(command.rawValue)"
            scrollView.addSubview(button)
            controls.append(button)
        }

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.accessibilityIdentifier = "editor.command.separator"
        scrollView.addSubview(separator)
        controls.append(separator)

        var editConfiguration = UIButton.Configuration.gray()
        editConfiguration.image = UIImage(systemName: "slider.horizontal.3")
        editConfiguration.buttonSize = .medium
        editConfiguration.cornerStyle = .capsule
        editConfiguration.baseForegroundColor = .label
        let editButton = UIButton(configuration: editConfiguration, primaryAction: UIAction { [weak self] _ in
            self?.editAction()
        })
        editButton.accessibilityLabel = "Edit toolbar"
        editButton.accessibilityHint = "Choose, remove, and reorder editor commands."
        editButton.accessibilityIdentifier = "editor.command.editToolbar"
        scrollView.addSubview(editButton)
        controls.append(editButton)
        accessibilityElements = controls.filter { $0.accessibilityIdentifier != "editor.command.separator" }
        setNeedsLayout()
    }
}

// MARK: - Highlighter

enum OrgSyntaxHighlighter {
    static var baseFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }
    private static var boldFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .bold)
    }

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
