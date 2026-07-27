import AppKit
import Combine
import Foundation

struct DownloadFlyAnimationOrigin: Equatable {
    let windowNumber: Int
    let sourceRectInWindow: NSRect
    let nativeOriginalRect: NSRect?
}

struct DownloadFlyAnimationRequest: Equatable, Identifiable {
    let id = UUID()
    let windowNumber: Int
    let sourceRectInWindow: NSRect
    let icon: NSImage
}

@MainActor
final class DownloadFlyAnimationCenter {
    let requests = PassthroughSubject<DownloadFlyAnimationRequest, Never>()

    func requestFallback(
        from origin: DownloadFlyAnimationOrigin,
        icon: NSImage
    ) {
        requests.send(
            DownloadFlyAnimationRequest(
                windowNumber: origin.windowNumber,
                sourceRectInWindow: origin.sourceRectInWindow,
                icon: icon
            )
        )
    }
}

@MainActor
protocol DockDownloadDestinationChecking: AnyObject {
    func containsDestinationFolder(for fileURL: URL) -> Bool
}

@MainActor
final class SystemDockDownloadDestinationChecker: DockDownloadDestinationChecking {
    private struct Cache {
        let modificationDate: Date?
        let folderPaths: Set<String>
    }

    private let dockPlistURL: URL
    private let fileManager: FileManager
    private var cache: Cache?

    init(
        dockPlistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist"),
        fileManager: FileManager = .default
    ) {
        self.dockPlistURL = dockPlistURL
        self.fileManager = fileManager
    }

    func containsDestinationFolder(for fileURL: URL) -> Bool {
        let folderPath = Self.normalizedPath(
            fileURL.deletingLastPathComponent()
        )
        return dockFolderPaths().contains(folderPath)
    }

    private func dockFolderPaths() -> Set<String> {
        let attributes = try? fileManager.attributesOfItem(
            atPath: dockPlistURL.path
        )
        let modificationDate = attributes?[.modificationDate] as? Date
        if let cache, cache.modificationDate == modificationDate {
            return cache.folderPaths
        }

        let folderPaths: Set<String>
        if let data = try? Data(contentsOf: dockPlistURL),
           let propertyList = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            folderPaths = Self.folderPaths(from: propertyList["persistent-others"])
        } else {
            folderPaths = []
        }

        cache = Cache(
            modificationDate: modificationDate,
            folderPaths: folderPaths
        )
        return folderPaths
    }

    static func folderPaths(from persistentOthers: Any?) -> Set<String> {
        guard let items = persistentOthers as? [[String: Any]] else {
            return []
        }

        return Set(items.compactMap { item in
            guard item["tile-type"] as? String == "directory-tile",
                  let tileData = item["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String,
                  let url = URL(string: urlString),
                  url.isFileURL
            else {
                return nil
            }
            return normalizedPath(url)
        })
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
