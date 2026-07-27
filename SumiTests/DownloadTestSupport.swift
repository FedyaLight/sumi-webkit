import AppKit
import Foundation

@testable import Sumi

@MainActor
final class TestDownloadTransport: DownloadTransport {
    let progress: Progress
    var promptWindow: NSWindow? { nil }
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private weak var delegate: (any DownloadTransportDelegate)?

    init(totalUnitCount: Int64 = 100) {
        progress = Progress(totalUnitCount: totalUnitCount)
    }

    func start(delegate: any DownloadTransportDelegate) {
        startCount += 1
        self.delegate = delegate
    }

    func cancel() {
        cancelCount += 1
    }

    func chooseDestination(
        filename: String = "download.bin",
        expectedContentLength: Int64 = 100
    ) async -> URL? {
        let response = URLResponse(
            url: URL(string: "https://example.com/\(filename)")!,
            mimeType: "application/octet-stream",
            expectedContentLength: Int(expectedContentLength),
            textEncodingName: nil
        )
        return await delegate?.downloadTransport(
            self,
            decideDestinationUsing: response,
            suggestedFilename: filename
        )
    }

    func finish() {
        delegate?.downloadTransportDidFinish(self)
    }

    func fail(
        _ error: Error = URLError(.networkConnectionLost),
        resumeData: Data? = nil
    ) {
        delegate?.downloadTransport(
            self,
            didFail: .failed(error: error, resumeData: resumeData)
        )
    }

    func finishCancellation() {
        delegate?.downloadTransport(self, didFail: .cancelled)
    }
}

@MainActor
final class TestDownloadDestinationAllocator: DownloadDestinationAllocating {
    let directory: URL
    var rejectsReservation = false
    private(set) var reserveCount = 0
    private(set) var renewCount = 0
    private(set) var released: [DownloadDestinationReservation] = []

    init(directory: URL = FileManager.default.temporaryDirectory) {
        self.directory = directory
    }

    func reserve(
        _ request: DownloadDestinationRequest
    ) async -> DownloadDestinationReservation? {
        reserveCount += 1
        guard !rejectsReservation else { return nil }
        let destination = directory.appendingPathComponent(request.suggestedFilename)
        return DownloadDestinationReservation(
            fileName: destination.lastPathComponent,
            destinationURL: destination,
            tempURL: destination.appendingPathExtension("sumiload")
        )
    }

    func renewTemporaryDestination(
        for reservation: DownloadDestinationReservation
    ) async -> DownloadDestinationReservation? {
        renewCount += 1
        return DownloadDestinationReservation(
            allocationID: UUID(),
            fileName: reservation.fileName,
            destinationURL: reservation.destinationURL,
            tempURL: reservation.tempURL.appendingPathExtension("retry-\(renewCount)")
        )
    }

    func release(_ reservation: DownloadDestinationReservation) {
        released.append(reservation)
    }
}

final class TestDownloadFinalizer: DownloadFileFinalizing, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(String)
    }

    private let lock = NSLock()
    private var storedOutcome: Outcome
    private var storedFinalizeCount = 0
    private var storedRemovedURLs: [URL] = []

    init(outcome: Outcome = .success) {
        storedOutcome = outcome
    }

    var outcome: Outcome {
        get { lock.withLock { storedOutcome } }
        set { lock.withLock { storedOutcome = newValue } }
    }

    var finalizeCount: Int {
        lock.withLock { storedFinalizeCount }
    }

    var removedURLs: [URL] {
        lock.withLock { storedRemovedURLs }
    }

    func finalize(
        data: Data,
        reservation: DownloadDestinationReservation,
        sourceURL _: URL?
    ) async throws -> DownloadFinalizedFile {
        try result(url: reservation.destinationURL, byteCount: Int64(data.count))
    }

    func finalize(
        temporaryURL _: URL,
        destinationURL: URL,
        sourceURL _: URL?
    ) async throws -> DownloadFinalizedFile {
        try result(url: destinationURL, byteCount: nil)
    }

    func removeTemporaryFile(at url: URL) async {
        lock.withLock { storedRemovedURLs.append(url) }
    }

    private func result(url: URL, byteCount: Int64?) throws -> DownloadFinalizedFile {
        let outcome = lock.withLock { () -> Outcome in
            storedFinalizeCount += 1
            return storedOutcome
        }
        switch outcome {
        case .success:
            return DownloadFinalizedFile(url: url, byteCount: byteCount)
        case .failure(let message):
            throw TestDownloadError(message: message)
        }
    }
}

