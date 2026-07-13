import Foundation
import OSLog

final class SumiProtectionBundleCacheTransaction {
    enum Phase: String, Equatable, Sendable {
        case staging
        case validatingCandidate
        case validatingPrevious
        case publishing
        case validatingPublished
        case rollingBack
        case revalidatingRestored
        case quarantining
        case cleaningUp
        case active
        case previousActive
        case restoredActive
        case unavailable
        case failed
    }

    enum FaultStage: String, CaseIterable, Equatable, Sendable {
        case candidateDurability
        case candidateValidation
        case previousValidation
        case publicationSwap
        case publicationDurability
        case publishedValidation
        case rollbackSwap
        case rollbackDurability
        case restoredRevalidation
        case unavailablePublication
        case unavailableDurability
        case quarantinePublication
        case quarantineDurability
        case cleanup
        case cleanupDurability
    }

    typealias FaultInjector = (_ stage: FaultStage, _ url: URL) throws -> Void

    private enum PreviousValidation {
        case missing
        case valid(SumiProtectionBundleValidationReceipt)
        case invalid(any Error)

        var errorOrMissing: any Error {
            switch self {
            case .invalid(let error):
                return error
            case .missing:
                return SumiProtectionBundleRemoteUpdateError
                    .cacheCommitFailed("no previous generation exists")
            case .valid:
                return SumiProtectionBundleRemoteUpdateError
                    .cacheCommitFailed(
                        "validated previous generation was not restored"
                    )
            }
        }
    }

    private static let log = Logger.sumi(category: "ProtectionBundleCache")
    private let profileId: String
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let payloadValidator: any SumiProtectionBundlePayloadValidating
    private let faultInjector: FaultInjector?
    private let transactionId: UUID
    private let quarantineIO: SumiProtectionBundleQuarantine
    private let stagingRoot: URL
    let stagedBundleURL: URL
    private(set) var phase: Phase = .staging
    private var removeStagingOnDeinit = true

    init(
        profileId: String,
        rootDirectory: URL = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        fileManager: FileManager = .default,
        payloadValidator: any SumiProtectionBundlePayloadValidating = SumiProtectionNativeBundlePayloadValidator(),
        transactionId: UUID = UUID(),
        faultInjector: FaultInjector? = nil
    ) throws {
        guard Self.isSafePathComponent(profileId) else {
            throw SumiProtectionBundleRemoteUpdateError
                .invalidRelativePath(profileId)
        }
        self.profileId = profileId
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.payloadValidator = payloadValidator
        self.transactionId = transactionId
        self.faultInjector = faultInjector
        quarantineIO = SumiProtectionBundleQuarantine(
            profileId: profileId,
            rootDirectory: rootDirectory,
            fileManager: fileManager,
            transactionId: transactionId,
            faultInjector: faultInjector
        )
        stagingRoot = rootDirectory
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(transactionId.uuidString.lowercased(), isDirectory: true)
        stagedBundleURL = stagingRoot.appendingPathComponent(
            SumiAdblockNativeRuleBundle.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagedBundleURL,
            withIntermediateDirectories: true
        )
    }

