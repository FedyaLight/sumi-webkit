//
//  UserScriptMetadata.swift
//  Sumi
//
//  Parses userscript/userstyle metadata blocks.
//  Port of the parse() logic from quoid/userscripts Functions.swift,
//  adapted for direct WKUserScript injection.
//

import Foundation

// MARK: - Enums

enum UserScriptRunAt: String, Codable {
    case documentStart = "document-start"
    case documentBody = "document-body"
    case documentEnd = "document-end"
    case documentIdle = "document-idle"
}

enum UserScriptInjectInto: String, Codable {
    case auto
    case content
    case page
}

enum UserScriptFileType: String, Codable {
    case javascript = "js"
    case css = "css"
}

// MARK: - Metadata Model

struct UserScriptMetadata {
    let name: String
    let description: String?
    let namespace: String?
    let version: String?
    let author: String?
    let icon: String?
    let homepageURL: String?
    let downloadURL: String?
    let updateURL: String?
    let supportURL: String?
    let license: String?
    /// @source (repository / canonical source URL)
    let sourceURL: String?
    /// @antifeature lines (Violentmonkey / OpenUserJS metadata)
    let antifeatures: [String]

    let matches: [String]
    let excludeMatches: [String]
    let includes: [String]
    let excludes: [String]

    let runAt: UserScriptRunAt
    let injectInto: UserScriptInjectInto
    let grants: [String]
    let requires: [String]
    /// Declarative WebKit / Sumi userscript compatibility modules (`// @sumi-compat webkit-media`).
    let sumiCompat: [String]
    let connects: [String]
    let noframes: Bool
    let unwrap: Bool
    let topLevelAwait: Bool
    let weight: Int

    let resources: [String: String] // name: url
    let localizedNames: [String: String]
    let localizedDescriptions: [String: String]

    let fileType: UserScriptFileType

    /// The raw metablock string (including delimiters)
    let metablock: String

    /// The script/style body code (after metablock)
    let code: String

    /// All raw key-value pairs from the metadata
    let rawMetadata: [String: [String]]

    /// Returns a copy with a different script body (e.g. WebKit compatibility transforms).
    func replacingCode(_ newCode: String) -> UserScriptMetadata {
        UserScriptMetadata(
            name: name,
            description: description,
            namespace: namespace,
            version: version,
            author: author,
            icon: icon,
            homepageURL: homepageURL,
            downloadURL: downloadURL,
            updateURL: updateURL,
            supportURL: supportURL,
            license: license,
            sourceURL: sourceURL,
            antifeatures: antifeatures,
            matches: matches,
            excludeMatches: excludeMatches,
            includes: includes,
            excludes: excludes,
            runAt: runAt,
            injectInto: injectInto,
            grants: grants,
            requires: requires,
            sumiCompat: sumiCompat,
            connects: connects,
            noframes: noframes,
            unwrap: unwrap,
            topLevelAwait: topLevelAwait,
            weight: weight,
            resources: resources,
            localizedNames: localizedNames,
            localizedDescriptions: localizedDescriptions,
            fileType: fileType,
            metablock: metablock,
            code: newCode,
            rawMetadata: rawMetadata
        )
    }
}

// MARK: - Parser

enum UserScriptMetadataParser {

    // RE for full metablock extraction
    // Group 1/2/3: SumiInstalledUserScript format (metablock, metas, code)
    // Group 4/5/6: UserStyle format (metablock, metas, code)
    private static let metablockRE = try! NSRegularExpression(
        pattern: #"(?:(\/\/ ==UserScript==[ \t]*?\r?\n([\S\s]*?)\r?\n\/\/ ==\/UserScript==)([\S\s]*)|(\/\* ==UserStyle==[ \t]*?\r?\n([\S\s]*?)\r?\n==\/UserStyle== \*\/)([\S\s]*))"#,
        options: []
    )

    // RE for key-value meta lines: // @key value
    private static let metaLineRE = try! NSRegularExpression(
        pattern: #"^(?:[ \t]*(?:\/\/)?[ \t]*@)([\w:-]+)[ \t]+([^\s]+[^\r\nt\v\f]*)"#,
        options: []
    )

    // RE for valueless meta keys (e.g. @noframes)
    private static let metaKeyOnlyRE = try! NSRegularExpression(
        pattern: #"^(?:[ \t]*(?:\/\/)?[ \t]*@)(noframes|unwrap|top-level-await)[ \t]*$"#,
        options: []
    )

    // RE for @resource: // @resource name url
    private static let resourceRE = try! NSRegularExpression(
        pattern: #"^(?:[ \t]*(?:\/\/)?[ \t]*@)resource[ \t]+([^\s]+)[ \t]+([^\s]+)"#,
        options: []
    )