final class TestDownloadAllocationFileManager: FileManager, @unchecked Sendable {
    private let accessLock = NSLock()
    private var mainThreadAccessCount = 0
    private var filesystemAccessCount = 0

    var accessedFromMainThread: Bool {
        accessLock.withLock { mainThreadAccessCount > 0 }
    }

    var recordedFilesystemAccessCount: Int {
        accessLock.withLock { filesystemAccessCount }
    }

    override func fileExists(atPath path: String) -> Bool {
        recordFilesystemAccess()
        return super.fileExists(atPath: path)
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        recordFilesystemAccess()
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    private func recordFilesystemAccess() {
        accessLock.withLock {
            filesystemAccessCount += 1
            if Thread.isMainThread {
                mainThreadAccessCount += 1
            }
        }
    }
}

private struct TestDownloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class TestDownloadProgressPublisher: DownloadProgressPublishing {
    private(set) var publications: [TestDownloadProgressPublication] = []

    func makePublication(
        source: DownloadProgressSource,
        sourceURL _: URL,
        onUpdate: @escaping @MainActor (DownloadProgressSnapshot) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onTemporaryFileRemoved: @escaping @MainActor () -> Void
    ) -> any DownloadProgressPublication {
        let total: Int64
        switch source {
        case .progress(let progress):
            total = progress.totalUnitCount
        case .totalUnitCount(let count):
            total = count
        }
        let publication = TestDownloadProgressPublication(
            totalUnitCount: total,
            onUpdate: onUpdate,
            onCancel: onCancel,
            onTemporaryFileRemoved: onTemporaryFileRemoved
        )
        publications.append(publication)
        return publication
    }
}

@MainActor
final class TestDownloadProgressPublication: DownloadProgressPublication {
    let progress: DownloadProgress
    private(set) var snapshot: DownloadProgressSnapshot
    private(set) var stopCount = 0
    private(set) var publishedTemporaryURL: URL?

    private let onUpdate: @MainActor (DownloadProgressSnapshot) -> Void
    private let onCancel: @MainActor () -> Void
    private let onTemporaryFileRemoved: @MainActor () -> Void

    init(
        totalUnitCount: Int64,
        onUpdate: @escaping @MainActor (DownloadProgressSnapshot) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onTemporaryFileRemoved: @escaping @MainActor () -> Void
    ) {
        progress = DownloadProgress(totalUnitCount: totalUnitCount)
        snapshot = DownloadProgressSnapshot(
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            throughput: nil,
            estimatedTimeRemaining: nil
        )
        self.onUpdate = onUpdate
        self.onCancel = onCancel
        self.onTemporaryFileRemoved = onTemporaryFileRemoved
    }

    func publishFile(
        at temporaryURL: URL,
        destinationURL _: URL,
        responseMIMEType _: String?,
        flyAnimationOriginalRect _: NSRect?
    ) {
        publishedTemporaryURL = temporaryURL
    }

    func markCompleted(byteCount: Int64?) {
        let total = byteCount ?? max(snapshot.totalUnitCount, 0)
        emit(completed: total, total: total)
    }

    func stop() {
        stopCount += 1
    }

    func emit(
        completed: Int64,
        total: Int64,
        throughput: Int? = nil,
        remaining: TimeInterval? = nil
    ) {
        progress.updateProgress(
            totalUnitCount: total,
            completedUnitCount: completed
        )
        snapshot = DownloadProgressSnapshot(
            completedUnitCount: completed,
            totalUnitCount: total,
            throughput: throughput,
            estimatedTimeRemaining: remaining
        )
        onUpdate(snapshot)
    }

