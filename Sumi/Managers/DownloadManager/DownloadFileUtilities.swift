import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

enum DownloadsDirectoryResolver {
    static func resolvedDownloadsDirectory(fileManager: FileManager = .default) -> URL {
        if useIsolatedDirectory {
            let dir = isolatedRoot(fileManager: fileManager).appendingPathComponent("SumiDownloads", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        return fileManager.temporaryDirectory
    }

    private static var useIsolatedDirectory: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["SUMI_TEST_DOWNLOADS_ISOLATION"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--uitest-smoke") { return true }
        if env["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }

    private static func isolatedRoot(fileManager: FileManager) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["SUMI_APP_SUPPORT_OVERRIDE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("TestDownloads", isDirectory: true)
        }
        if let tmp = env["TMPDIR"], !tmp.isEmpty {
            return URL(fileURLWithPath: tmp, isDirectory: true)
        }
        return fileManager.temporaryDirectory
    }
}

enum DownloadFileUtilities {
    static let incompleteDownloadExtension = "sumiload"

    static func sanitizedFilename(_ filename: String, fallbackExtension: String? = nil) -> String {
        var clean = (filename.removingPercentEncoding ?? filename)
            .replacingOccurrences(of: "[~#@*+%{}<>\\[\\]|\"\\_^\\/:\\\\]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.isEmpty {
            clean = "download"
        }

        if (clean as NSString).pathExtension.isEmpty,
           let fallbackExtension,
           !fallbackExtension.isEmpty {
            clean += ".\(fallbackExtension)"
        }

        return clean
    }

    static func suggestedFilename(
        response: URLResponse?,
        requestURL: URL?,
        fallback: String = "download"
    ) -> String {
        if let responseSuggested = response?.suggestedFilename,
           !responseSuggested.isEmpty {
            return responseSuggested
        }

        if let requestSuggested = requestURL?.sumiSuggestedDownloadFilename,
           !requestSuggested.isEmpty {
            return requestSuggested
        }

        return fallback
    }

    static func uniqueDestination(for filename: String, fileManager: FileManager = .default) -> URL {
        let directory = DownloadsDirectoryResolver.resolvedDownloadsDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let cleanName = sanitizedFilename(filename)
        let desired = directory.appendingPathComponent(cleanName)
        return uniqueURL(for: desired, fileManager: fileManager)
    }

    static func uniqueURL(for desiredURL: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: desiredURL.path) else {
            return desiredURL
        }

        let directory = desiredURL.deletingLastPathComponent()
        let ext = desiredURL.pathExtension
        let base = desiredURL.deletingPathExtension().lastPathComponent
        var counter = 1

        while true {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    static func incompleteURL(for destinationURL: URL, fileManager: FileManager = .default) -> URL {
        let ext = destinationURL.pathExtension
        let incompleteExtension = ext.isEmpty ? incompleteDownloadExtension : "\(ext).\(incompleteDownloadExtension)"
        let desired = destinationURL.deletingPathExtension().appendingPathExtension(incompleteExtension)
        return uniqueURL(for: desired, fileManager: fileManager)
    }

    static func removeOrphanedIncompleteDownloads(fileManager: FileManager = .default) {
        let directory = DownloadsDirectoryResolver.resolvedDownloadsDirectory(fileManager: fileManager)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension == incompleteDownloadExtension {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    static func openDownloadsFolder(selecting itemToSelect: URL? = nil) {
        let folder = DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        if let itemToSelect,
           FileManager.default.fileExists(atPath: itemToSelect.path) {
            NSWorkspace.shared.activateFileViewerSelecting([itemToSelect])
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
}

extension URL {
    var sumiSuggestedDownloadFilename: String? {
        if !lastPathComponent.isEmpty, pathComponents != ["/"] {
            return lastPathComponent
        }
        return host?.replacingOccurrences(of: ".", with: "_")
    }
}
