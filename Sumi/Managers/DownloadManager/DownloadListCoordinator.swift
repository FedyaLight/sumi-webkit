import AppKit
import Foundation

struct DownloadRetryReceipt: Equatable {
    let id: UUID
    let itemID: UUID
}

@MainActor
protocol DownloadListCoordinatorEventSink: AnyObject {
    func downloadListCoordinatorDidChange(
        _ coordinator: DownloadListCoordinator
    )
    func downloadListCoordinator(
        _ coordinator: DownloadListCoordinator,
        didFinish item: DownloadItem
    )
}

@MainActor
final class DownloadListCoordinator: DownloadTransactionDelegate {
    private let transactionFactory: DownloadTransactionFactory
    private let promptPresenter: any DownloadPromptPresenting
    private var transactions: [UUID: DownloadTransaction] = [:]
    private var pendingRetryReceipts: [UUID: DownloadRetryReceipt] = [:]
    private weak var eventSink: (any DownloadListCoordinatorEventSink)?
    private var didAttachEventSink = false

    weak var settings: SumiSettingsService?
    private(set) var items: [DownloadItem] = []

    init(
        transactionFactory: DownloadTransactionFactory,
        promptPresenter: any DownloadPromptPresenting
    ) {
        self.transactionFactory = transactionFactory
        self.promptPresenter = promptPresenter
    }

    @discardableResult
    func attachEventSink(
        _ eventSink: any DownloadListCoordinatorEventSink
    ) -> Bool {
        guard !didAttachEventSink else { return false }
        didAttachEventSink = true
        self.eventSink = eventSink
        return true
    }

    var activeCount: Int {
        items.filter(\.isActive).count
    }

    var combinedProgressFraction: Double? {
        let active = items.filter(\.isActive)
        guard !active.isEmpty else { return nil }

        var knownCompleted: Int64 = 0
        var knownTotal: Int64 = 0
        var hasIndeterminate = false
        for item in active {
            if item.totalUnitCount > 0 {
                knownCompleted += max(item.completedUnitCount, 0)
                knownTotal += item.totalUnitCount
            } else {
                hasIndeterminate = true
            }
        }
        guard knownTotal > 0 else { return -1 }
        if hasIndeterminate, knownCompleted == 0 { return -1 }
        return min(max(Double(knownCompleted) / Double(knownTotal), 0), 1)
    }

    func start(
        transport: any DownloadTransport,
        originalURL: URL,
        suggestedFilename: String,
        openIntent: SumiDownloadOpenIntent?,
        promptRequest: SumiDownloadPromptRequest?,
        flyAnimationOrigin: DownloadFlyAnimationOrigin?
    ) -> DownloadItem {
        let item = DownloadItem(
            downloadURL: originalURL,
            fileName: initialFilename(suggestedFilename),
            openIntent: openIntent,
            promptRequest: promptRequest
        )
        insert(item)
        let transaction = transactionFactory.makeTransportTransaction(
            itemID: item.id,
            transport: transport,
            sourceURL: originalURL,
            suggestedFilename: suggestedFilename,
            promptRequest: promptRequest,
            flyAnimationOrigin: flyAnimationOrigin,
            delegate: self
        )
        transactions[item.id] = transaction
        transaction.start()
        return item
    }

    func save(
        data: Data,
        originalURL: URL,
        suggestedFilename: String
    ) -> DownloadItem {
        let item = DownloadItem(
            downloadURL: originalURL,
            fileName: initialFilename(suggestedFilename)
        )
        insert(item)
        let transaction = transactionFactory.makeDataTransaction(
            itemID: item.id,
            data: data,
            sourceURL: originalURL,
            suggestedFilename: suggestedFilename,
            delegate: self
        )
        transactions[item.id] = transaction
        transaction.start()
        return item
    }

    func cancel(_ item: DownloadItem) {
        transactions[item.id]?.cancel()
    }

    func makeRetryReceipt(for item: DownloadItem) -> DownloadRetryReceipt? {
        guard item.state == .failed else { return nil }
        let receipt = DownloadRetryReceipt(id: UUID(), itemID: item.id)
        pendingRetryReceipts[item.id] = receipt
        return receipt
    }

    func attachRetry(
        transport: any DownloadTransport,
        to item: DownloadItem,
        receipt: DownloadRetryReceipt
    ) -> Bool {
        guard receipt.itemID == item.id,
              pendingRetryReceipts[item.id] == receipt,
              item.state == .failed
        else {
            return false
        }
        pendingRetryReceipts[item.id] = nil

        let previous = transactions[item.id]
        let inheritedReservation = previous?.takeReservationForRetry()
        previous?.invalidate(
            preservingReservation: inheritedReservation != nil
        )
        prepareItemForRetry(item)

        let transaction = transactionFactory.makeTransportTransaction(
            itemID: item.id,
            transport: transport,
            sourceURL: item.downloadURL,
            suggestedFilename: item.fileName,
            promptRequest: nil,
            flyAnimationOrigin: nil,
            inheritedReservation: inheritedReservation,
            delegate: self
        )
        transactions[item.id] = transaction
        transaction.start()
        return true
    }

    func failRetry(
        _ receipt: DownloadRetryReceipt,
        item: DownloadItem,
        message: String
    ) {
        guard pendingRetryReceipts[item.id] == receipt else { return }
        pendingRetryReceipts[item.id] = nil
        item.error = .failed(
            message: message,
            resumeData: item.error?.resumeData,
            isRetryable: item.error?.resumeData != nil
        )
        notify()
    }

