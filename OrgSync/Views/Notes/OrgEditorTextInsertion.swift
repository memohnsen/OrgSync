//
//  OrgEditorTextInsertion.swift
//  OrgSync
//
//  Pure text transformations for the editor toolbar. Keeping this separate
//  from UIKit makes every command's insertion and caret behavior testable.
//

import Foundation

struct OrgEditorTextInsertion: Equatable {
    let text: String
    let selection: NSRange

    static func applying(_ command: OrgEditorCommand,
                         to text: String,
                         selection: NSRange,
                         timestamp: String) -> OrgEditorTextInsertion {
        switch command {
        case .headline:
            insertAtLineStart("* ", into: text, selection: selection)
        case .todo:
            insertAtLineStart("* TODO ", into: text, selection: selection)
        case .checkbox:
            insertAtLineStart("- [ ] ", into: text, selection: selection)
        case .timestamp:
            insert(timestamp, into: text, selection: selection, separatesFromLineContent: true)
        case .scheduled:
            insert("SCHEDULED: \(timestamp)", into: text, selection: selection, separatesFromLineContent: true)
        case .deadline:
            insert("DEADLINE: \(timestamp)", into: text, selection: selection, separatesFromLineContent: true)
        case .priority:
            insert("[#A] ", into: text, selection: selection, separatesFromLineContent: true)
        case .tag:
            insert(":tag:", into: text, selection: selection, caretOffsetFromEnd: 1, separatesFromLineContent: true)
        case .bold:
            wrapSelection("*", "*", in: text, selection: selection)
        case .italic:
            wrapSelection("/", "/", in: text, selection: selection)
        case .underline:
            wrapSelection("_", "_", in: text, selection: selection)
        case .strike:
            wrapSelection("+", "+", in: text, selection: selection)
        case .code:
            wrapSelection("~", "~", in: text, selection: selection)
        case .link:
            insert("[[][]]", into: text, selection: selection, caretOffsetFromEnd: 4, separatesFromLineContent: true)
        case .comment:
            insertAtLineStart("# ", into: text, selection: selection)
        case .sourceBlock:
            insert("#+begin_src\n\n#+end_src", into: text, selection: selection, caretOffsetFromEnd: 10)
        }
    }

    private static func insert(_ snippet: String,
                               into text: String,
                               selection: NSRange,
                               caretOffsetFromEnd: Int = 0,
                               separatesFromLineContent: Bool = false) -> OrgEditorTextInsertion {
        let range = validRange(selection, in: text)
        let separator = separatesFromLineContent && range.length == 0
            ? inlineSeparators(in: text, at: range.location)
            : (before: "", after: "")
        let replacement = separator.before + snippet + separator.after
        let replaced = (text as NSString).replacingCharacters(in: range, with: replacement)
        let caret = range.location + (separator.before as NSString).length + (snippet as NSString).length - caretOffsetFromEnd
        return OrgEditorTextInsertion(text: replaced, selection: NSRange(location: caret, length: 0))
    }

    private static func inlineSeparators(in text: String, at location: Int) -> (before: String, after: String) {
        let nsText = text as NSString
        let left = location > 0 ? nsText.substring(with: nsText.rangeOfComposedCharacterSequence(at: location - 1)) : ""
        let right = location < nsText.length ? nsText.substring(with: nsText.rangeOfComposedCharacterSequence(at: location)) : ""
        return (
            before: left.isEmpty || left.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) ? "" : " ",
            after: right.isEmpty || right.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) ? "" : " "
        )
    }

    private static func wrapSelection(_ open: String,
                                      _ close: String,
                                      in text: String,
                                      selection: NSRange) -> OrgEditorTextInsertion {
        let range = validRange(selection, in: text)
        let selected = (text as NSString).substring(with: range)
        let replacement = open + selected + close
        let replaced = (text as NSString).replacingCharacters(in: range, with: replacement)
        let caret: Int
        if range.length == 0 {
            caret = range.location + (open as NSString).length
        } else {
            caret = range.location + (replacement as NSString).length
        }
        return OrgEditorTextInsertion(text: replaced, selection: NSRange(location: caret, length: 0))
    }

    private static func insertAtLineStart(_ prefix: String,
                                          into text: String,
                                          selection: NSRange) -> OrgEditorTextInsertion {
        let range = validRange(selection, in: text)
        let nsText = text as NSString
        let lineStart = nsText.lineRange(for: NSRange(location: range.location, length: 0)).location
        let replaced = nsText.replacingCharacters(in: NSRange(location: lineStart, length: 0), with: prefix)
        let caret = range.location + (prefix as NSString).length
        return OrgEditorTextInsertion(text: replaced, selection: NSRange(location: caret, length: 0))
    }

    private static func validRange(_ selection: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(selection.location, length))
        let selectedLength = max(0, min(selection.length, length - location))
        return NSRange(location: location, length: selectedLength)
    }
}
