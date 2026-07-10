import AppKit
import Foundation
import OSLog

final class SumiFaviconPayloadIngestion: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconPayloadIngestion")

    private let payloadCommitter: SumiFaviconStoredPayloadCommitter
    private let preparedPipeline: SumiPreparedFaviconPipeline

    init(
        payloadCommitter: SumiFaviconStoredPayloadCommitter,
        preparedPipeline: SumiPreparedFaviconPipeline
    ) {
        self.payloadCommitter = payloadCommitter
        self.preparedPipeline = preparedPipeline
    }

    func storeExternalPayload(
        _ imageData: Data,
        faviconURL: URL?,
        documentURL: URL,
        partition: SumiFaviconPartition
    ) throws {
        let candidate = SumiFaviconCandidate(
            pageURL: documentURL,
            iconURL: faviconURL ?? documentURL,
            sourceKind: .browserFallback,
            relTokens: ["icon"],
            partition: partition
        )
        let validation = SumiFaviconPayloadValidator.validate(
            data: imageData,
            responseMimeType: nil,
            candidate: candidate
        )
        guard case .valid(let payload) = validation else { return }
        let lease = payloadCommitter.lease(for: partition)
        _ = try payloadCommitter.store(payload, for: candidate, lease: lease)
    }

    func ingestLocalExtensionIcon(
        fileURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext
    ) async -> NSImage? {
        guard ExtensionUtils.isExtensionOwnedURL(documentURL) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            Self.log.error(
                "Failed to load local extension favicon icon: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        let candidate = SumiFaviconCandidate(
            pageURL: documentURL,
            iconURL: fileURL.standardizedFileURL,
            sourceKind: .extensionManifest,
            relTokens: ["icon"],
            declaredType: Self.mimeType(forIconFileURL: fileURL),
            partition: partition
        )
        let validation = SumiFaviconPayloadValidator.validate(
            data: data,
            responseMimeType: nil,
            candidate: candidate
        )
        guard case .valid(let payload) = validation else { return nil }

        do {
            let lease = payloadCommitter.lease(for: partition)
            guard let selection = try payloadCommitter.store(
                payload,
                for: candidate,
                lease: lease
            ) else {
                return nil
            }
            return await preparedPipeline.preparedImage(
                for: selection,
                request: SumiPreparedFaviconRequest(
                    pageURL: documentURL,
                    partition: partition,
                    context: context,
                    backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
                )
            )
        } catch {
            Self.log.error(
                "Failed to store local extension favicon icon: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private static func mimeType(forIconFileURL fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "ico":
            return "image/x-icon"
        case "svg":
            return "image/svg+xml"
        default:
            return nil
        }
    }
}
