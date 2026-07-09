import AppKit
import Foundation
import UniformTypeIdentifiers

enum BrowserBookmarkImportSelection: Equatable {
    case htmlFile
    case source(SumiBookmarkImportSource)
}

@MainActor
protocol BrowserBookmarkImportExportPresenting: AnyObject {
    func promptImportSource(
        detectedSources: [SumiBookmarkImportSource]
    ) -> BrowserBookmarkImportSelection?
    func promptHTMLImportFile() -> URL?
    func promptUnreadableSafariBookmarksReplacement(
        source: SumiBookmarkImportSource,
        originalError: Error
    ) -> URL?
    func promptExportDestination(defaultFileName: String) -> URL?
    func showBookmarkResultAlert(title: String, message: String)
}

/// Import/export pipeline collaborator for `BrowserBookmarkCommandOwner`.
/// Not a BrowserManager lazy Owner — constructed and held privately by the command surface.
@MainActor
final class BrowserBookmarkImportExportOwner {
    private let bookmarkManager: @MainActor @Sendable () -> SumiBookmarkManager?
    private let detectedImportSources: @MainActor @Sendable () -> [SumiBookmarkImportSource]
    private let readBookmarks: @MainActor @Sendable (SumiBookmarkImportSource) throws -> [SumiBookmarkImportNode]
    private let presenter: any BrowserBookmarkImportExportPresenting

    init(
        bookmarkManager: @escaping @MainActor @Sendable () -> SumiBookmarkManager?,
        detectedImportSources: @escaping @MainActor @Sendable () -> [SumiBookmarkImportSource],
        readBookmarks: @escaping @MainActor @Sendable (SumiBookmarkImportSource) throws -> [SumiBookmarkImportNode],
        presenter: any BrowserBookmarkImportExportPresenting
    ) {
        self.bookmarkManager = bookmarkManager
        self.detectedImportSources = detectedImportSources
        self.readBookmarks = readBookmarks
        self.presenter = presenter
    }

    func importBookmarksFromMenu() {
        let detectedSources = detectedImportSources()
        guard !detectedSources.isEmpty else {
            importBookmarksFromHTMLFile()
            return
        }

        guard let selection = presenter.promptImportSource(detectedSources: detectedSources) else { return }
        switch selection {
        case .htmlFile:
            importBookmarksFromHTMLFile()
        case .source(let source):
            importBookmarks(from: source)
        }
    }

    func exportBookmarksFromMenu() {
        guard let bookmarkManager = bookmarkManager(),
              let destination = presenter.promptExportDestination(defaultFileName: "Bookmarks.html")
        else {
            return
        }

        do {
            try bookmarkManager.exportBookmarksHTML(to: destination)
            presenter.showBookmarkResultAlert(
                title: "Bookmarks Exported",
                message: "Bookmarks were exported to \(destination.lastPathComponent)."
            )
        } catch {
            presenter.showBookmarkResultAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importBookmarksFromHTMLFile() {
        guard let fileURL = presenter.promptHTMLImportFile() else { return }
        importBookmarks(
            from: SumiBookmarkImportSource(
                id: "html-\(fileURL.path)",
                title: fileURL.lastPathComponent,
                fileURL: fileURL,
                kind: .html
            )
        )
    }

    private func importBookmarks(from source: SumiBookmarkImportSource) {
        guard let bookmarkManager = bookmarkManager() else {
            presenter.showBookmarkResultAlert(
                title: "Import Failed",
                message: BrowserBookmarkCommandOwnerError.bookmarkManagerUnavailable.localizedDescription
            )
            return
        }

        do {
            let nodes = try readBookmarks(source)
            let summary = try bookmarkManager.importBookmarks(nodes)
            presenter.showBookmarkResultAlert(
                title: "Bookmarks Imported",
                message: "\(source.title): \(summary.message)"
            )
        } catch {
            if source.kind == .safariPlist {
                importUnreadableSafariBookmarks(source: source, originalError: error)
            } else {
                presenter.showBookmarkResultAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    private func importUnreadableSafariBookmarks(
        source: SumiBookmarkImportSource,
        originalError: Error
    ) {
        guard let fileURL = presenter.promptUnreadableSafariBookmarksReplacement(
            source: source,
            originalError: originalError
        ) else {
            presenter.showBookmarkResultAlert(title: "Import Failed", message: originalError.localizedDescription)
            return
        }

        let replacement = SumiBookmarkImportSource(
            id: "\(source.id)-manual",
            title: source.title,
            fileURL: fileURL,
            kind: source.kind
        )
        importBookmarks(from: replacement)
    }
}
