import Foundation

enum ExtensionRuntimeDemandReason: String {
    case browserSession
    case webViewConfiguration
    case install
}

@available(macOS 15.5, *)
enum ExtensionRuntimePublicationStage: Equatable {
    case loadedRuntime
    case loadFinalization

    @MainActor
    func admits(_ loadStatus: ExtensionRuntimeLoadStatusAuthority) -> Bool {
        self == .loadFinalization || loadStatus.extensionsLoaded
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLifecycleAuthority {
    private(set) var state: ExtensionManager.ExtensionRuntimeState = .idle

    var isReady: Bool { state == .ready }

    var isReadyOrLoading: Bool {
        state == .ready || state == .loading
    }

    func markUnavailable() {
        state = .unavailable
    }

    func beginLoading() {
        state = .loading
    }

    /// Readiness discovery must not erase a terminal failure. Explicit demand
    /// may still recover a failed runtime by calling `beginLoading()` first.
    func updateReadiness(isReady: Bool) {
        guard state != .failed else { return }
        state = isReady ? .ready : .loading
    }

    func markFailed() {
        state = .failed
    }

    func resetAfterShutdown() {
        state = .idle
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeDemandAuthority {
    private var allowsRuntimeWithoutEnabledExtensions = false

    var hasRuntimeDemandWithoutEnabledExtensions: Bool {
        allowsRuntimeWithoutEnabledExtensions
    }

    func hasRuntimeDemand(hasEnabledExtensions: Bool) -> Bool {
        hasEnabledExtensions || allowsRuntimeWithoutEnabledExtensions
    }

    func recordRuntimeDemandWithoutEnabledExtensions() {
        allowsRuntimeWithoutEnabledExtensions = true
    }

    func reset() {
        allowsRuntimeWithoutEnabledExtensions = false
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLoadStatusAuthority {
    private(set) var extensionsLoaded = false

    @discardableResult
    func markExtensionsLoaded() -> Bool {
        guard extensionsLoaded == false else { return false }
        extensionsLoaded = true
        return true
    }

    @discardableResult
    func reset() -> Bool {
        guard extensionsLoaded else { return false }
        extensionsLoaded = false
        return true
    }
}

/// Owns the committed manifest and profile-scoped load outcomes for each
/// extension. Scoped retirement removes both kinds of result together so no
/// stale manifest or profile error survives an extension's runtime binding.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeCatalog {
    private var manifestsByExtensionID: [String: [String: Any]] = [:]
    private var loadErrorsByContext:
        [ExtensionRuntimeResidencyState.ScopedKey: Error] = [:]

    var extensionIDs: Set<String> {
        Set(manifestsByExtensionID.keys)
    }

    var isEmpty: Bool {
        manifestsByExtensionID.isEmpty && loadErrorsByContext.isEmpty
    }

    func manifest(for extensionID: String) -> [String: Any]? {
        manifestsByExtensionID[extensionID]
    }

    func recordManifest(
        _ manifest: [String: Any],
        for extensionID: String
    ) {
        manifestsByExtensionID[extensionID] = manifest
    }

    func recordLoadError(
        _ error: Error,
        extensionID: String,
        profileID: UUID
    ) {
        loadErrorsByContext[
            .init(profileId: profileID, extensionId: extensionID)
        ] = error
    }

    func clearLoadError(extensionID: String, profileID: UUID) {
        loadErrorsByContext.removeValue(
            forKey: .init(profileId: profileID, extensionId: extensionID)
        )
    }

    func loadError(extensionID: String, profileID: UUID) -> Error? {
        loadErrorsByContext[
            .init(profileId: profileID, extensionId: extensionID)
        ]
    }

    func hasLoadErrors(for extensionID: String) -> Bool {
        loadErrorsByContext.keys.contains { $0.extensionId == extensionID }
    }

    func retire(extensionID: String) {
        manifestsByExtensionID.removeValue(forKey: extensionID)
        loadErrorsByContext = loadErrorsByContext.filter {
            $0.key.extensionId != extensionID
        }
    }

    func reset() {
        manifestsByExtensionID.removeAll()
        loadErrorsByContext.removeAll()
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeResidencyAuthority {
    private var state = ExtensionRuntimeResidencyState()

    var liveContextKeys: [ExtensionRuntimeResidencyState.ScopedKey] {
        state.liveContextKeys
    }

    func touch(extensionID: String, profileID: UUID) {
        state.touch(extensionId: extensionID, profileId: profileID)
    }

    func remove(extensionID: String, profileID: UUID) {
        state.remove(extensionId: extensionID, profileId: profileID)
    }

    func retire(extensionID: String) {
        state.remove(extensionId: extensionID)
    }

    func reset() {
        state.removeAll()
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeMetricsAuthority {
    private var metricsByExtensionID:
        [String: ExtensionManager.ExtensionRuntimeMetrics] = [:]

    func metrics(
        for extensionID: String
    ) -> ExtensionManager.ExtensionRuntimeMetrics? {
        metricsByExtensionID[extensionID]
    }

    var isEmpty: Bool {
        metricsByExtensionID.isEmpty
    }

    func recordManifestValidationDuration(
        _ duration: TimeInterval,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.manifestValidationDuration = duration
        }
    }

    func recordWebExtensionCreationDuration(
        _ duration: TimeInterval,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.webExtensionCreationDuration = duration
        }
    }

    func recordContextLoadDuration(
        _ duration: TimeInterval,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.contextLoadDuration = duration
        }
    }

    func recordBackgroundWake(
        duration: TimeInterval,
        reason: ExtensionManager.ExtensionBackgroundWakeReason,
        didFail: Bool,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.backgroundWakeDuration = duration
            $0.backgroundWakeCount += 1
            $0.lastBackgroundWakeReason = reason
            $0.lastBackgroundWakeFailed = didFail
        }
    }

    func recordBackgroundWakeInvocation(
        reason: ExtensionManager.ExtensionBackgroundWakeReason,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.backgroundWakeCount += 1
            $0.lastBackgroundWakeReason = reason
        }
    }

    func recordErrorUpdateDuration(
        _ duration: TimeInterval,
        for extensionID: String
    ) {
        updateMetrics(for: extensionID) {
            $0.errorUpdateDuration = duration
        }
    }

    private func updateMetrics(
        for extensionID: String,
        update: (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
    ) {
        var metrics = metricsByExtensionID[extensionID]
            ?? ExtensionManager.ExtensionRuntimeMetrics()
        update(&metrics)
        metricsByExtensionID[extensionID] = metrics
    }

    func reset() {
        metricsByExtensionID.removeAll()
    }
}

struct ExtensionLoadRevision: Hashable {
    let generation: UInt64
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionLoadRevisionAuthority {
    private var generation: UInt64 = 0

    func issue() -> ExtensionLoadRevision {
        ExtensionLoadRevision(generation: generation)
    }

    @discardableResult
    func advance() -> ExtensionLoadRevision {
        generation &+= 1
        return issue()
    }

    func isCurrent(_ revision: ExtensionLoadRevision) -> Bool {
        revision.generation == generation
    }
}

struct ExtensionTabPublicationRevision: Hashable {
    let generation: UInt64
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabPublicationRevisionAuthority {
    private var generation: UInt64 = 1

    func issue() -> ExtensionTabPublicationRevision {
        ExtensionTabPublicationRevision(generation: generation)
    }

    /// Compare-and-advance preserves the reload transaction's reentrancy
    /// invariant: a nested reload wins and the older transaction cannot write
    /// a generation chosen from stale evidence.
    func advance(
        ifCurrent revision: ExtensionTabPublicationRevision
    ) -> ExtensionTabPublicationRevision? {
        guard isCurrent(revision) else { return nil }
        generation &+= 1
        return issue()
    }

    func isCurrent(_ revision: ExtensionTabPublicationRevision) -> Bool {
        revision.generation == generation
    }
}

struct ExtensionRuntimePublicationEvidence: Hashable {
    let extensionLoad: ExtensionLoadRevision
    let tabPublication: ExtensionTabPublicationRevision
}

/// Issues one synchronous MainActor snapshot across the two independent
/// revision authorities. It owns no mutable state and exposes neither
/// authority, so consumers can only capture and validate immutable evidence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationEvidenceIssuer {
    private let extensionLoadRevisions: ExtensionLoadRevisionAuthority
    private let tabPublicationRevisions:
        ExtensionTabPublicationRevisionAuthority

    init(
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    ) {
        self.extensionLoadRevisions = extensionLoadRevisions
        self.tabPublicationRevisions = tabPublicationRevisions
    }

    func issue() -> ExtensionRuntimePublicationEvidence {
        ExtensionRuntimePublicationEvidence(
            extensionLoad: extensionLoadRevisions.issue(),
            tabPublication: tabPublicationRevisions.issue()
        )
    }

    func isCurrent(_ evidence: ExtensionRuntimePublicationEvidence) -> Bool {
        extensionLoadRevisions.isCurrent(evidence.extensionLoad)
            && tabPublicationRevisions.isCurrent(evidence.tabPublication)
    }

    /// Retains the captured load epoch while compare-and-advancing only the
    /// Tab graph. A reentrant load invalidation or Tab reload rejects the old
    /// transaction instead of letting it adopt newer evidence.
    func advanceTabPublication(
        ifCurrent evidence: ExtensionRuntimePublicationEvidence
    ) -> ExtensionRuntimePublicationEvidence? {
        guard extensionLoadRevisions.isCurrent(evidence.extensionLoad),
              let tabPublication = tabPublicationRevisions.advance(
                  ifCurrent: evidence.tabPublication
              )
        else {
            return nil
        }
        return ExtensionRuntimePublicationEvidence(
            extensionLoad: evidence.extensionLoad,
            tabPublication: tabPublication
        )
    }
}
