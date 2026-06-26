import Foundation

@MainActor
protocol SumiProtectionPreparedBundleManaging: AnyObject {
    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest?
    func preparedNativeRuleBundleDiscovery(profileId: String) -> SumiPreparedAdblockBundleDiscovery
    func installPreparedNativeRuleBundle(profileId: String) async throws -> AdblockCompiledGenerationManifest?
    func restorePreparedNativeRuleBundleForStartup(profileId: String) async throws -> AdblockCompiledGenerationManifest?
}

extension SumiAdBlockingModule: SumiProtectionPreparedBundleManaging {}

enum SumiProtectionPreparedBundleIdentity {
    static func preparedBundleProfileId(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        guard !manifest.activeGenerationId.isEmpty,
              manifest.generationSource.isPreparedBundleSource
        else { return nil }
        return installedBundleProfileId(from: manifest)
    }

    static func installedBundleProfileId(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> String? {
        guard let manifest else { return nil }
        if let bundleProfileId = manifest.bundleProfileId, !bundleProfileId.isEmpty {
            return bundleProfileId
        }
        return inferredBundleProfileId(from: manifest.nativeRuleBundleId)
    }

    private static func inferredBundleProfileId(from nativeRuleBundleId: String?) -> String? {
        guard let nativeRuleBundleId else { return nil }
        for profileId in [SumiProtectionBundleProfile.adblock] {
            if nativeRuleBundleId.contains(profileId) {
                return profileId
            }
        }
        return nil
    }
}

struct SumiProtectionBundleLifecycleDiagnostics: Equatable, Sendable {
    let remoteManifestSignatureRequired: Bool
    let remoteManifestSignatureVerified: Bool?
    let remoteSigningKeyId: String?
    let remoteSigningKeyVersion: Int?
    let lastRemoteUpdateError: String?
    let lastSignatureError: String?
    let downgradeRejected: Bool
    let lastSuccessfulBundleInstallDate: Date?
    let preparedBundleAvailable: Bool
    let preparedBundleSource: SumiAdblockBundleInstallSource?
    let searchedBundlePaths: [SumiPreparedAdblockBundleSearchPath]
}

@MainActor
final class SumiProtectionBundleLifecycle {
    let statusStore: SumiProtectionBundleUpdateStatusStore
    private let preparedBundleManager: any SumiProtectionPreparedBundleManaging
    private let remoteUpdater: any SumiProtectionBundleRemoteUpdating

    private(set) var lastBundleLookupDuration: TimeInterval?
    private var lastPreparedBundleDiscoveryProfileId: String?
    private var lastPreparedBundleDiscovery: SumiPreparedAdblockBundleDiscovery?

    init(
        preparedBundleManager: any SumiProtectionPreparedBundleManaging,
        remoteUpdater: any SumiProtectionBundleRemoteUpdating = SumiProtectionBundleRemoteUpdater(),
        statusStore: SumiProtectionBundleUpdateStatusStore = .shared
    ) {
        self.preparedBundleManager = preparedBundleManager
        self.remoteUpdater = remoteUpdater
        self.statusStore = statusStore
    }

    @discardableResult
    func ensurePreparedBundleInstalled(profileId: String) async throws -> String {
        let discovery = discoverPreparedBundle(profileId: profileId)
        let activeManifest = preparedBundleManager.activeManifestIfLoaded()
        let activePreparedBundleProfileId = activeManifest.flatMap {
            SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: $0)
        }
        let shouldInstallDiscoveredRemoteBundle = discovery.resolvedBundle?.source == .remoteReleaseBundle
            && discovery.resolvedBundle?.bundleId != activeManifest?.nativeRuleBundleId