    /// Parse a userscript/userstyle file content into structured metadata.
    /// Returns nil if metablock is missing or @name is absent.
    static func parse(_ content: String) -> UserScriptMetadata? {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        guard let match = metablockRE.firstMatch(in: content, options: [], range: fullRange) else {
            return nil
        }

        // Determine format: SumiInstalledUserScript (groups 1,2,3) or UserStyle (groups 4,5,6)
        let metablockGroupIdx: Int
        let metasGroupIdx: Int
        let codeGroupIdx: Int

        if match.range(at: 1).location != NSNotFound {
            metablockGroupIdx = 1
            metasGroupIdx = 2
            codeGroupIdx = 3
        } else if match.range(at: 4).location != NSNotFound {
            metablockGroupIdx = 4
            metasGroupIdx = 5
            codeGroupIdx = 6
        } else {
            return nil
        }

        guard let metablockRange = Range(match.range(at: metablockGroupIdx), in: content) else {
            return nil
        }
        let metablock = String(content[metablockRange])

        // Parse individual metadata lines
        var rawMetadata: [String: [String]] = [:]
        var resources: [String: String] = [:]

        if let metasRange = Range(match.range(at: metasGroupIdx), in: content) {
            let metaLines = content[metasRange].split(whereSeparator: \.isNewline)
            for line in metaLines {
                let lineStr = String(line).trimmingCharacters(in: .whitespaces)
                let lineRange = NSRange(location: 0, length: (lineStr as NSString).length)

                if let m = resourceRE.firstMatch(in: lineStr, options: [], range: lineRange),
                   let nameRange = Range(m.range(at: 1), in: lineStr),
                   let urlRange = Range(m.range(at: 2), in: lineStr)
                {
                    let name = String(lineStr[nameRange])
                    let url = String(lineStr[urlRange])
                    resources[name] = url
                } else if let m = metaLineRE.firstMatch(in: lineStr, options: [], range: lineRange),
                   let keyRange = Range(m.range(at: 1), in: lineStr),
                   let valueRange = Range(m.range(at: 2), in: lineStr)
                {
                    let key = String(lineStr[keyRange])
                    let value = String(lineStr[valueRange])
                    rawMetadata[key, default: []].append(value)
                } else if let m2 = metaKeyOnlyRE.firstMatch(in: lineStr, options: [], range: lineRange),
                          let keyRange = Range(m2.range(at: 1), in: lineStr)
                {
                    let key = String(lineStr[keyRange])
                    rawMetadata[key] = rawMetadata[key] ?? []
                }
            }
        }

        // @name is required
        guard let names = rawMetadata["name"], let name = names.first else {
            return nil
        }

        // Extract code body
        let code: String
        if let codeRange = Range(match.range(at: codeGroupIdx), in: content) {
            code = String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            code = ""
        }

        // Determine file type from content format
        let fileType: UserScriptFileType = metablockGroupIdx == 4 ? .css : .javascript

        // Parse @run-at
        let runAtStr = rawMetadata["run-at"]?.first ?? "document-end"
        let runAt = UserScriptRunAt(rawValue: runAtStr) ?? .documentEnd

        // Parse @inject-into
        let injectIntoStr = rawMetadata["inject-into"]?.first ?? "auto"
        let injectInto = UserScriptInjectInto(rawValue: injectIntoStr) ?? .auto

        // Parse @weight
        let weightStr = rawMetadata["weight"]?.first ?? "1"
        let weight = Self.normalizeWeight(weightStr)

        return UserScriptMetadata(
            name: name,
            description: rawMetadata["description"]?.first,
            namespace: rawMetadata["namespace"]?.first,
            version: rawMetadata["version"]?.first,
            author: rawMetadata["author"]?.first,
            icon: rawMetadata["icon"]?.first,
            homepageURL: rawMetadata["homepageURL"]?.first,
            downloadURL: rawMetadata["downloadURL"]?.first,
            updateURL: rawMetadata["updateURL"]?.first,
            supportURL: rawMetadata["supportURL"]?.first,
            license: rawMetadata["license"]?.first,
            sourceURL: rawMetadata["source"]?.first,
            antifeatures: rawMetadata["antifeature"] ?? [],
            matches: rawMetadata["match"] ?? [],
            excludeMatches: rawMetadata["exclude-match"] ?? [],
            includes: rawMetadata["include"] ?? [],
            excludes: rawMetadata["exclude"] ?? [],
            runAt: runAt,
            injectInto: injectInto,
            grants: rawMetadata["grant"] ?? [],
            requires: rawMetadata["require"] ?? [],
            sumiCompat: rawMetadata["sumi-compat"] ?? [],
            connects: rawMetadata["connect"] ?? [],
            noframes: rawMetadata["noframes"] != nil,
            unwrap: rawMetadata["unwrap"] != nil,
            topLevelAwait: rawMetadata["top-level-await"] != nil,
            weight: weight,
            resources: resources,
            localizedNames: Self.localizedValues(for: "name", in: rawMetadata),
            localizedDescriptions: Self.localizedValues(for: "description", in: rawMetadata),
            fileType: fileType,
            metablock: metablock,
            code: code,
            rawMetadata: rawMetadata
        )

    }

    private static func normalizeWeight(_ str: String) -> Int {
        guard let w = Int(str) else { return 1 }
        return min(999, max(1, w))
    }

    private static func localizedValues(
        for baseKey: String,
        in rawMetadata: [String: [String]]
    ) -> [String: String] {
        var result: [String: String] = [:]
        let prefix = "\(baseKey):"
        for (key, values) in rawMetadata where key.hasPrefix(prefix) {
            let locale = String(key.dropFirst(prefix.count)).lowercased()
            guard locale.isEmpty == false, let value = values.first else { continue }
            result[locale] = value
        }
        return result
    }
}
