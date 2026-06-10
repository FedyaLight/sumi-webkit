//
//  SumiCompanionAppLaunchPolicy.swift
//  Sumi
//
//  Bounded companion-app launch decisions via Launch Services bundle IDs only.
//

import Foundation

enum SumiCompanionAppLaunchDecision: String, Sendable, Equatable {
    case allowed
    case suppressedNoProtocolAdapter
    case suppressedProtocolUnknown
    case rateLimited
    case appNotInstalled
    case refusedArbitraryPath
}

@MainActor
final class SumiCompanionAppLaunchPolicy {
    static let shared = SumiCompanionAppLaunchPolicy()

    private var lastLaunchAttemptByBundleID: [String: Date] = [:]
    private var protocolUnknownSuppressedBundleIDs: Set<String> = []
    private let minimumLaunchInterval: TimeInterval

    init(minimumLaunchInterval: TimeInterval = 30) {
        self.minimumLaunchInterval = minimumLaunchInterval
    }

    func clearPendingState() {
        lastLaunchAttemptByBundleID.removeAll()
        protocolUnknownSuppressedBundleIDs.removeAll()
    }

    func evaluateLaunch(
        hostBundleIdentifier: String,
        appInstalled: Bool,
        protocolAdapterAvailable: Bool,
        now: Date = Date()
    ) -> SumiCompanionAppLaunchDecision {
        guard appInstalled else {
            return .appNotInstalled
        }

        guard protocolAdapterAvailable else {
            protocolUnknownSuppressedBundleIDs.insert(hostBundleIdentifier)
            return .suppressedNoProtocolAdapter
        }

        if protocolUnknownSuppressedBundleIDs.contains(hostBundleIdentifier) {
            return .suppressedProtocolUnknown
        }

        if let lastAttempt = lastLaunchAttemptByBundleID[hostBundleIdentifier],
           now.timeIntervalSince(lastAttempt) < minimumLaunchInterval
        {
            return .rateLimited
        }

        return .allowed
    }

    func recordLaunchAttempt(forHostBundleIdentifier bundleIdentifier: String, at date: Date = Date()) {
        lastLaunchAttemptByBundleID[bundleIdentifier] = date
    }

    /// Launch Services lookup only — never opens arbitrary filesystem paths.
    func launchInstalledApplication(
        hostBundleIdentifier: String,
        launcher: SumiHostApplicationLaunching
    ) async throws {
        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            throw SumiNativeMessagingRelay.makeError(
                code: .hostNotFound,
                description: "No installed application matches the resolved host bundle identifier.",
                diagnostic: nil
            )
        }

        recordLaunchAttempt(forHostBundleIdentifier: hostBundleIdentifier)
        try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
    }

    /// Refuses path-based launches outright.
    static func refusesArbitraryExecutablePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        return true
    }
}
