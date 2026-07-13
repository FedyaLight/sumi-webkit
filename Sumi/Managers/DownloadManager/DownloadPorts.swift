import AppKit
import Foundation

struct DownloadDestinationReservation: Equatable, Sendable {
    let allocationID: UUID
    let fileName: String
    let destinationURL: URL
    let tempURL: URL

    init(
        allocationID: UUID = UUID(),
        fileName: String,
        destinationURL: URL,
        tempURL: URL
    ) {
        self.allocationID = allocationID
        self.fileName = fileName
        self.destinationURL = destinationURL
        self.tempURL = tempURL
    }
}

struct DownloadDestinationRequest {
    let suggestedFilename: String
    let response: URLResponse?
    let sourceURL: URL
    let preference: SumiDownloadDestinationPreference
}

@MainActor
protocol DownloadDestinationAllocating: AnyObject {
    func reserve(_ request: DownloadDestinationRequest) async -> DownloadDestinationReservation?
    func renewTemporaryDestination(
        for reservation: DownloadDestinationReservation
    ) async -> DownloadDestinationReservation?
    func release(_ reservation: DownloadDestinationReservation)
}

struct DownloadFinalizedFile: Equatable {
    let url: URL
    let byteCount: Int64?
}

protocol DownloadFileFinalizing: Sendable {
    func finalize(
        data: Data,
        reservation: DownloadDestinationReservation,
        sourceURL: URL?
    ) async throws -> DownloadFinalizedFile

    func finalize(
        temporaryURL: URL,
        destinationURL: URL,
        sourceURL: URL?
    ) async throws -> DownloadFinalizedFile

    func removeTemporaryFile(at url: URL) async
}

struct DownloadProgressSnapshot: Equatable {
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let throughput: Int?
    let estimatedTimeRemaining: TimeInterval?
}

enum DownloadProgressSource {
    case progress(Progress)
    case totalUnitCount(Int64)
}

@MainActor
protocol DownloadProgressPublication: AnyObject {
    var progress: DownloadProgress { get }
    var snapshot: DownloadProgressSnapshot { get }

    func publishFile(
        at temporaryURL: URL,
        destinationURL: URL,
        responseMIMEType: String?,
        flyAnimationOriginalRect: NSRect?
    )
    func markCompleted(byteCount: Int64?)
    func stop()
}

@MainActor
protocol DownloadProgressPublishing: AnyObject {
    func makePublication(
        source: DownloadProgressSource,
        sourceURL: URL,
        onUpdate: @escaping @MainActor (DownloadProgressSnapshot) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onTemporaryFileRemoved: @escaping @MainActor () -> Void
    ) -> any DownloadProgressPublication
}

enum DownloadTransportFailure {
    case cancelled
    case failed(error: Error, resumeData: Data?)
}

@MainActor
protocol DownloadTransportDelegate: AnyObject {
    func downloadTransport(
        _ transport: any DownloadTransport,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL?
    func downloadTransportDidFinish(_ transport: any DownloadTransport)
    func downloadTransport(
        _ transport: any DownloadTransport,
        didFail failure: DownloadTransportFailure
    )
}

@MainActor
protocol DownloadTransport: AnyObject {
    var progress: Progress { get }
    var promptWindow: NSWindow? { get }

    func start(delegate: any DownloadTransportDelegate)
    func cancel()
}

struct DownloadRetryRequest {
    let sourceURL: URL
    let resumeData: Data?
}

@MainActor
protocol DownloadRetryTransportStarting: AnyObject {
    @discardableResult
    func startRetry(
        _ request: DownloadRetryRequest,
        completion: @escaping @MainActor (any DownloadTransport) -> Void
    ) -> Bool
}

struct DownloadPromptDecision: Equatable {
    let action: SumiDownloadResolvedAction
    let shouldPersist: Bool
    let identity: SumiDownloadContentIdentity
}

@MainActor
protocol DownloadPromptPresenting: AnyObject {
    func resolve(
        request: SumiDownloadPromptRequest,
        response: URLResponse,
        suggestedFilename: String,
        sourceURL: URL,
        window: NSWindow?
    ) async -> DownloadPromptDecision
}

@MainActor
protocol DownloadWorkspaceOpening: AnyObject {
    func openDownloadedFile(at url: URL, sourceURL: URL?)
    func openDownloadedFileIfSafe(
        at url: URL,
        intent: SumiDownloadOpenIntent
    )
    func revealDownloadedFile(at url: URL)
    func openDownloadsFolder(preference: SumiDownloadDestinationPreference)
}

protocol DownloadOrphanCleaning: Sendable {
    func removeOrphanedDownloads(
        preference: SumiDownloadDestinationPreference
    ) async
}
