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
    /// Assigns a standard org `:ID:` property to every TODO headline that
    /// lacks one. Returns whether serialization is required.
    @discardableResult
    public mutating func ensurePersistentIDsForTodoHeadlines() -> Bool {
        var changed = false
        func visit(_ headlines: inout [OrgHeadline], config: OrgTodoConfig) {
            for index in headlines.indices {
                if let keyword = headlines[index].todoKeyword, config.isKeyword(keyword),
                   headlines[index].persistentID == nil {
                    var drawer = headlines[index].propertyDrawer ?? OrgPropertyDrawer(properties: [])
                    drawer.properties.append(OrgProperty(key: "ID", value: UUID().uuidString.uppercased()))
                    drawer.beginRaw = nil; drawer.endRaw = nil
                    headlines[index].propertyDrawer = drawer
                    headlines[index].raw = nil
                    changed = true
                }
                visit(&headlines[index].children, config: config)
            }
        }
        visit(&headlines, config: todoConfig)
        return changed
    }
    /// Apply `transform` to the headline addressed by `path`.
    public mutating func mutateHeadline(at path: [Int], _ transform: (inout OrgHeadline) -> Void) {
        OrgDocument.mutate(&headlines, path: path, transform)
    }

    /// Apply `transform` to the headline identified by a stable outline. This
    /// is deliberately title-path based rather than index-path based so agenda
    /// and reminder records can survive a document being parsed again.
    @discardableResult
    public mutating func mutateHeadline(at outline: OrgOutline,
                                        _ transform: (inout OrgHeadline) -> Void) -> Bool {
        var match = 0
        return OrgDocument.mutate(&headlines, titles: [], outline: outline,
                                  match: &match, transform)
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

    private static func mutate(_ nodes: inout [OrgHeadline], titles: [String],
                               outline: OrgOutline, match: inout Int,
                               _ transform: (inout OrgHeadline) -> Void) -> Bool {
        for index in nodes.indices {
            let here = titles + [nodes[index].title]
            if here == outline.headingPath {
                if match == outline.index {
                    transform(&nodes[index])
                    return true
                }
                match += 1
            }
            if mutate(&nodes[index].children, titles: here, outline: outline,
                      match: &match, transform) {
                return true
            }
        }
        return false
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
