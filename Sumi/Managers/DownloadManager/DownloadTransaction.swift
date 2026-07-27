import AppKit
import Foundation

@MainActor
protocol DownloadTransactionDelegate: AnyObject {
    func downloadTransactionDidBegin(
        _ transaction: DownloadTransaction,
        progress: DownloadProgress,
        snapshot: DownloadProgressSnapshot
    )
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        destinationPreferenceFor sourceURL: URL
    ) -> SumiDownloadDestinationPreference?
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        resolvePrompt request: SumiDownloadPromptRequest,
        response: URLResponse,
        suggestedFilename: String,
        sourceURL: URL,
        window: NSWindow?
    ) async -> DownloadPromptDecision?
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didResolvePrompt decision: DownloadPromptDecision
    )
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didChoose reservation: DownloadDestinationReservation,
        response: URLResponse?
    )
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didUpdate snapshot: DownloadProgressSnapshot
    )
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didFinish file: DownloadFinalizedFile
    )
    func downloadTransaction(
        _ transaction: DownloadTransaction,
        didFail error: DownloadError
    )
}

@MainActor
final class DownloadTransaction: DownloadTransportDelegate {
    enum Source {
        case transport(any DownloadTransport)
        case data(Data)
    }

    private enum Phase {
        case created
        case running
        case awaitingDestination
        case downloading
        case cancelling
        case finalizing
        case terminal
        case invalidated
    }

    let itemID: UUID

    private let source: Source
    private let sourceURL: URL
    private let suggestedFilename: String
    private var promptRequest: SumiDownloadPromptRequest?
    private let flyAnimationOrigin: DownloadFlyAnimationOrigin?
    private let destinations: any DownloadDestinationAllocating
    private let finalizer: any DownloadFileFinalizing
    private let progressPublisher: any DownloadProgressPublishing
    private weak var delegate: (any DownloadTransactionDelegate)?

    private var phase: Phase = .created
    private var reservation: DownloadDestinationReservation?
    private var inheritedReservation: DownloadDestinationReservation?
    private var publication: (any DownloadProgressPublication)?
    private var operationTask: Task<Void, Never>?
    private var retryableFailure = false

    init(
        itemID: UUID,
        source: Source,
        sourceURL: URL,
        suggestedFilename: String,
        promptRequest: SumiDownloadPromptRequest?,
        flyAnimationOrigin: DownloadFlyAnimationOrigin?,
        inheritedReservation: DownloadDestinationReservation?,
        destinations: any DownloadDestinationAllocating,
        finalizer: any DownloadFileFinalizing,
        progressPublisher: any DownloadProgressPublishing,
        delegate: any DownloadTransactionDelegate
    ) {
        self.itemID = itemID
        self.source = source
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        self.promptRequest = promptRequest
        self.flyAnimationOrigin = flyAnimationOrigin
        self.inheritedReservation = inheritedReservation
        self.destinations = destinations
        self.finalizer = finalizer
        self.progressPublisher = progressPublisher
        self.delegate = delegate
    }

    func start() {
        guard phase == .created else { return }
        phase = .running
        let progressSource: DownloadProgressSource
        switch source {
        case .transport(let transport):
            progressSource = .progress(transport.progress)
        case .data(let data):
            progressSource = .totalUnitCount(max(Int64(data.count), 1))
        }
        let publication = progressPublisher.makePublication(
            source: progressSource,
            sourceURL: sourceURL,
            onUpdate: { [weak self] snapshot in
                guard let self else { return }
                self.delegate?.downloadTransaction(self, didUpdate: snapshot)
            },
            onCancel: { [weak self] in self?.cancel() },
            onTemporaryFileRemoved: { [weak self] in
                self?.temporaryFileWasRemoved()
            }
        )
        self.publication = publication
        delegate?.downloadTransactionDidBegin(
            self,
            progress: publication.progress,
            snapshot: publication.snapshot
        )

        switch source {
        case .transport(let transport):
            transport.start(delegate: self)
        case .data(let data):
            operationTask = Task { [weak self] in
                await self?.runDataTransaction(data)
            }
        }
    }

