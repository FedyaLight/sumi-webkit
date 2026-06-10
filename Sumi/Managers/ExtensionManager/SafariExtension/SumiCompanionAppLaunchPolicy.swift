//
//  SumiCompanionAppLaunchPolicy.swift
//  Sumi
//
//  Bounded companion-app launch decisions via Launch Services bundle IDs only.
//

import AppKit
import Foundation

enum SumiCompanionAppLaunchDecision: String, Sendable, Equatable {
    case allowed
    case suppressedNoProtocolAdapter
    case suppressedProtocolUnknown
    case suppressedConnectIfNotRunning
    case suppressedSessionLaunchAttempted
    case rateLimited
    case appNotInstalled
    case refusedArbitraryPath
}

enum SumiCompanionAppLaunchReason: String, Codable, Sendable, Equatable {
    case adapterConnect
    case adapterOneShot
    case relayConnect
    case relayOneShot
}

struct SumiCompanionAppLaunchSessionKey: Hashable, Sendable {
    let profileId: UUID?
    let extensionId: String
    let applicationIdentifier: String
}

@MainActor
final class SumiCompanionAppLaunchPolicy {
    static let shared = SumiCompanionAppLaunchPolicy()

    /// Password-manager style hosts: connect to an already-running desktop app only.
    nonisolated static let connectIfRunningHostBundleIdentifiers: Set<String> = [
        BitwardenNativeMessagingIdentifiers.hostBundleIdentifier,
    ]

    private struct SessionLaunchState {
        var lastLaunchAttemptAt: Date?
        var launchAttempted: Bool
    }

    private var lastLaunchAttemptByBundleID: [String: Date] = [:]
    private var protocolUnknownSuppressedBundleIDs: Set<String> = []
    private var sessionStateByKey: [SumiCompanionAppLaunchSessionKey: SessionLaunchState] = [:]
    private let minimumLaunchInterval: TimeInterval
    private let workspace: NSWorkspace

    init(minimumLaunchInterval: TimeInterval = 30, workspace: NSWorkspace = .shared) {
        self.minimumLaunchInterval = minimumLaunchInterval
        self.workspace = workspace
    }

    func clearPendingState() {
        lastLaunchAttemptByBundleID.removeAll()
        protocolUnknownSuppressedBundleIDs.removeAll()
        sessionStateByKey.removeAll()
    }

    func clearSessionKeys(forExtensionId extensionId: String, profileId: UUID? = nil) {
        sessionStateByKey = sessionStateByKey.filter { entry in
            guard entry.key.extensionId == extensionId else { return true }
            if let profileId {
                return entry.key.profileId != profileId
            }
            return false
        }
    }

    func clear(forExtensionId extensionId: String, profileId: UUID? = nil) {
        let removedApplicationIdentifiers = sessionStateByKey.compactMap { entry -> String? in
            guard entry.key.extensionId == extensionId else { return nil }
            if let profileId, entry.key.profileId != profileId { return nil }
            return entry.key.applicationIdentifier
        }
        for applicationIdentifier in Set(removedApplicationIdentifiers) {
            lastLaunchAttemptByBundleID.removeValue(forKey: applicationIdentifier)
        }
        clearSessionKeys(forExtensionId: extensionId, profileId: profileId)
    }

    func clearAllSessions() {
        sessionStateByKey.removeAll()
    }

    static func sessionKey(
        profileId: UUID?,
        extensionId: String,
        requestedApplicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> SumiCompanionAppLaunchSessionKey {
        SumiCompanionAppLaunchSessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: SumiNativeMessagingRelayLoopGuard.canonicalApplicationIdentifier(
                requested: requestedApplicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier
            )
        )
    }

    func isHostApplicationRunning(hostBundleIdentifier: String) -> Bool {
        workspace.runningApplications.contains {
            $0.bundleIdentifier == hostBundleIdentifier
        }
    }

    func prefersConnectIfRunning(hostBundleIdentifier: String) -> Bool {
        Self.connectIfRunningHostBundleIdentifiers.contains(hostBundleIdentifier)
    }

