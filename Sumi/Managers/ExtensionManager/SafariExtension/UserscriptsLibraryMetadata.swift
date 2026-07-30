import Foundation

struct UserscriptLibraryFile: Sendable {
    let url: URL
    let filename: String
    let type: String
    let content: String
    let code: String
    let metablock: String
    let metadata: [String: [String]]
    let modifiedAt: Date

    var name: String { metadata["name"]?.first ?? filename }
    var runAt: String { metadata["run-at"]?.first ?? "document-end" }
    var noframes: Bool { metadata["noframes"] != nil }
}

struct UserscriptsLibraryManifest: Codable {
    var blacklist: [String] = []
    var declarativeNetRequest: [String] = []
    var disabled: [String] = []
    var exclude: [String: [String]] = [:]
    var excludeMatch: [String: [String]] = [:]
    var include: [String: [String]] = [:]
    var match: [String: [String]] = [:]
    var require: [String: [String]] = [:]
    var settings: [String: String] = Self.defaultSettings

    enum CodingKeys: String, CodingKey {
        case blacklist, declarativeNetRequest, disabled, exclude, include, match, require, settings
        case excludeMatch = "exclude-match"
    }

    static let defaultSettings = [
        "active": "true",
        "autoCloseBrackets": "true",
        "autoHint": "true",
        "descriptions": "true",
        "languageCode": Locale.current.language.languageCode?.identifier ?? "en",
        "lint": "false",
        "log": "false",
        "sortOrder": "lastModifiedDesc",
        "showCount": "true",
        "showInvisibles": "true",
        "tabSize": "4",
    ]
}

struct UserscriptsMetadataPolicy: Sendable {
    func matchingFiles(
        url: String,
        files: [UserscriptLibraryFile],
        manifest: UserscriptsLibraryManifest,
        includeDisabled: Bool = false,
        respectsActivation: Bool = true,
        respectsBlacklist: Bool = true
    ) -> [UserscriptLibraryFile] {
        if respectsActivation, manifest.settings["active"] != "true" { return [] }
        if respectsBlacklist,
           manifest.blacklist.contains(where: {
               matchesMatchPattern(url: url, pattern: $0)
           }) { return [] }

        return files.filter { file in
            guard (includeDisabled || manifest.disabled.contains(file.filename) == false),
                  file.runAt != "request" else { return false }
            let included = (file.metadata["match"] ?? []).contains {
                matchesMatchPattern(url: url, pattern: $0)
            } || (file.metadata["include"] ?? []).contains {
                matchesIncludePattern(url: url, pattern: $0)
            }
            let excluded = (file.metadata["exclude-match"] ?? []).contains {
                matchesMatchPattern(url: url, pattern: $0)
            } || (file.metadata["exclude"] ?? []).contains {
                matchesIncludePattern(url: url, pattern: $0)
            }
            return included && excluded == false
        }
    }