        if activePreparedBundleProfileId != profileId || shouldInstallDiscoveredRemoteBundle {
            guard discovery.resolvedBundle != nil else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: profileId,
                    detail: discovery.failureSummary
                )
            }
            let manifest: AdblockCompiledGenerationManifest?
            do {
                manifest = try await preparedBundleManager.installPreparedNativeRuleBundle(profileId: profileId)
            } catch {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: profileId,
                    detail: error.localizedDescription
                )
            }
            try validateInstalledBundleManifest(
                manifest,
                profileId: profileId,
                unavailableDetail: "The installer did not publish the requested prepared bundle."
            )
        }

        let activePreparedProfileAfterInstall = preparedBundleManager
            .activeManifestIfLoaded()
            .flatMap { SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: $0) }
        guard activePreparedProfileAfterInstall == profileId else {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: profileId,
                detail: "The active prepared bundle after install is \(activePreparedProfileAfterInstall ?? "nil")."
            )
        }
        return profileId
    }

    func restorePreparedBundleForStartup(
        profileId: String
    ) async throws -> AdblockCompiledGenerationManifest {
        let manifest = try await preparedBundleManager.restorePreparedNativeRuleBundleForStartup(
            profileId: profileId
        )
        guard let manifest,
              SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: manifest) == profileId
        else {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: profileId,
                detail: "Startup restore did not publish the requested prepared bundle."
            )
        }
        return manifest
    }

    func updatePreparedBundlesManually(
        appliedLevel: SumiProtectionLevel,
        currentBrowserRestartRequired: Bool,
        activateInstalledBundle: @MainActor (_ summary: String) async throws -> Void
    ) async throws -> SumiProtectionBundleManualUpdateOutcome {
        let profileId = SumiProtectionBundleProfile.adblock
        do {
            let remote = try await remoteUpdater.fetchLatestApprovedBundle(profileId: profileId)
            let activeManifest = preparedBundleManager.activeManifestIfLoaded()
            let activation: SumiProtectionBundleManualUpdateActivation
            let restartRequired: Bool
            let summary: String

            if appliedLevel != .off {
                if activeManifest?.nativeRuleBundleId == remote.bundleId
                    || activeManifest?.activeGenerationId == remote.generationId {
                    activation = .alreadyCurrent
                    restartRequired = currentBrowserRestartRequired
                    summary = "Prepared bundles are already current: \(remote.releaseVersion)."
                } else {
                    let manifest = try await preparedBundleManager.installPreparedNativeRuleBundle(
                        profileId: profileId
                    )
                    guard manifest?.nativeRuleBundleId == remote.bundleId,
                          manifest?.activeGenerationId == remote.generationId
                    else {
                        throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                            profileId: profileId,
                            detail: "The remote bundle was cached but did not become the active prepared bundle."
                        )
                    }
                    activation = .installedRestartRequired
                    restartRequired = true
                    summary = "Updated prepared bundles to \(remote.releaseVersion). Restart Sumi or reload open pages before relying on the new rules."
                    try await activateInstalledBundle(summary)
                }
            } else {
                activation = .cachedOnly
                restartRequired = currentBrowserRestartRequired
                summary = "Downloaded prepared bundles \(remote.releaseVersion). They will be used after Protection or Adblock is selected and applied."
            }

            let outcome = SumiProtectionBundleManualUpdateOutcome(
                profileId: profileId,
                releaseVersion: remote.releaseVersion,
                releaseTag: remote.releaseTag,
                bundleId: remote.bundleId,
                generationId: remote.generationId,
                manifestSignatureRequired: remote.manifestSignatureRequired,
                manifestSignatureVerified: remote.manifestSignatureVerified,
                signingKeyId: remote.signingKeyId,
                signingKeyVersion: remote.signingKeyVersion,
                activation: activation,
                browserRestartRequired: restartRequired,
                summary: summary
            )
            statusStore.recordSuccess(outcome)
            return outcome
        } catch {
            statusStore.recordFailure(error)
            throw error
        }
    }

    func diagnostics(
        manifest: AdblockCompiledGenerationManifest?,
        requiredBundleProfileId: String?,
        activePreparedBundleProfileId: String?
    ) -> SumiProtectionBundleLifecycleDiagnostics {
        let preparedBundleDiscovery = requiredBundleProfileId == lastPreparedBundleDiscoveryProfileId
            ? lastPreparedBundleDiscovery
            : nil

        return SumiProtectionBundleLifecycleDiagnostics(
            remoteManifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            remoteManifestSignatureVerified: manifest?.remoteManifestSignatureVerified
                ?? statusStore.lastSignatureVerified,
            remoteSigningKeyId: manifest?.remoteSigningKeyId
                ?? statusStore.lastSigningKeyId,
            remoteSigningKeyVersion: manifest?.remoteSigningKeyVersion
                ?? statusStore.lastSigningKeyVersion,
            lastRemoteUpdateError: statusStore.lastFailureReason,
            lastSignatureError: statusStore.lastSignatureError,
            downgradeRejected: statusStore.lastDowngradeRejected ?? false,
            lastSuccessfulBundleInstallDate: manifest?.lastSuccessfulUpdateDate,
            preparedBundleAvailable: preparedBundleDiscovery?.isAvailable
                ?? (requiredBundleProfileId.map { activePreparedBundleProfileId == $0 } ?? true),
            preparedBundleSource: preparedBundleDiscovery?.source ?? (
                requiredBundleProfileId != nil && activePreparedBundleProfileId == requiredBundleProfileId
                    ? manifest?.generationSource.sumiBundleInstallSource
                    : nil
            ),
            searchedBundlePaths: preparedBundleDiscovery?.searchedPaths ?? []
        )
    }

    func clearPreparedBundleLookupDiagnostics() {
        lastBundleLookupDuration = nil
        lastPreparedBundleDiscoveryProfileId = nil
        lastPreparedBundleDiscovery = nil
    }

    private func discoverPreparedBundle(profileId: String) -> SumiPreparedAdblockBundleDiscovery {
        let discoveryStart = Date()
        let discovery = preparedBundleManager.preparedNativeRuleBundleDiscovery(profileId: profileId)
        lastBundleLookupDuration = Date().timeIntervalSince(discoveryStart)
        lastPreparedBundleDiscoveryProfileId = profileId
        lastPreparedBundleDiscovery = discovery
        return discovery
    }

    private func validateInstalledBundleManifest(
        _ manifest: AdblockCompiledGenerationManifest?,
        profileId: String,
        unavailableDetail: String
    ) throws {
        guard let manifest,
              SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: manifest) == profileId
        else {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: profileId,
                detail: unavailableDetail
            )
        }
    }
}

extension AdblockRuleGenerationSource {
    var isPreparedBundleSource: Bool {
        true
    }

    var sumiBundleInstallSource: SumiAdblockBundleInstallSource? {
        switch self {
        case .embeddedBundle:
            return .appResource
        case .developmentBundle:
            return .developmentBundle
        case .remoteReleaseBundle:
            return .remoteReleaseBundle
        }
    }
}