    func cancel() {
        switch phase {
        case .running, .awaitingDestination, .downloading:
            phase = .cancelling
            switch source {
            case .transport(let transport):
                transport.cancel()
            case .data:
                operationTask?.cancel()
                settleFailure(.cancelled, preserveReservation: false)
            }
        case .created:
            settleFailure(.cancelled, preserveReservation: false)
        case .cancelling, .finalizing, .terminal, .invalidated:
            break
        }
    }

    func invalidate(preservingReservation: Bool = false) {
        guard phase != .invalidated else { return }
        if phase != .terminal, phase != .finalizing,
           case .transport(let transport) = source {
            transport.cancel()
        }
        phase = .invalidated
        operationTask?.cancel()
        operationTask = nil
        publication?.stop()
        publication = nil
        if !preservingReservation {
            releaseReservation()
        }
    }

    func takeReservationForRetry() -> DownloadDestinationReservation? {
        guard phase == .terminal, retryableFailure else { return nil }
        let transferred = reservation ?? inheritedReservation
        reservation = nil
        inheritedReservation = nil
        return transferred
    }

    func discardTemporaryFile() {
        let temporaryURL = reservation?.tempURL ?? inheritedReservation?.tempURL
        releaseReservation()
        if let temporaryURL {
            Task { [finalizer] in
                await finalizer.removeTemporaryFile(at: temporaryURL)
            }
        }
    }

    func downloadTransport(
        _ transport: any DownloadTransport,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard phase == .running else { return nil }
        phase = .awaitingDestination

        if let promptRequest {
            guard let decision = await delegate?.downloadTransaction(
                self,
                resolvePrompt: promptRequest,
                response: response,
                suggestedFilename: suggestedFilename,
                sourceURL: sourceURL,
                window: transport.promptWindow
            ), phase == .awaitingDestination else {
                return nil
            }
            self.promptRequest = nil
            delegate?.downloadTransaction(self, didResolvePrompt: decision)
            if decision.action == .cancel {
                settleFailure(.cancelled, preserveReservation: false)
                return nil
            }
        }

        guard let preference = delegate?.downloadTransaction(
            self,
            destinationPreferenceFor: sourceURL
        ) else {
            settleFailure(.cancelled, preserveReservation: false)
            return nil
        }
        let nextReservation: DownloadDestinationReservation?
        let abandonedTemporaryURL: URL?
        if let inheritedReservation {
            nextReservation = await destinations.renewTemporaryDestination(
                for: inheritedReservation
            )
            abandonedTemporaryURL = inheritedReservation.tempURL
            if nextReservation != nil {
                self.inheritedReservation = nil
            }
        } else {
            abandonedTemporaryURL = nil
            nextReservation = await destinations.reserve(
                DownloadDestinationRequest(
                    suggestedFilename: suggestedFilename,
                    response: response,
                    sourceURL: sourceURL,
                    preference: preference
                )
            )
        }
        guard phase == .awaitingDestination else {
            if let nextReservation {
                destinations.release(nextReservation)
                if let abandonedTemporaryURL {
                    await finalizer.removeTemporaryFile(
                        at: abandonedTemporaryURL
                    )
                }
            }
            return nil
        }
        guard let nextReservation else {
            settleFailure(.cancelled, preserveReservation: false)
            return nil
        }
        if let abandonedTemporaryURL,
           abandonedTemporaryURL != nextReservation.tempURL {
            await finalizer.removeTemporaryFile(at: abandonedTemporaryURL)
            guard phase == .awaitingDestination else {
                destinations.release(nextReservation)
                return nil
            }
        }

        reservation = nextReservation
        phase = .downloading
        delegate?.downloadTransaction(
            self,
            didChoose: nextReservation,
            response: response
        )
        publication?.publishFile(
            at: nextReservation.tempURL,
            destinationURL: nextReservation.destinationURL,
            responseMIMEType: response.mimeType,
            flyAnimationOrigin: flyAnimationOrigin
        )
        return nextReservation.tempURL
    }

    func downloadTransportDidFinish(_ transport: any DownloadTransport) {
        guard phase == .downloading, let reservation else {
            if phase == .running {
                settleFailure(
                    .moveFailed(message: "Download finished without a destination."),
                    preserveReservation: false
                )
            }
            return
        }
        phase = .finalizing
        let knownBytes = max(
            transport.progress.completedUnitCount,
            publication?.progress.completedUnitCount ?? 0
        )
        publication?.markCompleted(byteCount: knownBytes)
        operationTask = Task { [weak self, finalizer] in
            do {
                let file = try await finalizer.finalize(
                    temporaryURL: reservation.tempURL,
                    destinationURL: reservation.destinationURL,
                    sourceURL: self?.sourceURL
                )
                self?.finishFinalization(.success(file))
            } catch {
                self?.finishFinalization(.failure(error))
            }
        }
    }