    deinit {
        guard removeStagingOnDeinit,
              fileManager.fileExists(atPath: stagingRoot.path)
        else { return }
        do {
            try fileManager.removeItem(at: stagingRoot)
        } catch {
            Self.log.error(
                "Failed to remove abandoned protection bundle staging transaction \(self.transactionId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func write(_ data: Data, relativePath: String) throws {
        guard phase == .staging else {
            throw invalidPhaseError()
        }
        let destination = try safeDestinationURL(relativePath: relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func writeMetadata(_ metadata: SumiAdblockPreparedBundleRemoteMetadata) throws {
        guard phase == .staging else {
            throw invalidPhaseError()
        }
        try JSONEncoder().encode(metadata).write(
            to: stagedBundleURL.appendingPathComponent(
                SumiRemoteAdblockBundleCache.metadataFileName
            ),
            options: .atomic
        )
    }

    func commit(expectedIdentity: SumiProtectionBundleIdentity) throws -> URL {
        guard phase == .staging else { throw invalidPhaseError() }
        guard expectedIdentity.profileId == profileId else {
            throw SumiProtectionBundleRemoteUpdateError.bundleMetadataMismatch(
                "cache transaction profile \(profileId) does not match \(expectedIdentity.profileId)"
            )
        }

        let destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        let profileRoot = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: profileRoot,
            withIntermediateDirectories: true
        )
        let hadPreviousBundle = fileManager.fileExists(atPath: destination.path)

        let candidateReceipt: SumiProtectionBundleValidationReceipt
        do {
            phase = .validatingCandidate
            try faultInjector?(.candidateDurability, stagedBundleURL)
            try quarantineIO.synchronizeBundleTree(at: stagedBundleURL)
            try faultInjector?(.candidateValidation, stagedBundleURL)
            candidateReceipt = try payloadValidator.validateBundle(
                at: stagedBundleURL
            )
            guard candidateReceipt.identity == expectedIdentity else {
                throw SumiProtectionBundleRemoteUpdateError
                    .bundleMetadataMismatch(
                        "expected \(expectedIdentity.bundleId)/\(expectedIdentity.generationId), got \(candidateReceipt.identity.bundleId)/\(candidateReceipt.identity.generationId)"
                    )
            }
        } catch {
            let previous = validatePreviousIfPresent(
                at: destination,
                isPresent: hadPreviousBundle
            )
            throw failBeforePublication(
                candidateError: error,
                previous: previous,
                destination: destination
            )
        }

        let previous = validatePreviousIfPresent(
            at: destination,
            isPresent: hadPreviousBundle
        )
        phase = .publishing
        var didPublish = false
        do {
            try faultInjector?(.publicationSwap, destination)
            if hadPreviousBundle {
                try ContentBlockingItemExchange.swap(
                    destination,
                    stagedBundleURL
                )
            } else {
                try fileManager.moveItem(
                    at: stagedBundleURL,
                    to: destination
                )
            }
            didPublish = true
            try faultInjector?(.publicationDurability, profileRoot)
            try quarantineIO.synchronizeDirectory(at: profileRoot)

            phase = .validatingPublished
            try faultInjector?(.publishedValidation, destination)
            let publishedReceipt = try payloadValidator.validateBundle(
                at: destination
            )
            guard publishedReceipt == candidateReceipt else {
                throw SumiProtectionBundleRemoteUpdateError
                    .bundleMetadataMismatch(
                        "published bundle bytes or identity differ from the validated candidate"
                    )
            }
        } catch {
            if didPublish {
                throw rollbackAfterPublicationFailure(
                    error,
                    previous: previous,
                    destination: destination,
                    hadPreviousBundle: hadPreviousBundle
                )
            }
            if case .valid = previous {
                do {
                    try cleanupPublishedTransaction(clearUnavailable: true)
                } catch let cleanupError {
                    phase = .failed
                    removeStagingOnDeinit = false
                    throw SumiProtectionBundleRemoteUpdateError
                        .cacheQuarantineFailed(
                            cleanupError.localizedDescription
                        )
                }
                phase = .previousActive
                throw SumiProtectionBundleRemoteUpdateError.cacheCommitFailed(
                    "bundle publication swap failed; the validated previous bundle remains active"
                )
            }
            throw makeUnavailable(
                currentError: error,
                previousError: previous.errorOrMissing,
                artifacts: [
                    ("candidate", stagedBundleURL),
                    ("previous", destination),
                ]
            )
        }

        if case .invalid(let error) = previous {
            do {
                try quarantine(
                    artifacts: [("previous", stagedBundleURL)],
                    currentError: "validated candidate",
                    previousError: diagnostic(error)
                )
            } catch {
                phase = .failed
                removeStagingOnDeinit = false
                throw SumiProtectionBundleRemoteUpdateError
                    .cacheQuarantineFailed(error.localizedDescription)
            }
        }
        do {
            try cleanupPublishedTransaction(clearUnavailable: true)
        } catch {
            phase = .failed
            removeStagingOnDeinit = false
            throw SumiProtectionBundleRemoteUpdateError
                .cacheQuarantineFailed(error.localizedDescription)
        }
        phase = .active
        return destination
    }

    private func validatePreviousIfPresent(
        at destination: URL,
        isPresent: Bool
    ) -> PreviousValidation {
        guard isPresent else { return .missing }
        phase = .validatingPrevious
        do {
            try faultInjector?(.previousValidation, destination)
            return .valid(try payloadValidator.validateBundle(at: destination))
        } catch {
            removeStagingOnDeinit = false
            return .invalid(error)
        }
    }

    private func failBeforePublication(
        candidateError: any Error,
        previous: PreviousValidation,
        destination: URL
    ) -> any Error {
        switch previous {
        case .valid:
            do {
                try quarantine(
                    artifacts: [("candidate", stagedBundleURL)],
                    currentError: diagnostic(candidateError),
                    previousError: "validated previous"
                )
                try cleanupPublishedTransaction(clearUnavailable: true)
                phase = .previousActive
                return candidateError
            } catch {
                phase = .failed
                removeStagingOnDeinit = false
                return SumiProtectionBundleRemoteUpdateError
                    .cacheQuarantineFailed(error.localizedDescription)
            }
        case .invalid(let previousError):
            return makeUnavailable(
                currentError: candidateError,
                previousError: previousError,
                artifacts: [
                    ("candidate", stagedBundleURL),
                    ("previous", destination),
                ]
            )
        case .missing:
            return makeUnavailable(
                currentError: candidateError,
                previousError: SumiProtectionBundleRemoteUpdateError
                    .cacheCommitFailed("no previous generation exists"),
                artifacts: [("candidate", stagedBundleURL)]
            )
        }
    }

    /// Atomic swap-back is only the rollback publication step. The restored
    /// bytes stay unusable until the exact pre-swap receipt is revalidated.
    private func rollbackAfterPublicationFailure(
        _ publicationError: any Error,
        previous: PreviousValidation,
        destination: URL,
        hadPreviousBundle: Bool
    ) -> any Error {
        guard hadPreviousBundle else {
            return makeUnavailable(
                currentError: publicationError,
                previousError: SumiProtectionBundleRemoteUpdateError
                    .cacheCommitFailed("no previous generation exists"),
                artifacts: [("candidate", destination)]
            )
        }

        phase = .rollingBack
        do {
            // Block new cache discovery before swap-back. The marker remains
            // until the restored exact receipt is validated and cleanup is
            // durable, so no concurrent loader can reuse it in the gap.
            try quarantineIO.publishUnavailableMarker(
                currentFailure: diagnostic(publicationError),
                previousFailure: "rollback validation pending"
            )
        } catch {
            return makeUnavailable(
                currentError: publicationError,
                previousError: error,
                artifacts: [
                    ("candidate", destination),
                    ("previous", stagedBundleURL),
                ]
            )
        }
        do {
            try faultInjector?(.rollbackSwap, destination)
            try ContentBlockingItemExchange.swap(destination, stagedBundleURL)
        } catch {
            return makeUnavailable(
                currentError: publicationError,
                previousError: SumiProtectionBundleRemoteUpdateError
                    .cacheRollbackFailed(
                        commit: publicationError.localizedDescription,
                        rollback: error.localizedDescription
                    ),
                artifacts: [
                    ("candidate", destination),
                    ("previous", stagedBundleURL),
                ]
            )
        }

        var rollbackDurabilityError: (any Error)?
        do {
            try faultInjector?(
                .rollbackDurability,
                destination.deletingLastPathComponent()
            )
            try quarantineIO.synchronizeDirectory(
                at: destination.deletingLastPathComponent()
            )
        } catch {
            rollbackDurabilityError = error
        }

        phase = .revalidatingRestored
        let restoredResult: Result<
            SumiProtectionBundleValidationReceipt,
            any Error
        >
        do {
            try faultInjector?(.restoredRevalidation, destination)
            restoredResult = .success(
                try payloadValidator.validateBundle(at: destination)
            )
        } catch {
            restoredResult = .failure(error)
        }

        guard rollbackDurabilityError == nil,
              case .valid(let previousReceipt) = previous,
              case .success(let restoredReceipt) = restoredResult,
              restoredReceipt == previousReceipt
        else {
            let restoredError = rollbackDurabilityError
                ?? restoredResult.failure
                ?? previous.errorOrMissing
            return makeUnavailable(
                currentError: publicationError,
                previousError: restoredError,
                artifacts: [
                    ("previous", destination),
                    ("candidate", stagedBundleURL),
                ]
            )
        }

        do {
            try quarantine(
                artifacts: [("candidate", stagedBundleURL)],
                currentError: diagnostic(publicationError),
                previousError: "restored receipt revalidated"
            )
            try cleanupPublishedTransaction(clearUnavailable: true)
        } catch {
            phase = .failed
            removeStagingOnDeinit = false
            return SumiProtectionBundleRemoteUpdateError
                .cacheQuarantineFailed(error.localizedDescription)
        }
        phase = .restoredActive
        return publicationError
    }

    private func makeUnavailable(
        currentError: any Error,
        previousError: any Error,
        artifacts: [(role: String, url: URL)]
    ) -> any Error {
        removeStagingOnDeinit = false
        var recoveryFailures = [String]()
        do {
            try quarantineIO.publishUnavailableMarker(
                currentFailure: diagnostic(currentError),
                previousFailure: diagnostic(previousError)
            )
        } catch {
            recoveryFailures.append("marker: \(diagnostic(error))")
        }
        do {
            try quarantine(
                artifacts: artifacts,
                currentError: diagnostic(currentError),
                previousError: diagnostic(previousError)
            )
        } catch {
            recoveryFailures.append("quarantine: \(diagnostic(error))")
        }
        phase = .unavailable
        return SumiProtectionBundleRemoteUpdateError.cacheUnavailable(
            transactionId: transactionId.uuidString.lowercased(),
            current: diagnostic(currentError),
            previous: diagnostic(previousError),
            recovery: recoveryFailures.isEmpty
                ? nil
                : recoveryFailures.joined(separator: "; ")
        )
    }

    private func quarantine(
        artifacts: [(role: String, url: URL)],
        currentError: String,
        previousError: String
    ) throws {
        phase = .quarantining
        try quarantineIO.publish(
            artifacts: artifacts,
            currentFailure: currentError,
            previousFailure: previousError
        )
    }

    private func cleanupPublishedTransaction(
        clearUnavailable: Bool
    ) throws {
        phase = .cleaningUp
        try quarantineIO.cleanup(
            stagingRoot: stagingRoot,
            clearUnavailable: clearUnavailable
        )
        removeStagingOnDeinit = false
    }

    private func safeDestinationURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(
                  separator: "/",
                  omittingEmptySubsequences: false
              ).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw SumiProtectionBundleRemoteUpdateError
                .invalidRelativePath(relativePath)
        }
        let destination = stagedBundleURL.appendingPathComponent(relativePath)
        let root = stagedBundleURL.standardizedFileURL.path
        let candidate = destination.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else {
            throw SumiProtectionBundleRemoteUpdateError
                .invalidRelativePath(relativePath)
        }
        return destination
    }

    private func invalidPhaseError() -> SumiProtectionBundleRemoteUpdateError {
        .cacheTransactionStateInvalid(phase.rawValue)
    }

    private func diagnostic(_ error: any Error) -> String {
        error.localizedDescription.replacingOccurrences(
            of: rootDirectory.path,
            with: "<protection-cache>"
        )
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains(":")
    }
}

private extension Result where Success == SumiProtectionBundleValidationReceipt,
    Failure == any Error {
    var failure: (any Error)? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
