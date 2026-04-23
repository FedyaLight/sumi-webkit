import Foundation
import SQLite3

enum SumiBookmarkImportReaderKind: Equatable, Sendable {
    case html
    case safariPlist
    case chromiumJSON
    case firefoxSQLite
}

struct SumiBookmarkImportSource: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var fileURL: URL
    var kind: SumiBookmarkImportReaderKind

    func readBookmarks() throws -> [SumiImportedBookmarkNode] {
        switch kind {
        case .html:
            return try SumiBookmarkImportReaders.readHTML(from: fileURL)
        case .safariPlist:
            return try SumiBookmarkImportReaders.readSafariPlist(from: fileURL)
        case .chromiumJSON:
            return try SumiBookmarkImportReaders.readChromiumBookmarks(from: fileURL)
        case .firefoxSQLite:
            return try SumiBookmarkImportReaders.readFirefoxPlaces(from: fileURL)
        }
    }

    static func detectedBrowserSources(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SumiBookmarkImportSource] {
        let fileManager = FileManager.default
        var sources: [SumiBookmarkImportSource] = []

        func addFileSource(title: String, pathComponents: [String], kind: SumiBookmarkImportReaderKind) {
            var url = homeDirectory
            for component in pathComponents {
                url.appendPathComponent(component)
            }
            if fileManager.fileExists(atPath: url.path) {
                sources.append(
                    SumiBookmarkImportSource(
                        id: "\(title)-\(url.path)",
                        title: title,
                        fileURL: url,
                        kind: kind
                    )
                )
            }
        }

        addFileSource(
            title: "Safari",
            pathComponents: ["Library", "Safari", "Bookmarks.plist"],
            kind: .safariPlist
        )
        addFileSource(
            title: "Safari Technology Preview",
            pathComponents: ["Library", "SafariTechnologyPreview", "Bookmarks.plist"],
            kind: .safariPlist
        )

        let chromiumBases: [(String, [String])] = [
            ("Google Chrome", ["Library", "Application Support", "Google", "Chrome"]),
            ("Chromium", ["Library", "Application Support", "Chromium"]),
            ("Microsoft Edge", ["Library", "Application Support", "Microsoft Edge"]),
            ("Brave", ["Library", "Application Support", "BraveSoftware", "Brave-Browser"]),
            ("Opera", ["Library", "Application Support", "com.operasoftware.Opera"]),
            ("Opera GX", ["Library", "Application Support", "com.operasoftware.OperaGX"]),
            ("Vivaldi", ["Library", "Application Support", "Vivaldi"]),
            ("Yandex Browser", ["Library", "Application Support", "Yandex", "YandexBrowser"]),
            ("CocCoc", ["Library", "Application Support", "CocCoc", "Browser"]),
        ]

        for (name, components) in chromiumBases {
            let base = components.reduce(homeDirectory) { $0.appendingPathComponent($1, isDirectory: true) }
            sources.append(contentsOf: chromiumProfileSources(browserName: name, baseURL: base))
        }

        let firefoxProfiles = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Firefox", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
        sources.append(contentsOf: firefoxProfileSources(browserName: "Firefox", profilesURL: firefoxProfiles))

        let torProfiles = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("TorBrowser-Data", isDirectory: true)
            .appendingPathComponent("Browser", isDirectory: true)
        sources.append(contentsOf: firefoxProfileSources(browserName: "Tor Browser", profilesURL: torProfiles))

        return sources.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func chromiumProfileSources(browserName: String, baseURL: URL) -> [SumiBookmarkImportSource] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { profileURL in
            let bookmarksURL = profileURL.appendingPathComponent("Bookmarks")
            guard fileManager.fileExists(atPath: bookmarksURL.path) else { return nil }
            let profileName = profileURL.lastPathComponent == "Default" ? "Default" : profileURL.lastPathComponent
            return SumiBookmarkImportSource(
                id: "\(browserName)-\(profileName)-\(bookmarksURL.path)",
                title: "\(browserName) - \(profileName)",
                fileURL: bookmarksURL,
                kind: .chromiumJSON
            )
        }
    }

    private static func firefoxProfileSources(browserName: String, profilesURL: URL) -> [SumiBookmarkImportSource] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { profileURL in
            let placesURL = profileURL.appendingPathComponent("places.sqlite")
            guard fileManager.fileExists(atPath: placesURL.path) else { return nil }
            return SumiBookmarkImportSource(
                id: "\(browserName)-\(profileURL.lastPathComponent)-\(placesURL.path)",
                title: "\(browserName) - \(profileURL.lastPathComponent)",
                fileURL: placesURL,
                kind: .firefoxSQLite
            )
        }
    }
}

