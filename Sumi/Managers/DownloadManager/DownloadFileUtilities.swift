import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers
import WebKit

enum DownloadsDirectoryResolver {
    static func resolvedDownloadsDirectory(fileManager: FileManager = .default) -> URL {
        if usesIsolatedDirectory {
            let dir = isolatedRoot(fileManager: fileManager).appendingPathComponent("SumiDownloads", isDirectory: true)
            DownloadFileUtilities.ensureDirectoryExists(
                dir,
                fileManager: fileManager,
                context: "isolated downloads directory"
            )
            return dir
        }
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        return fileManager.temporaryDirectory
    }

    static var usesIsolatedDirectory: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["SUMI_TEST_DOWNLOADS_ISOLATION"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--uitest-smoke") { return true }
        if env["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }

    private static func isolatedRoot(fileManager: FileManager) -> URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let override = env["SUMI_APP_SUPPORT_OVERRIDE"], !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("TestDownloads", isDirectory: true)
        } else if let tmp = env["TMPDIR"], !tmp.isEmpty {
            base = URL(fileURLWithPath: tmp, isDirectory: true)
        } else {
            base = fileManager.temporaryDirectory
        }

        guard env["XCTestConfigurationFilePath"] != nil else {
            return base
        }
        return base.appendingPathComponent(
            "SumiDownloads-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
    }
}

enum DownloadFileUtilities {
    static let incompleteDownloadExtension = "sumiload"
    private static let log = Logger.sumi(category: "Downloads")

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
        ensureDirectoryExists(directory, fileManager: fileManager, context: "downloads destination")

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
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logFileOperationFailure(
                "list incomplete downloads",
                url: directory,
                error: error
            )
            return
        }

        for url in urls where url.pathExtension == incompleteDownloadExtension {
            do {
                let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                guard !isDirectory else { continue }
                try fileManager.removeItem(at: url)
            } catch {
                logFileOperationFailure(
                    "remove orphaned incomplete download",
                    url: url,
                    error: error
                )
            }
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

    static func ensureDirectoryExists(
        _ directory: URL,
        fileManager: FileManager = .default,
        context: String
    ) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logFileOperationFailure(context, url: directory, error: error)
        }
    }

    static func removeItemIfPresent(
        at url: URL,
        fileManager: FileManager = .default,
        context: String
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logFileOperationFailure(context, url: url, error: error)
        }
    }

    static func fileSize(for url: URL) -> Int64? {
        do {
            return try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        } catch {
            logFileOperationFailure("read downloaded file size", url: url, error: error)
            return nil
        }
    }

    static func contentType(for url: URL) -> UTType? {
        do {
            return try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        } catch {
            logFileOperationFailure("read downloaded file content type", url: url, error: error)
            return nil
        }
    }

    static func logFileOperationFailure(
        _ context: String,
        url: URL,
        error: Error
    ) {
        Self.log.error(
            "Download file operation failed (\(context, privacy: .public), item=\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
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