    func matchesMatchPattern(url: String, pattern: String) -> Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return false }
        if pattern == "<all_urls>" { return scheme == "http" || scheme == "https" }

        guard let separator = pattern.range(of: "://") else { return false }
        let patternScheme = String(pattern[..<separator.lowerBound]).lowercased()
        let remainder = pattern[separator.upperBound...]
        guard let slash = remainder.firstIndex(of: "/") else { return false }
        let patternHost = String(remainder[..<slash]).lowercased()
        let patternPath = String(remainder[slash...])

        let schemeMatches = patternScheme == "*"
            ? scheme == "http" || scheme == "https"
            : patternScheme == scheme
        guard schemeMatches else { return false }

        let hostMatches: Bool
        if patternHost == "*" {
            hostMatches = true
        } else if patternHost.hasPrefix("*.") {
            let suffix = String(patternHost.dropFirst(2))
            hostMatches = host == suffix || host.hasSuffix("." + suffix)
        } else {
            hostMatches = host == patternHost
        }
        guard hostMatches else { return false }

        let pathAndQuery = components.percentEncodedPath
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        return globMatches(pathAndQuery, pattern: patternPath, caseInsensitive: false)
    }

    func matchesIncludePattern(url: String, pattern: String) -> Bool {
        if pattern.count >= 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
            let expression = String(pattern.dropFirst().dropLast())
            return url.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return globMatches(url, pattern: pattern, caseInsensitive: true)
    }

    func globMatches(
        _ value: String,
        pattern: String,
        caseInsensitive: Bool
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return value.range(of: "^\(escaped)$", options: options) != nil
    }

    func fileDictionary(
        _ file: UserscriptLibraryFile,
        disabledFilenames: Set<String> = []
    ) -> [String: Any] {
        var result: [String: Any] = [
            "canUpdate": file.metadata["version"] != nil && file.metadata["updateURL"] != nil,
            "content": file.content,
            "disabled": disabledFilenames.contains(file.filename),
            "filename": file.filename,
            "lastModified": Int(file.modifiedAt.timeIntervalSince1970 * 1_000),
            "metadata": file.metadata,
            "name": file.name,
            "noframes": file.noframes,
            "type": file.type,
        ]
        if let description = file.metadata["description"]?.first {
            result["description"] = description
        }
        if file.runAt == "request" { result["request"] = true }
        return result
    }

    func scriptObject(for file: UserscriptLibraryFile) -> [String: Any] {
        let grants = normalizedGrants(file.metadata["grant"] ?? [])
        var object: [String: Any] = [
            "description": file.metadata["description"]?.first ?? "",
            "excludes": file.metadata["exclude"] ?? [],
            "exclude-match": file.metadata["exclude-match"] ?? [],
            "filename": file.filename,
            "grant": grants,
            "icon": file.metadata["icon"]?.first ?? "",
            "includes": file.metadata["include"] ?? [],
            "inject-into": normalizedInjectInto(file.metadata["inject-into"]?.first),
            "matches": file.metadata["match"] ?? [],
            "name": file.name,
            "noframes": file.noframes,
            "namespace": file.metadata["namespace"]?.first ?? "",
            "resources": file.metadata["resource"] ?? [],
            "require": file.metadata["require"] ?? [],
            "run-at": normalizedRunAt(file.runAt),
            "version": file.metadata["version"]?.first ?? "",
        ]
        for (key, value) in file.metadata where object[key] == nil {
            object[key] = value.count == 1 ? value[0] : value
        }
        return object
    }

    func isAllowedFilename(_ filename: String) -> Bool {
        guard filename.isEmpty == false, filename.utf8.count <= 250 else { return false }
        let lower = filename.lowercased()
        return lower.hasSuffix(".js") || lower.hasSuffix(".css")
    }

    func fileType(_ filename: String) -> String? {
        if filename.lowercased().hasSuffix(".js") { return "js" }
        if filename.lowercased().hasSuffix(".css") { return "css" }
        return nil
    }

    func parse(content: String) -> (
        metadata: [String: [String]], code: String, metablock: String
    )? {
        let markers = [
            ("// ==UserScript==", "// ==/UserScript=="),
            ("/* ==UserStyle==", "==/UserStyle== */"),
        ]
        guard let markers = markers.first(where: {
            content.range(of: $0.0) != nil && content.range(of: $0.1) != nil
        }),
        let start = content.range(of: markers.0),
        let end = content.range(of: markers.1, range: start.upperBound..<content.endIndex)
        else {
            return nil
        }

        let metablock = String(content[start.lowerBound..<end.upperBound])
        var metadata: [String: [String]] = [:]
        for rawLine in metablock.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("*") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("@") else { continue }
            let body = line.dropFirst()
            let parts = body.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard let keyPart = parts.first else { continue }
            let key = String(keyPart)
            let value = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            metadata[key, default: []].append(value)
        }
        guard metadata["name"]?.first?.isEmpty == false else { return nil }
        let code = String(content[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (metadata, code, metablock)
    }

    func append(
        _ filename: String,
        values: [String],
        to dictionary: inout [String: [String]]
    ) {
        for value in values where value.isEmpty == false {
            if dictionary[value, default: []].contains(filename) == false {
                dictionary[value, default: []].append(filename)
                dictionary[value]?.sort()
            }
        }
    }

    func normalizedWeight(_ value: String?) -> String {
        String(min(999, max(1, Int(value ?? "1") ?? 1)))
    }

    func boolLike(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    func normalizedInjectInto(_ value: String?) -> String {
        ["auto", "content", "page"].contains(value ?? "") ? value! : "auto"
    }

    func normalizedRunAt(_ value: String) -> String {
        ["context-menu", "document-start", "document-end", "document-idle"].contains(value)
            ? value
            : "document-end"
    }

    func normalizedGrants(_ grants: [String]) -> [String] {
        if grants.contains("none") { return [] }
        let supported: Set<String> = [
            "GM.info", "GM_info", "GM.addStyle", "GM.openInTab", "GM.closeTab",
            "GM.setValue", "GM.getValue", "GM.deleteValue", "GM.listValues",
            "GM.setClipboard", "GM.getTab", "GM.saveTab", "GM_xmlhttpRequest",
            "GM.xmlHttpRequest",
        ]
        return Array(Set(grants).intersection(supported)).sorted()
    }

    func sanitizeFilename(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix(".") { result = "%2" + result.dropFirst() }
        return result
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "\\", with: "%5C")
    }

    func sanitizeResourceName(_ value: String) -> String {
        let sanitized = sanitizeFilename(value)
        guard sanitized.utf8.count > 180 else { return sanitized }
        let prefix = String(sanitized.prefix(140))
        return prefix + "-" + stableHexDigest(value)
    }

    func validatedRemoteURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    func stableHexDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

}
