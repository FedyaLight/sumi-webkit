import Foundation

enum SumiDownloadCompletionService {
    static func finalizeDownloadedFile(
        temporaryURL: URL,
        destinationURL: URL,
        sourceURL: URL?
    ) throws -> URL {
        let finalURL = DownloadFileUtilities.uniqueURL(for: destinationURL)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try SumiDownloadSafety.applyQuarantine(to: temporaryURL, sourceURL: sourceURL)
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