    func evaluateLaunch(
        hostBundleIdentifier: String,
        appInstalled: Bool,
        protocolAdapterAvailable: Bool,
        sessionKey: SumiCompanionAppLaunchSessionKey? = nil,
        isHostRunning: Bool? = nil,
        now: Date = Date()
    ) -> SumiCompanionAppLaunchDecision {
        guard appInstalled else {
            return .appNotInstalled
        }

        guard protocolAdapterAvailable else {
            protocolUnknownSuppressedBundleIDs.insert(hostBundleIdentifier)
            return .suppressedNoProtocolAdapter
        }

        // Stale suppression from pre-adapter failures must not block relay once an adapter exists.
        protocolUnknownSuppressedBundleIDs.remove(hostBundleIdentifier)

        if prefersConnectIfRunning(hostBundleIdentifier: hostBundleIdentifier) {
            let running = isHostRunning ?? isHostApplicationRunning(hostBundleIdentifier: hostBundleIdentifier)
            if running == false {
                return .suppressedConnectIfNotRunning
            }
        }

        if let sessionKey, let sessionState = sessionStateByKey[sessionKey], sessionState.launchAttempted {
            return .suppressedSessionLaunchAttempted
        }

        if let sessionKey,
           let sessionState = sessionStateByKey[sessionKey],
           let lastAttempt = sessionState.lastLaunchAttemptAt,
           now.timeIntervalSince(lastAttempt) < minimumLaunchInterval
        {
            return .rateLimited
        }

        if let lastAttempt = lastLaunchAttemptByBundleID[hostBundleIdentifier],
           now.timeIntervalSince(lastAttempt) < minimumLaunchInterval
        {
            return .rateLimited
        }

        return .allowed
    }

    func recordLaunchAttempt(
        forHostBundleIdentifier bundleIdentifier: String,
        sessionKey: SumiCompanionAppLaunchSessionKey? = nil,
        at date: Date = Date()
    ) {
        lastLaunchAttemptByBundleID[bundleIdentifier] = date
        guard let sessionKey else { return }
        var state = sessionStateByKey[sessionKey] ?? SessionLaunchState(
            lastLaunchAttemptAt: nil,
            launchAttempted: false
        )
        state.lastLaunchAttemptAt = date
        state.launchAttempted = true
        sessionStateByKey[sessionKey] = state
    }

    func recordLaunchSuppressed(
        sessionKey: SumiCompanionAppLaunchSessionKey,
        decision: SumiCompanionAppLaunchDecision
    ) {
        guard decision != .allowed else { return }
        var state = sessionStateByKey[sessionKey] ?? SessionLaunchState(
            lastLaunchAttemptAt: nil,
            launchAttempted: false
        )
        if decision == .suppressedSessionLaunchAttempted || decision == .rateLimited {
            state.launchAttempted = true
        }
        sessionStateByKey[sessionKey] = state
    }

    func sessionLaunchAttempted(sessionKey: SumiCompanionAppLaunchSessionKey) -> Bool {
        sessionStateByKey[sessionKey]?.launchAttempted ?? false
    }

    func launchCooldownBucket(
        hostBundleIdentifier: String,
        sessionKey: SumiCompanionAppLaunchSessionKey?,
        now: Date = Date()
    ) -> SumiNativeMessagingRetryCountBucket {
        if let sessionKey,
           let lastAttempt = sessionStateByKey[sessionKey]?.lastLaunchAttemptAt,
           now.timeIntervalSince(lastAttempt) < minimumLaunchInterval
        {
            return .first
        }
        if let lastAttempt = lastLaunchAttemptByBundleID[hostBundleIdentifier],
           now.timeIntervalSince(lastAttempt) < minimumLaunchInterval
        {
            return .first
        }
        return .none
    }

    /// Launch Services lookup only — never opens arbitrary filesystem paths.
    func launchInstalledApplication(
        hostBundleIdentifier: String,
        sessionKey: SumiCompanionAppLaunchSessionKey? = nil,
        launcher: SumiHostApplicationLaunching
    ) async throws {
        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            throw SumiNativeMessagingRelay.makeError(
                code: .hostNotFound,
                description: "No installed application matches the resolved host bundle identifier.",
                diagnostic: nil
            )
        }

        recordLaunchAttempt(
            forHostBundleIdentifier: hostBundleIdentifier,
            sessionKey: sessionKey
        )
        try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
    }

    /// Refuses path-based launches outright.
    static func refusesArbitraryExecutablePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        return true
    }
}
