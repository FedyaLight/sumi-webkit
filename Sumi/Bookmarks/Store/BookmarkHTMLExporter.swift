//
//  BookmarkHTMLExporter.swift
//
//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//

import Foundation

enum BookmarkHTMLExporter {
    static func exportBookmarksHTML(root: SumiBookmarkEntity) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]
        appendExportLines(for: root.children, indent: 1, to: &lines)
        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    private static func appendExportLines(
        for entities: [SumiBookmarkEntity],
        indent: Int,
        to lines: inout [String]
    ) {
        let prefix = String(repeating: "    ", count: indent)
        for entity in entities {
            let title = htmlEscaped(entity.title.nilIfTrimmedEmpty ?? "Untitled")
            if entity.isFolder {
                lines.append("\(prefix)<DT><H3>\(title)</H3>")
                lines.append("\(prefix)<DL><p>")
                appendExportLines(for: entity.children, indent: indent + 1, to: &lines)
                lines.append("\(prefix)</DL><p>")
            } else if let url = entity.url {
                lines.append("\(prefix)<DT><A HREF=\"\(htmlEscaped(url.absoluteString))\">\(title)</A>")
            }
        }
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