    func downloadTransport(
        _: any DownloadTransport,
        didFail failure: DownloadTransportFailure
    ) {
        switch failure {
        case .cancelled:
            settleFailure(.cancelled, preserveReservation: false)
        case .failed(let error, let resumeData):
            let retryable = resumeData != nil
            settleFailure(
                .failed(
                    message: error.localizedDescription,
                    resumeData: resumeData,
                    isRetryable: retryable
                ),
                preserveReservation: retryable
            )
        }
    }

    private var transport: (any DownloadTransport)? {
        guard case .transport(let transport) = source else { return nil }
        return transport
    }

    private func runDataTransaction(_ data: Data) async {
        guard phase == .running,
              let preference = delegate?.downloadTransaction(
                self,
                destinationPreferenceFor: sourceURL
              )
        else { return }
        phase = .awaitingDestination
        let reservation = await destinations.reserve(
            DownloadDestinationRequest(
                suggestedFilename: suggestedFilename,
                response: nil,
                sourceURL: sourceURL,
                preference: preference
            )
        )
        guard phase == .awaitingDestination else {
            if let reservation { destinations.release(reservation) }
            return
        }
        guard let reservation else {
            settleFailure(.cancelled, preserveReservation: false)
            return
        }
        self.reservation = reservation
        phase = .finalizing
        delegate?.downloadTransaction(self, didChoose: reservation, response: nil)
        publication?.publishFile(
            at: reservation.tempURL,
            destinationURL: reservation.destinationURL,
            responseMIMEType: nil,
            flyAnimationOrigin: nil
        )
        publication?.markCompleted(byteCount: Int64(data.count))
        do {
            let file = try await finalizer.finalize(
                data: data,
                reservation: reservation,
                sourceURL: sourceURL
            )
            finishFinalization(.success(file))
        } catch {
            finishFinalization(.failure(error))
        }
    }

    private func finishFinalization(
        _ result: Result<DownloadFinalizedFile, Error>
    ) {
        guard phase == .finalizing else { return }
        operationTask = nil
        publication?.stop()
        publication = nil

        switch result {
        case .success(let file):
            phase = .terminal
            releaseReservation()
            delegate?.downloadTransaction(self, didFinish: file)
        case .failure(let error):
            phase = .terminal
            let temporaryURL = reservation?.tempURL
            releaseReservation()
            if let temporaryURL {
                Task { [finalizer] in
                    await finalizer.removeTemporaryFile(at: temporaryURL)
                }
            }
            delegate?.downloadTransaction(
                self,
                didFail: .moveFailed(message: error.localizedDescription)
            )
        }
    }

    private func settleFailure(
        _ error: DownloadError,
        preserveReservation: Bool
    ) {
        guard phase != .terminal,
              phase != .invalidated,
              phase != .finalizing
        else { return }
        phase = .terminal
        operationTask?.cancel()
        operationTask = nil
        publication?.stop()
        publication = nil
        retryableFailure = preserveReservation

        if !preserveReservation {
            let temporaryURL = reservation?.tempURL ?? inheritedReservation?.tempURL
            releaseReservation()
            if let temporaryURL {
                Task { [finalizer] in
                    await finalizer.removeTemporaryFile(at: temporaryURL)
                }
            }
        }
        delegate?.downloadTransaction(self, didFail: error)
    }

    private func temporaryFileWasRemoved() {
        guard phase == .downloading else { return }
        transport?.cancel()
        settleFailure(
            .failed(
                message: "The temporary download file was removed.",
                resumeData: nil,
                isRetryable: false
            ),
            preserveReservation: false
        )
    }

    private func releaseReservation() {
        if let reservation {
            destinations.release(reservation)
            self.reservation = nil
        }
        if let inheritedReservation {
            destinations.release(inheritedReservation)
            self.inheritedReservation = nil
        }
    }
}
