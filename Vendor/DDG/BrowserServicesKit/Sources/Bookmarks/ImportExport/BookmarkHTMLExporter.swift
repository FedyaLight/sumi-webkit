//
//  BookmarkHTMLExporter.swift
//

import CoreData
import Foundation

public enum BookmarkHTMLExporter {
    public static func exportBookmarksHTML(root: BookmarkEntity) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]
        appendExportLines(for: root.childrenArray, indent: 1, to: &lines)
        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    public static func exportBookmarksHTML(from context: NSManagedObjectContext) throws -> String {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            throw BookmarkImportExportError.missingRootFolder
        }
        return exportBookmarksHTML(root: root)
    }

    public static func exportBookmarksHTML(from context: NSManagedObjectContext, to destination: URL) throws {
        do {
            try exportBookmarksHTML(from: context).write(to: destination, atomically: true, encoding: .utf8)
        } catch let error as BookmarkImportExportError {
            throw error
        } catch {
            throw BookmarkImportExportError.exportFailed(error.localizedDescription)
        }
    }

    private static func appendExportLines(
        for entities: [BookmarkEntity],
        indent: Int,
        to lines: inout [String]
    ) {
        let prefix = String(repeating: "    ", count: indent)
        for entity in entities {
            let title = htmlEscaped(entity.title?.nilIfTrimmedEmpty ?? "Untitled")
            if entity.isFolder {
                lines.append("\(prefix)<DT><H3>\(title)</H3>")
                lines.append("\(prefix)<DL><p>")
                appendExportLines(for: entity.childrenArray, indent: indent + 1, to: &lines)
                lines.append("\(prefix)</DL><p>")
            } else if let urlString = entity.url,
                      let url = URL(string: urlString) {
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
