import AppKit
import Foundation

@MainActor
final class DownloadTransactionFactory {
    private let destinations: any DownloadDestinationAllocating
    private let finalizer: any DownloadFileFinalizing
    private let progressPublisher: any DownloadProgressPublishing

    init(
        destinations: any DownloadDestinationAllocating,
        finalizer: any DownloadFileFinalizing,
        progressPublisher: any DownloadProgressPublishing
    ) {
        self.destinations = destinations
        self.finalizer = finalizer
        self.progressPublisher = progressPublisher
    }

    func makeTransportTransaction(
        itemID: UUID,
        transport: any DownloadTransport,
        sourceURL: URL,
        suggestedFilename: String,
        promptRequest: SumiDownloadPromptRequest?,
        flyAnimationOriginalRect: NSRect?,
        inheritedReservation: DownloadDestinationReservation? = nil,
        delegate: any DownloadTransactionDelegate
    ) -> DownloadTransaction {
        DownloadTransaction(
            itemID: itemID,
            source: .transport(transport),
            sourceURL: sourceURL,
            suggestedFilename: suggestedFilename,
            promptRequest: promptRequest,
            flyAnimationOriginalRect: flyAnimationOriginalRect,
            inheritedReservation: inheritedReservation,
            destinations: destinations,
            finalizer: finalizer,
            progressPublisher: progressPublisher,
            delegate: delegate
        )
    }

    func makeDataTransaction(
        itemID: UUID,
        data: Data,
        sourceURL: URL,
        suggestedFilename: String,
        delegate: any DownloadTransactionDelegate
    ) -> DownloadTransaction {
        DownloadTransaction(
            itemID: itemID,
            source: .data(data),
            sourceURL: sourceURL,
            suggestedFilename: suggestedFilename,
            promptRequest: nil,
            flyAnimationOriginalRect: nil,
            inheritedReservation: nil,
            destinations: destinations,
            finalizer: finalizer,
            progressPublisher: progressPublisher,
            delegate: delegate
        )
    }
}
