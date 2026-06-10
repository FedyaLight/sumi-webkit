//
//  SumiNativeMessagingDiagnosticCoalescer.swift
//  Sumi
//
//  Payload-free native messaging diagnostic log coalescing.
//  Never logs message bodies or credentials.
//

import Foundation

enum SumiNativeMessagingDiagnosticLogStyle: Equatable, Sendable {
    case detailed
    case summarized(repeatCount: Int, retryCountBucket: SumiNativeMessagingRetryCountBucket)
}

@MainActor
final class SumiNativeMessagingDiagnosticCoalescer {
    private struct Key: Hashable {
        let profileId: UUID?
        let extensionId: String
        let applicationIdentifier: String?
        let outcome: SafariExtensionNativeMessagingOutcome
        let direction: SafariExtensionNativeMessagingDirection
    }

    private var repeatCounts: [Key: Int] = [:]
    private var lastEmittedBucket: [Key: SumiNativeMessagingRetryCountBucket] = [:]
    private var emittedDetailed: Set<Key> = []
    private let downstream: @MainActor (
        SafariExtensionNativeMessagingDiagnostic,
        SumiNativeMessagingDiagnosticLogStyle
    ) -> Void

    init(
        downstream: @escaping @MainActor (
            SafariExtensionNativeMessagingDiagnostic,
            SumiNativeMessagingDiagnosticLogStyle
        ) -> Void
    ) {
        self.downstream = downstream
    }

    func record(
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        profileId: UUID? = nil
    ) {
        guard shouldCoalesce(diagnostic) else {
            downstream(diagnostic, .detailed)
            return
        }

        let key = Key(
            profileId: profileId,
            extensionId: diagnostic.extensionId,
            applicationIdentifier: diagnostic.requestedApplicationIdentifier
                ?? diagnostic.hostBundleIdentifier,
            outcome: coalescedOutcome(for: diagnostic),
            direction: diagnostic.direction
        )

        let repeatCount = (repeatCounts[key] ?? 0) + 1
        repeatCounts[key] = repeatCount
        let bucket = diagnostic.retryCountBucket ?? .none

        if emittedDetailed.contains(key) == false {
            emittedDetailed.insert(key)
            lastEmittedBucket[key] = bucket
            downstream(diagnostic, .detailed)
            return
        }

        let previousBucket = lastEmittedBucket[key] ?? .none
        guard bucket != previousBucket else { return }

        lastEmittedBucket[key] = bucket
        downstream(
            diagnostic,
            .summarized(repeatCount: repeatCount, retryCountBucket: bucket)
        )
    }

    func repeatCount(
        extensionId: String,
        applicationIdentifier: String?,
        outcome: SafariExtensionNativeMessagingOutcome,
        direction: SafariExtensionNativeMessagingDirection,
        profileId: UUID? = nil
    ) -> Int {
        let key = Key(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            outcome: coalescedOutcome(for: SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: direction,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: applicationIdentifier,
                resolverBucket: nil,
                outcome: outcome,
                errorDomain: nil,
                errorCode: nil
            )),
            direction: direction
        )
        return repeatCounts[key] ?? 0
    }

    func clear(forExtensionId extensionId: String, profileId: UUID? = nil) {
        repeatCounts = repeatCounts.filter { entry in
            guard entry.key.extensionId == extensionId else { return true }
            if let profileId {
                return entry.key.profileId != profileId
            }
            return false
        }
        lastEmittedBucket = lastEmittedBucket.filter { entry in
            guard entry.key.extensionId == extensionId else { return true }
            if let profileId {
                return entry.key.profileId != profileId
            }
            return false
        }
        emittedDetailed = emittedDetailed.filter { entry in
            guard entry.extensionId == extensionId else { return true }
            if let profileId {
                return entry.profileId != profileId
            }
            return false
        }
    }

    func clearAll() {
        repeatCounts.removeAll()
        lastEmittedBucket.removeAll()
        emittedDetailed.removeAll()
    }

    private func shouldCoalesce(_ diagnostic: SafariExtensionNativeMessagingDiagnostic) -> Bool {
        switch diagnostic.outcome {
        case .companionAppProtocolUnknown, .launchSuppressed, .launchRateLimited:
            return true
        default:
            return false
        }
    }

    private func coalescedOutcome(
        for diagnostic: SafariExtensionNativeMessagingDiagnostic
    ) -> SafariExtensionNativeMessagingOutcome {
        switch diagnostic.outcome {
        case .companionAppProtocolUnknown, .launchSuppressed, .launchRateLimited:
            return .companionAppProtocolUnknown
        default:
            return diagnostic.outcome
        }
    }
}