enum SumiBookmarkImportReaders {
    static func readHTML(from fileURL: URL) throws -> [SumiImportedBookmarkNode] {
        let html = try String(contentsOf: fileURL, encoding: .utf8)
        let lineParsed = parseBookmarkHTMLLines(html)
        if !lineParsed.isEmpty {
            return lineParsed
        }

        let data = Data(html.utf8)
        let document = try XMLDocument(data: data, options: [.documentTidyHTML])
        let dlNodes = try document.nodes(forXPath: "//dl")
        guard let rootDL = dlNodes.first else { return [] }
        return parseBookmarkHTMLDL(rootDL)
    }

    static func readChromiumBookmarks(from fileURL: URL) throws -> [SumiImportedBookmarkNode] {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(ChromiumBookmarksFile.self, from: data)
        var nodes: [SumiImportedBookmarkNode] = []

        if let bookmarkBarChildren = decoded.roots.bookmarkBar?.children,
           !bookmarkBarChildren.isEmpty {
            nodes.append(
                .folder(
                    title: "Bookmarks Bar",
                    children: bookmarkBarChildren.compactMap(importedNode(from:))
                )
            )
        }

        if let otherChildren = decoded.roots.other?.children,
           !otherChildren.isEmpty {
            nodes.append(contentsOf: otherChildren.compactMap(importedNode(from:)))
        }

        if let syncedChildren = decoded.roots.synced?.children,
           !syncedChildren.isEmpty {
            nodes.append(
                .folder(
                    title: "Mobile Bookmarks",
                    children: syncedChildren.compactMap(importedNode(from:))
                )
            )
        }

        return nodes
    }

    static func readSafariPlist(from fileURL: URL) throws -> [SumiImportedBookmarkNode] {
        let data = try Data(contentsOf: fileURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any] else { return [] }
        return parseSafariChildren(root["Children"] as? [[String: Any]] ?? [])
    }

