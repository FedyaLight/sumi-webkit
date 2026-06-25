//
//  SumiNativeMessagingRelayLoopGuard.swift
//  Sumi
//
//  Generic failure-state cache and launch suppression for unsupported companion protocols.
//

import Foundation

enum SumiNativeMessagingRetryCountBucket: String, Codable, Sendable, Equatable {
    case none
    case first
    case low
    case elevated
}

@MainActor
final class SumiNativeMessagingRelayLoopGuard {
    struct SessionKey: Hashable, Sendable {
        let profileId: UUID?
        let extensionId: String
        let applicationIdentifier: String
    }

    struct Evaluation: Sendable, Equatable {
        let shouldLaunchHost: Bool
        let launchSuppressed: Bool
        let retryCountBucket: SumiNativeMessagingRetryCountBucket
        let isWithinCooldown: Bool
    }

    private struct CachedFailure {
        var retryCount: Int
        var lastFailureAt: Date
        var launchAttempted: Bool
    }

    /// Public host bundle IDs with a documented Sumi relay implementation.
    nonisolated static let supportedRelayProtocolHostBundleIdentifiers: Set<String> = Set(
        [BitwardenNativeMessagingIdentifiers.hostBundleIdentifier]
    )

    private static let baseCooldown: TimeInterval = 30
    private static let maxCooldown: TimeInterval = 300

    private var cache: [SessionKey: CachedFailure] = [:]

    static func canonicalApplicationIdentifier(
        requested requestedApplicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> String {
        let trimmed = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false {
            return SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier(trimmed)
        }
        return hostBundleIdentifier
    }

    func evaluate(
        key: SessionKey,
        hostBundleIdentifier: String
    ) -> Evaluation {
        let cached = cache[key]
        let retryBucket = retryCountBucket(for: cached?.retryCount ?? 0)
        let withinCooldown = cached.map { Date() < cooldownUntil(for: $0) } ?? false

        if Self.supportedRelayProtocolHostBundleIdentifiers.contains(hostBundleIdentifier) {
            let launchAttempted = cached?.launchAttempted ?? false
            // Supported adapters own protocol routing; never block send/connect on loop guard.
            // Launch gating is handled by SumiCompanionAppLaunchPolicy + gated launcher.
            return Evaluation(
                shouldLaunchHost: launchAttempted == false && withinCooldown == false,
                launchSuppressed: false,
                retryCountBucket: retryBucket,
                isWithinCooldown: withinCooldown
            )
        }

        if withinCooldown {
            return Evaluation(
                shouldLaunchHost: false,
                launchSuppressed: true,
                retryCountBucket: retryBucket,
                isWithinCooldown: true
            )
        }

        return Evaluation(
            shouldLaunchHost: false,
            launchSuppressed: false,
            retryCountBucket: retryBucket,
            isWithinCooldown: false
        )
    }

    func recordSupportedAdapterLaunchAttempt(key: SessionKey) {
        if var existing = cache[key] {
            existing.launchAttempted = true
            existing.lastFailureAt = Date()
            cache[key] = existing
            return
        }

        cache[key] = CachedFailure(
            retryCount: 0,
            lastFailureAt: Date(),
            launchAttempted: true
        )
    }

    func recordCompanionAppProtocolUnknown(
        key: SessionKey,
        launchAttempted: Bool
    ) {
        if var existing = cache[key] {
            existing.retryCount += 1
            existing.lastFailureAt = Date()
            existing.launchAttempted = existing.launchAttempted || launchAttempted
            cache[key] = existing
            return
        }

        cache[key] = CachedFailure(
            retryCount: 1,
            lastFailureAt: Date(),
            launchAttempted: launchAttempted
        )
    }

    /// Increments retry count for coalesced logging without extending the cooldown window.
    func recordSuppressedRetry(key: SessionKey) {
        guard var existing = cache[key] else { return }
        existing.retryCount += 1
        cache[key] = existing
    }

    func sessionState(
        policyDenial: SumiNativeMessagingRelayPolicyDenial?,
        profileRuntimeLoaded: Bool,
        evaluation: SumiCompanionAppResolverResult?,
        hostBundleIdentifier: String,
        key: SessionKey
    ) -> SumiNativeMessagingSessionState? {
        let loopEvaluation = evaluate(key: key, hostBundleIdentifier: hostBundleIdentifier)
        let adapterAvailable = evaluation?.detail?.protocolAdapterAvailable ?? false
        return SumiNativeMessagingSessionStateMachine.resolve(
            policyDenial: policyDenial,
            profileRuntimeLoaded: profileRuntimeLoaded,
            evaluation: evaluation,
            loopEvaluation: loopEvaluation,
            adapterAvailable: adapterAvailable
        )
    }

    func clear(forExtensionId extensionId: String, profileId: UUID? = nil) {
        cache = cache.filter { entry in
            guard entry.key.extensionId == extensionId else { return true }
            if let profileId {
                return entry.key.profileId != profileId
            }
            return false
        }
    }

    func clear(forProfileId profileId: UUID) {
        cache = cache.filter { $0.key.profileId != profileId }
    }

    func clearAll() {
        cache.removeAll()
    }

    private func cooldownUntil(for cached: CachedFailure) -> Date {
        let exponent = min(max(cached.retryCount - 1, 0), 4)
        let interval = min(
            Self.baseCooldown * pow(2.0, Double(exponent)),
            Self.maxCooldown
        )
        return cached.lastFailureAt.addingTimeInterval(interval)
    }

    private func retryCountBucket(for retryCount: Int) -> SumiNativeMessagingRetryCountBucket {
        switch retryCount {
        case 0:
            return .none
        case 1:
            return .first
        case 2...5:
            return .low
        default:
            return .elevated
        }
    }
}