    func requestCancellation() {
        onCancel()
    }

    func reportTemporaryFileRemoved() {
        onTemporaryFileRemoved()
    }
}

@MainActor
final class TestDownloadPromptPresenter: DownloadPromptPresenting {
    private(set) var callCount = 0

    func resolve(
        request: SumiDownloadPromptRequest,
        response _: URLResponse,
        suggestedFilename _: String,
        sourceURL _: URL,
        window _: NSWindow?
    ) async -> DownloadPromptDecision {
        callCount += 1
        return DownloadPromptDecision(
            action: .saveFile,
            shouldPersist: false,
            identity: request.identity
        )
    }
}

@MainActor
final class TestDownloadRetryTransport: DownloadRetryTransportStarting {
    let transport: TestDownloadTransport
    private(set) var requests: [DownloadRetryRequest] = []

    init(transport: TestDownloadTransport = TestDownloadTransport()) {
        self.transport = transport
    }

    func startRetry(
        _ request: DownloadRetryRequest,
        completion: @escaping @MainActor (any DownloadTransport) -> Void
    ) -> Bool {
        requests.append(request)
        completion(transport)
        return true
    }
}

@MainActor
final class TestDownloadWorkspace: DownloadWorkspaceOpening {
    private(set) var opened: [URL] = []
    private(set) var automaticallyOpened: [URL] = []
    private(set) var revealed: [URL] = []
    private(set) var folderOpenCount = 0

    func openDownloadedFile(at url: URL, sourceURL _: URL?) { opened.append(url) }
    func openDownloadedFileIfSafe(
        at url: URL,
        intent _: SumiDownloadOpenIntent
    ) {
        automaticallyOpened.append(url)
    }
    func revealDownloadedFile(at url: URL) { revealed.append(url) }
    func openDownloadsFolder(preference _: SumiDownloadDestinationPreference) {
        folderOpenCount += 1
    }
}

final class TestDownloadOrphanCleaner: DownloadOrphanCleaning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPreferences: [SumiDownloadDestinationPreference] = []

    var callCount: Int { lock.withLock { storedPreferences.count } }
    var preferences: [SumiDownloadDestinationPreference] {
        lock.withLock { storedPreferences }
    }

    func removeOrphanedDownloads(
        preference: SumiDownloadDestinationPreference
    ) async {
        lock.withLock { storedPreferences.append(preference) }
    }
}

@MainActor
final class TestDownloadListCoordinatorEventSink:
    DownloadListCoordinatorEventSink
{
    private(set) var changeCount = 0
    private(set) var finishedItems: [DownloadItem] = []

    func downloadListCoordinatorDidChange(
        _: DownloadListCoordinator
    ) {
        changeCount += 1
    }

    func downloadListCoordinator(
        _: DownloadListCoordinator,
        didFinish item: DownloadItem
    ) {
        finishedItems.append(item)
    }
}

@MainActor
struct DownloadTestHarness {
    let manager: DownloadManager
    let coordinator: DownloadListCoordinator
    let destinations: TestDownloadDestinationAllocator
    let finalizer: TestDownloadFinalizer
    let progress: TestDownloadProgressPublisher
    let workspace: TestDownloadWorkspace

    init(finalizer: TestDownloadFinalizer = TestDownloadFinalizer()) {
        let destinations = TestDownloadDestinationAllocator()
        let progress = TestDownloadProgressPublisher()
        let coordinator = DownloadListCoordinator(
            transactionFactory: DownloadTransactionFactory(
                destinations: destinations,
                finalizer: finalizer,
                progressPublisher: progress
            ),
            promptPresenter: TestDownloadPromptPresenter()
        )
        let workspace = TestDownloadWorkspace()
        self.manager = DownloadManager(
            coordinator: coordinator,
            workspace: workspace
        )
        self.coordinator = coordinator
        self.destinations = destinations
        self.finalizer = finalizer
        self.progress = progress
        self.workspace = workspace
    }
}