    static func readFirefoxPlaces(from fileURL: URL) throws -> [SumiImportedBookmarkNode] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFirefoxBookmarks-\(UUID().uuidString).sqlite")
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: fileURL, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var database: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            throw SumiBookmarkError.importFailed("Could not open Firefox bookmarks database.")
        }
        defer { sqlite3_close(database) }

        let rootNodes = try firefoxChildren(parentID: 1, database: database)
        if !rootNodes.isEmpty {
            return rootNodes
        }
        return try firefoxChildren(parentID: 0, database: database)
    }

    private static func parseBookmarkHTMLDL(_ dl: XMLNode) -> [SumiImportedBookmarkNode] {
        let children = elementChildren(of: dl)
        var result: [SumiImportedBookmarkNode] = []
        var index = 0

        while index < children.count {
            let node = children[index]
            guard elementName(node) == "dt" else {
                index += 1
                continue
            }

            if let anchor = firstDescendantElement(named: "a", in: node),
               let href = (anchor as? XMLElement)?.attribute(forName: "href")?.stringValue,
               let url = URL(string: href) {
                result.append(.bookmark(title: anchor.stringValue ?? href, url: url))
            } else if let heading = firstDescendantElement(named: "h3", in: node) {
                let siblingDL = nextElement(after: index, in: children, named: "dl")
                let nestedDL = firstDescendantElement(named: "dl", in: node) ?? siblingDL
                let folderChildren = nestedDL.map(parseBookmarkHTMLDL) ?? []
                result.append(.folder(title: heading.stringValue ?? "Folder", children: folderChildren))
                if let nestedDL, let siblingDL, nestedDL === siblingDL {
                    index += 1
                }
            }
            index += 1
        }

        return result
    }

    private static func parseBookmarkHTMLLines(_ html: String) -> [SumiImportedBookmarkNode] {
        var stack: [(title: String?, children: [SumiImportedBookmarkNode])] = [(nil, [])]
        var pendingFolderTitle: String?

        for rawLine in html.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let folderTitle = firstRegexCapture(
                in: line,
                pattern: #"<H3[^>]*>(.*?)</H3>"#
            ) {
                pendingFolderTitle = htmlUnescaped(folderTitle)
                continue
            }

            if line.range(of: "<DL", options: [.caseInsensitive]) != nil {
                if let title = pendingFolderTitle {
                    stack.append((title, []))
                    pendingFolderTitle = nil
                }
                continue
            }

            if line.range(of: "</DL", options: [.caseInsensitive]) != nil {
                if stack.count > 1 {
                    let finished = stack.removeLast()
                    stack[stack.count - 1].children.append(
                        .folder(title: finished.title ?? "Folder", children: finished.children)
                    )
                }
                continue
            }

            guard let href = firstRegexCapture(
                in: line,
                pattern: #"<A[^>]*HREF="([^"]+)"[^>]*>(.*?)</A>"#,
                captureIndex: 1
            ),
                let title = firstRegexCapture(
                    in: line,
                    pattern: #"<A[^>]*HREF="([^"]+)"[^>]*>(.*?)</A>"#,
                    captureIndex: 2
                ),
                let url = URL(string: htmlUnescaped(href))
            else {
                continue
            }
            stack[stack.count - 1].children.append(.bookmark(title: htmlUnescaped(title), url: url))
        }

        while stack.count > 1 {
            let finished = stack.removeLast()
            stack[stack.count - 1].children.append(
                .folder(title: finished.title ?? "Folder", children: finished.children)
            )
        }

        return stack.first?.children ?? []
    }

    private static func firstRegexCapture(
        in string: String,
        pattern: String,
        captureIndex: Int = 1
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > captureIndex,
              let captureRange = Range(match.range(at: captureIndex), in: string)
        else {
            return nil
        }
        return String(string[captureRange])
    }

    private static func htmlUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func parseSafariChildren(_ children: [[String: Any]]) -> [SumiImportedBookmarkNode] {
        children.compactMap(parseSafariItem)
    }

    private static func parseSafariItem(_ item: [String: Any]) -> SumiImportedBookmarkNode? {
        let type = item["WebBookmarkType"] as? String
        let title = (item["URIDictionary"] as? [String: Any])?["title"] as? String
            ?? item["Title"] as? String
            ?? "Untitled"

        if type == "WebBookmarkTypeLeaf" {
            guard let urlString = item["URLString"] as? String,
                  let url = URL(string: urlString)
            else {
                return nil
            }
            return .bookmark(title: title, url: url)
        }

        guard type == "WebBookmarkTypeList" else { return nil }
        let folderTitle = item["Title"] as? String ?? title
        if folderTitle == "com.apple.ReadingList" {
            return nil
        }
        let children = parseSafariChildren(item["Children"] as? [[String: Any]] ?? [])
        if folderTitle == "BookmarksMenu" || folderTitle == "BookmarksBar" {
            return .folder(title: folderTitle == "BookmarksBar" ? "Bookmarks Bar" : "Bookmarks Menu", children: children)
        }
        return .folder(title: folderTitle, children: children)
    }

    private static func importedNode(from node: ChromiumBookmarkNode) -> SumiImportedBookmarkNode? {
        switch node.type {
        case "url":
            guard let urlString = node.url,
                  let url = URL(string: urlString)
            else {
                return nil
            }
            return .bookmark(title: node.name, url: url)
        case "folder":
            return .folder(title: node.name, children: (node.children ?? []).compactMap(importedNode(from:)))
        default:
            return nil
        }
    }

    private static func firefoxChildren(parentID: Int64, database: OpaquePointer) throws -> [SumiImportedBookmarkNode] {
        let sql = """
        SELECT b.id, b.type, b.title, p.url, b.guid
        FROM moz_bookmarks b
        LEFT JOIN moz_places p ON b.fk = p.id
        WHERE b.parent = ? AND b.type IN (1, 2)
        ORDER BY b.position ASC, b.id ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SumiBookmarkError.importFailed("Could not read Firefox bookmarks.")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, parentID)
        var nodes: [SumiImportedBookmarkNode] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let type = sqlite3_column_int(statement, 1)
            let title = sqliteString(statement, 2) ?? "Untitled"
            let urlString = sqliteString(statement, 3)
            let guid = sqliteString(statement, 4)

            if type == 2 {
                if guid == "tags________" || title.localizedCaseInsensitiveCompare("Tags") == .orderedSame {
                    continue
                }
                let children = try firefoxChildren(parentID: id, database: database)
                if !children.isEmpty {
                    nodes.append(.folder(title: title, children: children))
                }
            } else if type == 1,
                      let urlString,
                      let url = URL(string: urlString),
                      shouldImportFirefoxURL(url) {
                nodes.append(.bookmark(title: title, url: url))
            }
        }
        return nodes
    }

    private static func shouldImportFirefoxURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func sqliteString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func elementChildren(of node: XMLNode) -> [XMLNode] {
        (node.children ?? []).filter { $0.kind == .element }
    }

    private static func elementName(_ node: XMLNode) -> String {
        (node.name ?? "").lowercased()
    }

    private static func firstDescendantElement(named name: String, in node: XMLNode) -> XMLNode? {
        if elementName(node) == name {
            return node
        }
        for child in elementChildren(of: node) {
            if let result = firstDescendantElement(named: name, in: child) {
                return result
            }
        }
        return nil
    }

    private static func nextElement(after index: Int, in nodes: [XMLNode], named name: String) -> XMLNode? {
        let nextIndex = index + 1
        guard nodes.indices.contains(nextIndex),
              elementName(nodes[nextIndex]) == name
        else {
            return nil
        }
        return nodes[nextIndex]
    }
}

private struct ChromiumBookmarksFile: Decodable {
    let roots: ChromiumBookmarkRoots
}

private struct ChromiumBookmarkRoots: Decodable {
    let bookmarkBar: ChromiumBookmarkNode?
    let other: ChromiumBookmarkNode?
    let synced: ChromiumBookmarkNode?

    enum CodingKeys: String, CodingKey {
        case bookmarkBar = "bookmark_bar"
        case other
        case synced
    }
}

private struct ChromiumBookmarkNode: Decodable {
    let type: String
    let name: String
    let url: String?
    let children: [ChromiumBookmarkNode]?
}
