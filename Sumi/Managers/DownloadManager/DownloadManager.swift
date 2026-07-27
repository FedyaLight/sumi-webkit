import AppKit
import Combine
import Foundation

@MainActor
final class DownloadManager: ObservableObject, DownloadListCoordinatorEventSink {
    @Published private(set) var items: [DownloadItem]
    @Published private(set) var activeDownloadCount: Int
    @Published private(set) var combinedProgressFraction: Double?

    private let coordinator: DownloadListCoordinator?
    private let workspace: (any DownloadWorkspaceOpening)?
    private var retryTransport: (any DownloadRetryTransportStarting)?
    let flyAnimationCenter: DownloadFlyAnimationCenter

    weak var settings: SumiSettingsService? {
        didSet { coordinator?.settings = settings }
    }

    init(
        coordinator: DownloadListCoordinator?,
        workspace: (any DownloadWorkspaceOpening)?,
        flyAnimationCenter: DownloadFlyAnimationCenter
    ) {
        self.coordinator = coordinator
        self.workspace = workspace
        self.flyAnimationCenter = flyAnimationCenter
        self.items = coordinator?.items ?? []
        self.activeDownloadCount = coordinator?.activeCount ?? 0
        self.combinedProgressFraction = coordinator?.combinedProgressFraction

        if let coordinator {
            precondition(
                coordinator.attachEventSink(self),
                "Download coordinator event sink must be attached exactly once"
            )
        }
    }

    static func unavailable() -> DownloadManager {
        DownloadManager(
            coordinator: nil,
            workspace: nil,
            flyAnimationCenter: DownloadFlyAnimationCenter()
        )
    }

    var isAvailable: Bool {
        coordinator != nil
    }

    var hasActiveDownloads: Bool {
        activeDownloadCount > 0
    }

    var hasInactiveDownloads: Bool {
        items.contains { !$0.isActive }
    }

    @discardableResult
    func attachRetryTransport(
        _ transport: any DownloadRetryTransportStarting
    ) -> Bool {
        guard retryTransport == nil else { return false }
        retryTransport = transport
        return true
    }

    @discardableResult
    func addDownload(
        transport: any DownloadTransport,
        originalURL: URL,
        suggestedFilename: String,
        openIntent: SumiDownloadOpenIntent? = nil,
        promptRequest: SumiDownloadPromptRequest? = nil,
        flyAnimationOrigin: DownloadFlyAnimationOrigin? = nil
    ) -> DownloadItem? {
        guard let coordinator else {
            transport.cancel()
            return nil
        }
        let item = coordinator.start(
            transport: transport,
            originalURL: originalURL,
            suggestedFilename: suggestedFilename,
            openIntent: openIntent,
            promptRequest: promptRequest,
            flyAnimationOrigin: flyAnimationOrigin
        )
        return item
    }

    func saveDownloadedData(
        _ data: Data,
        suggestedFilename: String,
        mimeType _: String?,
        originatingURL: URL
    ) {
        guard let coordinator else { return }
        _ = coordinator.save(
            data: data,
            originalURL: originatingURL,
            suggestedFilename: suggestedFilename
        )
    }

    func cancel(_ item: DownloadItem) {
        coordinator?.cancel(item)
    }

    func retry(_ item: DownloadItem) {
        guard item.canRetry || item.state == .failed,
              let coordinator,
              let receipt = coordinator.makeRetryReceipt(for: item)
        else { return }
        guard let retryTransport else {
            coordinator.failRetry(
                receipt,
                item: item,
                message: "Open a browser tab to retry this download."
            )
            return
        }

        let started = retryTransport.startRetry(
            DownloadRetryRequest(
                sourceURL: item.downloadURL,
                resumeData: item.error?.resumeData
            )
        ) { [weak self, weak item] transport in
            guard let self, let item,
                  self.coordinator?.attachRetry(
                    transport: transport,
                    to: item,
                    receipt: receipt
                  ) == true
            else {
                transport.cancel()
                return
            }
        }
        if !started {
            coordinator.failRetry(
                receipt,
                item: item,
                message: "Open a browser tab to retry this download."
            )
        }
    }

    func open(_ item: DownloadItem) {
        guard let url = item.localURL else { return }
        workspace?.openDownloadedFile(at: url, sourceURL: item.downloadURL)
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.destinationURL else { return }
        workspace?.revealDownloadedFile(at: url)
    }

    func openDownloadsFolder() {
        workspace?.openDownloadsFolder(
            preference: settings?.downloadsDestinationPreference
                ?? SumiDownloadDestinationPreference(
                    alwaysAskWhereToSave: false,
                    customDirectoryURL: nil
                )
        )
    }

    func clearInactiveDownloads() {
        coordinator?.clearInactiveDownloads()
    }

    private func openCompletedDownloadIfNeeded(_ item: DownloadItem) {
        guard let intent = item.openIntent, let url = item.localURL else { return }
        workspace?.openDownloadedFileIfSafe(
            at: url,
            intent: intent
        )
    }

    func downloadListCoordinatorDidChange(
        _ coordinator: DownloadListCoordinator
    ) {
        guard let ownedCoordinator = self.coordinator,
              ownedCoordinator === coordinator
        else { return }
        publishCoordinatorState()
    }

    func downloadListCoordinator(
        _ coordinator: DownloadListCoordinator,
        didFinish item: DownloadItem
    ) {
        guard let ownedCoordinator = self.coordinator,
              ownedCoordinator === coordinator
        else { return }
        openCompletedDownloadIfNeeded(item)
    }

    private func publishCoordinatorState() {
        guard let coordinator else { return }
        items = coordinator.items
        activeDownloadCount = coordinator.activeCount
        combinedProgressFraction = coordinator.combinedProgressFraction
    }
}