    func clearInactiveDownloads() {
        let inactiveIDs = Set(items.filter { !$0.isActive }.map(\.id))
        guard !inactiveIDs.isEmpty else { return }

        for itemID in inactiveIDs {
            pendingRetryReceipts[itemID] = nil
            transactions[itemID]?.discardTemporaryFile()
            transactions[itemID]?.invalidate()
            transactions[itemID] = nil
        }
        items.removeAll { inactiveIDs.contains($0.id) }
        notify()
    }

    func downloadTransactionDidBegin(
        _ transaction: DownloadTransaction,
        progress: DownloadProgress,
        snapshot: DownloadProgressSnapshot
    ) {
        guard let item = currentItem(for: transaction) else { return }
        item.progress = progress
        item.state = .downloading
        apply(snapshot, to: item)
        notify()
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        destinationPreferenceFor _: URL
    ) -> SumiDownloadDestinationPreference? {
        guard isCurrent(transaction) else { return nil }
        return settings?.downloadsDestinationPreference
            ?? SumiDownloadDestinationPreference(
                alwaysAskWhereToSave: false,
                customDirectoryURL: nil
            )
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        resolvePrompt request: SumiDownloadPromptRequest,
        response: URLResponse,
        suggestedFilename: String,
        sourceURL: URL,
        window: NSWindow?
    ) async -> DownloadPromptDecision? {
        guard isCurrent(transaction) else { return nil }
        let decision = await promptPresenter.resolve(
            request: request,
            response: response,
            suggestedFilename: suggestedFilename,
            sourceURL: sourceURL,
            window: window
        )
        guard isCurrent(transaction) else { return nil }
        return decision
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didResolvePrompt decision: DownloadPromptDecision
    ) {
        guard let item = currentItem(for: transaction) else { return }
        item.promptRequest = nil
        if case .downloadThenOpen(let intent) = decision.action {
            item.openIntent = intent
        }
        guard decision.shouldPersist,
              let contentType = decision.identity.contentType
        else { return }

        let handler: SumiContentHandlerKind
        switch decision.action {
        case .downloadThenOpen:
            handler = .useSystemDefault
        case .saveFile:
            handler = .saveFile
        default:
            return
        }
        settings?.downloadApplicationsStore.upsert(
            SumiContentHandlerRecord(
                contentType: contentType,
                displayName: decision.identity.displayName,
                handler: handler,
                applicationURL: nil
            )
        )
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didChoose reservation: DownloadDestinationReservation,
        response: URLResponse?
    ) {
        guard let item = currentItem(for: transaction) else { return }
        item.fileName = reservation.fileName
        item.destinationURL = reservation.destinationURL
        item.tempURL = reservation.tempURL
        item.state = .downloading
        if let response, response.expectedContentLength > 0,
           item.totalUnitCount <= 0 {
            item.totalUnitCount = response.expectedContentLength
        }
        notify()
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didUpdate snapshot: DownloadProgressSnapshot
    ) {
        guard let item = currentItem(for: transaction), item.isActive else {
            return
        }
        apply(snapshot, to: item)
        notify()
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didFinish file: DownloadFinalizedFile
    ) {
        guard let item = currentItem(for: transaction) else { return }
        item.destinationURL = file.url
        item.tempURL = nil
        item.fileName = file.url.lastPathComponent
        if let byteCount = file.byteCount {
            item.totalUnitCount = max(item.totalUnitCount, byteCount)
            item.completedUnitCount = max(item.completedUnitCount, byteCount)
        } else {
            item.completedUnitCount = max(
                item.completedUnitCount,
                item.totalUnitCount
            )
        }
        item.state = .completed
        item.error = nil
        item.progress = nil
        pendingRetryReceipts[item.id] = nil
        notify()
        eventSink?.downloadListCoordinator(self, didFinish: item)
    }

    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didFail error: DownloadError
    ) {
        guard let item = currentItem(for: transaction) else { return }
        item.state = error == .cancelled ? .cancelled : .failed
        item.error = error
        item.progress = nil
        pendingRetryReceipts[item.id] = nil
        notify()
    }

    private func currentItem(
        for transaction: DownloadTransaction
    ) -> DownloadItem? {
        guard isCurrent(transaction) else { return nil }
        return items.first { $0.id == transaction.itemID }
    }

    private func isCurrent(_ transaction: DownloadTransaction) -> Bool {
        transactions[transaction.itemID] === transaction
    }

    private func apply(
        _ snapshot: DownloadProgressSnapshot,
        to item: DownloadItem
    ) {
        item.completedUnitCount = snapshot.completedUnitCount
        item.totalUnitCount = snapshot.totalUnitCount
        item.throughput = snapshot.throughput
        item.estimatedTimeRemaining = snapshot.estimatedTimeRemaining
    }

    private func insert(_ item: DownloadItem) {
        items.insert(item, at: 0)
        items.sort { lhs, rhs in
            if lhs.added != rhs.added { return lhs.added > rhs.added }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func prepareItemForRetry(_ item: DownloadItem) {
        item.state = .pending
        item.error = nil
        item.progress = nil
        item.completedUnitCount = 0
        if item.totalUnitCount <= 0 {
            item.totalUnitCount = -1
        }
        item.throughput = nil
        item.estimatedTimeRemaining = nil
    }

    private func initialFilename(_ suggestedFilename: String) -> String {
        let trimmed = suggestedFilename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? "download" : trimmed
    }

    private func notify() {
        eventSink?.downloadListCoordinatorDidChange(self)
    }
}
