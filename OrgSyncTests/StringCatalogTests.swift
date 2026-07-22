//
//  StringCatalogTests.swift
//  OrgSyncTests
//
//  Guards the hand-maintained .xcstrings catalogs: every translatable key must
//  carry all supported languages, and translations must keep the same format
//  specifiers and intent placeholders as the English key.
//

import Foundation
import Testing

@Suite struct StringCatalogTests {
    static let languages = ["de", "es", "fr", "ja", "pt-BR", "zh-Hans"]
    static let catalogs = [
        "OrgSync/Localizable.xcstrings",
        "OrgSync/AppShortcuts.xcstrings",
        "OrgSync/InfoPlist.xcstrings",
        "OrgSyncWidgets/Localizable.xcstrings",
    ]

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable { let state: String; let value: String }
                let stringUnit: StringUnit?
            }
            let shouldTranslate: Bool?
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func load(_ path: String) throws -> Catalog {
        let url = Self.repoRoot.appendingPathComponent(path)
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// Occurrences of format specifiers and ${...} placeholders, ignoring
    /// positional prefixes so "%1$lld" and "%lld" compare equal.
    private func placeholders(_ s: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let specifier = /%(?:\d+\$)?(@|lld|d|u|f|ld|lu|llu|s)/
        for match in s.matches(of: specifier) { counts["%\(match.output.1)", default: 0] += 1 }
        let intentVar = /\$\{[a-zA-Z]+\}/
        for match in s.matches(of: intentVar) { counts[String(match.output), default: 0] += 1 }
        return counts
    }

    @Test(arguments: catalogs)
    func everyTranslatableKeyHasAllLanguages(path: String) throws {
        let catalog = try load(path)
        #expect(catalog.sourceLanguage == "en")
        for (key, entry) in catalog.strings where entry.shouldTranslate != false && !key.isEmpty {
            let locs = entry.localizations ?? [:]
            for lang in Self.languages {
                let unit = locs[lang]?.stringUnit
                #expect(unit != nil, "\(path): \"\(key)\" missing \(lang)")
                if let unit {
                    #expect(unit.state == "translated", "\(path): \"\(key)\" \(lang) not translated")
                    #expect(!unit.value.isEmpty, "\(path): \"\(key)\" \(lang) empty")
                }
            }
        }
    }

    @Test(arguments: catalogs)
    func translationsPreservePlaceholders(path: String) throws {
        let catalog = try load(path)
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            // The English plural-suffix hack ("Conflict%@") is deliberately
            // dropped in translations via positional specifiers, so only
            // require that translations never introduce specifiers the key
            // lacks, and that %lld-style numeric specifiers are kept.
            let expected = placeholders(key)
            for (lang, loc) in entry.localizations ?? [:] {
                guard let value = loc.stringUnit?.value else { continue }
                let got = placeholders(value)
                for (spec, count) in got {
                    #expect(expected[spec, default: 0] >= count,
                            "\(path): \"\(key)\" \(lang) adds \(spec) not in the English key")
                }
                for (spec, count) in expected where spec.hasPrefix("${") {
                    #expect(got[spec, default: 0] == count,
                            "\(path): \"\(key)\" \(lang) must keep \(spec) exactly")
                }
                if let lld = expected["%lld"] {
                    #expect(got["%lld", default: 0] == lld,
                            "\(path): \"\(key)\" \(lang) must keep %lld count")
                }
            }
        }
    }

    @Test func widgetSharedKeysStayInSyncWithAppCatalog() throws {
        let app = try load("OrgSync/Localizable.xcstrings")
        let widget = try load("OrgSyncWidgets/Localizable.xcstrings")
        let shared = Set(app.strings.keys).intersection(widget.strings.keys)
        #expect(shared.contains("Favorites"))
        for key in shared {
            for lang in Self.languages {
                let a = app.strings[key]?.localizations?[lang]?.stringUnit?.value
                let w = widget.strings[key]?.localizations?[lang]?.stringUnit?.value
                #expect(a == w, "\"\(key)\" \(lang) differs between app (\(a ?? "nil")) and widget (\(w ?? "nil"))")
            }
        }
    }

    @Test func localizedBundlesDeclareTheDevelopmentLanguage() throws {
        for path in ["OrgSync-Info.plist", "OrgSyncWidgets-Info.plist"] {
            let url = Self.repoRoot.appendingPathComponent(path)
            let plist = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                format: nil
            ) as? [String: Any]
            #expect(plist?["CFBundleDevelopmentRegion"] as? String == "$(DEVELOPMENT_LANGUAGE)",
                    "\(path) must declare the project development language")
        }
    }
}
