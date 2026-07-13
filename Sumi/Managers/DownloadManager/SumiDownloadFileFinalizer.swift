import Foundation

enum SumiDownloadFileFinalizationError: LocalizedError {
    case destinationOccupied

    var errorDescription: String? {
        "Another file appeared at the selected download destination."
    }
}

final class SumiDownloadFileFinalizer:
    DownloadFileFinalizing,
    @unchecked Sendable
{
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func finalize(
        data: Data,
        reservation: DownloadDestinationReservation,
        sourceURL: URL?
    ) async throws -> DownloadFinalizedFile {
        let fileManager = self.fileManager
        return try await Task.detached(priority: .utility) {
            do {
                try fileManager.createDirectory(
                    at: reservation.tempURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: reservation.tempURL, options: .atomic)
                return try Self.finalizeDownloadedFile(
                    temporaryURL: reservation.tempURL,
                    destinationURL: reservation.destinationURL,
                    sourceURL: sourceURL,
                    fileManager: fileManager
                )
            } catch {
                if !(error is SumiDownloadFileFinalizationError) {
                    DownloadFileUtilities.removeItemIfPresent(
                        at: reservation.tempURL,
                        fileManager: fileManager,
                        context: "remove failed data download temp file"
                    )
                }
                throw error
            }
        }.value
    }

    func finalize(
        temporaryURL: URL,
        destinationURL: URL,
        sourceURL: URL?
    ) async throws -> DownloadFinalizedFile {
        let fileManager = self.fileManager
        return try await Task.detached(priority: .utility) {
            try Self.finalizeDownloadedFile(
                temporaryURL: temporaryURL,
                destinationURL: destinationURL,
                sourceURL: sourceURL,
                fileManager: fileManager
            )
        }.value
    }

    func removeTemporaryFile(at url: URL) async {
        let fileManager = self.fileManager
        await Task.detached(priority: .utility) {
            DownloadFileUtilities.removeItemIfPresent(
                at: url,
                fileManager: fileManager,
                context: "remove download temporary file"
            )
        }.value
    }

    private static func finalizeDownloadedFile(
        temporaryURL: URL,
        destinationURL: URL,
        sourceURL: URL?,
        fileManager: FileManager
    ) throws -> DownloadFinalizedFile {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw SumiDownloadFileFinalizationError.destinationOccupied
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try SumiDownloadSafety.applyQuarantine(to: temporaryURL, sourceURL: sourceURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(
                    atPath: destinationURL.path
                )
            } catch {
                attributes = [:]
            }
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value
            return DownloadFinalizedFile(url: destinationURL, byteCount: byteCount)
        } catch {
            let cocoaError = error as? CocoaError
            if cocoaError?.code == .fileWriteFileExists {
                throw SumiDownloadFileFinalizationError.destinationOccupied
            }
            DownloadFileUtilities.removeItemIfPresent(
                at: temporaryURL,
                fileManager: fileManager,
                context: "remove failed finalized download temp file"
            )
            throw error
        }
    }
}
