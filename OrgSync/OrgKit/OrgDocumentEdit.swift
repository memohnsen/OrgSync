//
//  OrgDocumentEdit.swift
//  OrgSync
//
//  Small index-path addressing helpers on `OrgDocument`, used by the rendered
//  note view to mutate a specific headline (TODO/priority changes) or a
//  checkbox inside a headline body / the preamble. An index path is the chain
//  of child indices from a top-level headline down to the target.
//

import Foundation

extension OrgDocument {
    /// Apply `transform` to the headline addressed by `path`.
    public mutating func mutateHeadline(at path: [Int], _ transform: (inout OrgHeadline) -> Void) {
        OrgDocument.mutate(&headlines, path: path, transform)
    }

    private static func mutate(_ nodes: inout [OrgHeadline], path: [Int],
                               _ transform: (inout OrgHeadline) -> Void) {
        guard let first = path.first, nodes.indices.contains(first) else { return }
        if path.count == 1 {
            transform(&nodes[first])
        } else {
            mutate(&nodes[first].children, path: Array(path.dropFirst()), transform)
        }
    }

    /// Toggle a checkbox inside the `contentIndex`-th body element (a list) of
    /// the headline at `headlinePath`, addressing the item by `itemPath`.
    public mutating func toggleCheckbox(headlinePath: [Int], contentIndex: Int, itemPath: [Int]) {
        mutateHeadline(at: headlinePath) { headline in
            guard headline.body.indices.contains(contentIndex),
                  case .list(var list) = headline.body[contentIndex] else { return }
            list.cycleCheckbox(at: itemPath)
            headline.body[contentIndex] = .list(list)
            headline.updateStatisticsCookies()
        }
    }

    /// Toggle a checkbox inside a preamble list element.
    public mutating func togglePreambleCheckbox(contentIndex: Int, itemPath: [Int]) {
        guard preamble.indices.contains(contentIndex),
              case .list(var list) = preamble[contentIndex] else { return }
        list.cycleCheckbox(at: itemPath)
        preamble[contentIndex] = .list(list)
    }
}
