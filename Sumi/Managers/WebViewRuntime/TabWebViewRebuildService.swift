import Foundation
import SumiWebRuntime
import WebKit

enum TabWebViewRebuildResult: Equatable {
    case committed
    case deferred
    case noLiveWindows
    case failed

    var didCommit: Bool { self == .committed }
}

/// Rebuilds one tab's complete tracked WebView generation through the shared
/// replacement pipeline. It owns rebuild selection and provisional creation,
/// not repository settlement or initial-document activation.
@MainActor
final class TabWebViewRebuildService {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let pipeline: WebViewReplacementPipeline
        let activation: ReplacementNavigationActivation
        let isProtected: (WKWebView) -> Bool
        let deferProtected: (
            DeferredWebViewCommand,
            WKWebView,
            String
        ) -> DeferredProtectedCommandSchedulingOutcome
        let liveWindowIDs: () -> Set<UUID>
        let primaryCandidate: (UUID) -> TrackedWebViewOwner?
    }

    private struct PendingOwnershipRetry {
        var tab: Tab
        var preferredPrimaryWindowID: UUID?
        var targetURL: URL
        var configuration: DeferredWebViewRebuildConfiguration
        var reason: String
        var intentRevision: UInt64
        var rebuildKind: DeferredWebViewRebuildKind
    }

    private let runtime: Runtime
    private var pendingOwnershipRetries: [UUID: PendingOwnershipRetry] = [:]
    private var ownershipRetryWaiters: Set<UUID> = []

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    /// Explicit user-authorized repair of one failed physical residence. A
    /// native snapshot preserves history/form/POST semantics; callers may
    /// explicitly choose URL-only repair when no usable snapshot exists.
    func repairFailedResidence(
        tab: Tab,
        webView: WKWebView,
        useNativeSnapshot: Bool
    ) -> TabWebViewRebuildResult {
        guard let failure = tab.webContentRecoveryMarkers.recoveryState(
            on: webView
        ), failure.isFailure,
              let residence = runtime.webViewSessions.residence(of: webView),
              tab.webViewSession.residence(of: webView) == residence,
              runtime.webViewSessions.hasOwnershipTransition(for: tab.id)
                == false else {
            return .failed
        }
        let sessionData: Data?
        if useNativeSnapshot {
            guard let snapshot = failure.snapshot,
                  snapshot.residence == residence,
                  snapshot.residenceGeneration == tab.webViewSession.generation,
                  snapshot.profileID == (tab.resolveProfile()?.id ?? tab.profileId),
                  snapshot.dataStoreIdentity == PageSessionDataStoreIdentity(
                      webView.configuration.websiteDataStore
                  ),
                  snapshot.committedRevision
                    == tab.committedDocumentRuntime.authorityProof.revision,
                  WebRuntimeNavigationIdentity(snapshot.destination)
                    == WebRuntimeNavigationIdentity(failure.destination)
            else { return .failed }
            sessionData = snapshot.data
        } else {
            sessionData = nil
        }

        guard runtime.isProtected(webView) == false,
              let candidate = makeRepairCandidate(
                tab: tab,
                source: webView,
                reason: "fresh-page-repair"
              ) else { return .failed }
        let current = runtime.webViewSessions.snapshot(for: tab.id)
        let placement: WebViewReplacementPlacement
        let tracked: [WKWebView]
        let retired: WebViewSessionSnapshot
        switch residence {
        case .window(let owner):
            placement = .windowSubset(
                webViewsByWindowID: [owner.windowID: candidate]
            )
            tracked = [candidate]
            retired = WebViewSessionSnapshot(
                generation: current.generation,
                parkedWebView: nil,
                untrackedWebView: nil,
                primaryWindowID: nil,
                windowWebViews: [owner.windowID: webView]
            )
        case .parked:
            placement = .detached(webView: candidate, residence: .parked)
            tracked = []
            retired = current
        case .untracked:
            placement = .detached(webView: candidate, residence: .untracked)
            tracked = []
            retired = current
        case .retiring, .pendingCleanup:
            tab.cleanupCloneWebView(candidate)
            return .failed
        }

        let replacements = [candidate]
        let policyChangeSet: PreparedConfigurationPolicyChangeSet?
        if candidate.configuration.sumiIsNormalTabWebViewConfiguration {
            guard let prepared = tab.preparedConfigurationPolicyChangeSet(
                for: replacements
            ) else {
                tab.cleanupCloneWebView(candidate)
                return .failed
            }
            policyChangeSet = prepared
        } else {
            policyChangeSet = nil
        }
        guard let prepared = PreparedWebViewReplacement(
            tab: tab,
            snapshot: current,
            placement: placement,
            replacements: replacements,
            trackedReplacements: tracked,
            bindingReplacements: replacements,
            targetURL: failure.destination,
            semanticRevision: tab.mainFrameLoads.currentIntent.revision,
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: policyChangeSet,
            retiredSnapshot: retired,
            nativeSessionDataByWebViewID: sessionData.map {
                [ObjectIdentifier(candidate): $0]
            } ?? [:]
        ) else {
            policyChangeSet?.cancel()
            tab.cleanupCloneWebView(candidate)
            return .failed
        }

        tab.authorizeWebContentRecoveryReset(
            onCommitFrom: candidate
        )
        let start = runtime.pipeline.begin(
            [prepared],
            profileIDs: Set([prepared.profileID].compactMap { $0 }),
            model: .transaction(TabWebViewRebuildModelTransaction(
                tab: tab,
                intentRevision: tab.webViewRebuildEpoch.current,
                sourceURL: tab.url,
                targetURL: failure.destination
            )),
            completion: { [weak self] outcome in
                guard let self else { return }
                guard outcome == .committed else {
                    tab.loadingState = .idle
                    tab.navigationRuntime.webViewRouting
                        .pagePresentationDidChange(tab.id, webView)
                    return
                }
                self.runtime.activation.finishCommitted(
                    [prepared],
                    reason: "fresh-page-repair"
                )
            }
        )
        switch start {
        case .started(let receipt):
            tab.beginLoadingPresentationIfNeeded()
            runtime.activation.activate(
                [prepared],
                receipt: receipt,
                reason: "fresh-page-repair"
            )
            return .deferred
        case .committed:
            runtime.activation.activateWithoutNavigation(
                [prepared],
                reason: "fresh-page-repair"
            )
            return .committed
        case .modelCommitFailed, .rolledBack, .settlementConflict, .leaseLost:
            return .failed
        case .stale, .conflict, .invalid, .modelValidationFailed:
            discard(prepared)
            return .failed
        }
    }

    func rebuild(
        tab: Tab,
        preferredPrimaryWindowID: UUID?,
        targetURL: URL,
        configuration: DeferredWebViewRebuildConfiguration,
        reason: String,
        intentRevision: UInt64,
        rebuildKind: DeferredWebViewRebuildKind
    ) -> TabWebViewRebuildResult {
        guard tab.webViewRebuildEpoch.isCurrent(intentRevision) else {
            return .failed
        }
        let snapshot = runtime.webViewSessions.snapshot(for: tab.id)
        let targetWindowIDs = Set(snapshot.windowWebViews.keys)
            .intersection(runtime.liveWindowIDs())
        guard targetWindowIDs.isEmpty == false else { return .noLiveWindows }

        if runtime.webViewSessions.hasOwnershipTransition(for: tab.id) {
            retryAfterOwnershipBarrier(
                tab: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                targetURL: targetURL,
                configuration: configuration,
                reason: reason,
                intentRevision: intentRevision,
                rebuildKind: rebuildKind
            )
            return .deferred
        }

        let protected = runtime.webViewSessions
            .protectedCandidateWebViews(for: tab.id)
            .filter(runtime.isProtected)
        if let barrier = protected.min(by: identityOrder) {
            let intent = DeferredWebViewRebuildIntent(
                revision: intentRevision,
                targetURL: targetURL,
                configuration: configuration,
                kind: rebuildKind
            )
            let outcome = runtime.deferProtected(
                .rebuildLiveWebViews(
                    tabID: tab.id,
                    preferredPrimaryWindowID: preferredPrimaryWindowID,
                    intent: intent
                ),
                barrier,
                reason
            )
            return outcome.wasScheduled ? .deferred : .failed
        }

        guard let primaryWindowID = resolvePrimaryWindowID(
            tabID: tab.id,
            candidates: targetWindowIDs,
            preferred: preferredPrimaryWindowID
        ), let prepared = prepare(
            tab: tab,
            snapshot: snapshot,
            targetWindowIDs: targetWindowIDs,
            primaryWindowID: primaryWindowID,
            targetURL: targetURL,
            configuration: configuration,
            reason: reason
        ) else {
            return .failed
        }

        let previousURL = tab.url
        let start = runtime.pipeline.begin(
            [prepared],
            profileIDs: Set([tab.resolveProfile()?.id ?? tab.profileId].compactMap { $0 }),
            model: .transaction(TabWebViewRebuildModelTransaction(
                tab: tab,
                intentRevision: intentRevision,
                sourceURL: previousURL,
                targetURL: targetURL
            )),
            completion: { [weak self] outcome in
                guard let self, outcome == .committed else { return }
                self.runtime.activation.finishCommitted(
                    [prepared],
                    reason: reason
                )
            }
        )
        switch start {
        case .started(let receipt):
            runtime.activation.activate(
                [prepared],
                receipt: receipt,
                reason: reason
            )
            return .deferred
        case .committed:
            runtime.activation.activateWithoutNavigation(
                [prepared],
                reason: reason
            )
            return .committed
        case .conflict:
            discard(prepared)
            retryAfterOwnershipBarrier(
                tab: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                targetURL: targetURL,
                configuration: configuration,
                reason: reason,
                intentRevision: intentRevision,
                rebuildKind: rebuildKind
            )
            return .deferred
        case .stale, .modelValidationFailed:
            discard(prepared)
            return .failed
        case .invalid:
            discard(prepared)
            return .failed
        case .modelCommitFailed, .rolledBack, .settlementConflict, .leaseLost:
            return .failed
        }
    }

    private func prepare(
        tab: Tab,
        snapshot: WebViewSessionSnapshot,
        targetWindowIDs: Set<UUID>,
        primaryWindowID: UUID,
        targetURL: URL,
        configuration: DeferredWebViewRebuildConfiguration,
        reason: String
    ) -> PreparedWebViewReplacement? {
        var byWindowID: [UUID: WKWebView] = [:]
        for windowID in targetWindowIDs.sorted(by: uuidOrder) {
            let creationReason = windowID == primaryWindowID
                ? "\(reason).primary"
                : "\(reason).clone"
            let webView: WKWebView?
            switch configuration {
            case .normal:
                webView = tab.makeNormalTabWebView(reason: creationReason)
            case .currentExtensionPage:
                guard let webConfiguration =
                    tab.webExtensionContextOverride?.webViewConfiguration else {
                    byWindowID.values.forEach(tab.cleanupCloneWebView)
                    return nil
                }
                webView = tab.makeAuxiliaryOverrideTabWebView(
                    configuration: webConfiguration,
                    reason: creationReason
                )
            }
            guard let webView else {
                byWindowID.values.forEach(tab.cleanupCloneWebView)
                return nil
            }
            byWindowID[windowID] = webView
        }

        let replacements = Array(byWindowID.values)
        let configurationPolicyChangeSet:
            PreparedConfigurationPolicyChangeSet?
        if case .normal = configuration {
            guard let policyChangeSet =
                tab.preparedConfigurationPolicyChangeSet(
                    for: replacements
                ) else {
                replacements.forEach(tab.cleanupCloneWebView)
                return nil
            }
            configurationPolicyChangeSet = policyChangeSet
        } else {
            configurationPolicyChangeSet = nil
        }
        let navigation = tab.mainFrameLoads.currentIntent
        guard let preparedReplacement = PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .windowSet(
                webViewsByWindowID: byWindowID,
                primaryWindowID: primaryWindowID
            ),
            replacements: replacements,
            trackedReplacements: replacements,
            bindingReplacements: replacements,
            targetURL: targetURL,
            semanticRevision: navigation.revision,
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: configurationPolicyChangeSet
        ) else {
            configurationPolicyChangeSet?.cancel()
            replacements.forEach(tab.cleanupCloneWebView)
            return nil
        }
        return preparedReplacement
    }

    private func makeRepairCandidate(
        tab: Tab,
        source: WKWebView,
        reason: String
    ) -> WKWebView? {
        if source.configuration.sumiIsNormalTabWebViewConfiguration {
            return tab.makeNormalTabWebView(reason: reason)
        }
        guard let configuration = tab.webExtensionContextOverride?
            .webViewConfiguration else { return nil }
        return tab.makeAuxiliaryOverrideTabWebView(
            configuration: configuration,
            reason: reason
        )
    }

    private func resolvePrimaryWindowID(
        tabID: UUID,
        candidates: Set<UUID>,
        preferred: UUID?
    ) -> UUID? {
        if let preferred, candidates.contains(preferred) { return preferred }
        if let current = runtime.webViewSessions.primaryWindowID(for: tabID),
           candidates.contains(current) {
            return current
        }
        if let visible = runtime.primaryCandidate(tabID)?.windowID,
           candidates.contains(visible) {
            return visible
        }
        return candidates.min(by: uuidOrder)
    }

    private func retryAfterOwnershipBarrier(
        tab: Tab,
        preferredPrimaryWindowID: UUID?,
        targetURL: URL,
        configuration: DeferredWebViewRebuildConfiguration,
        reason: String,
        intentRevision: UInt64,
        rebuildKind: DeferredWebViewRebuildKind
    ) {
        pendingOwnershipRetries[tab.id] = PendingOwnershipRetry(
            tab: tab,
            preferredPrimaryWindowID: preferredPrimaryWindowID,
            targetURL: targetURL,
            configuration: configuration,
            reason: reason,
            intentRevision: intentRevision,
            rebuildKind: rebuildKind
        )
        guard ownershipRetryWaiters.insert(tab.id).inserted else { return }

        Task { @MainActor [weak self, weak tab] in
            guard let self, let tab else { return }
            let settled = await runtime.webViewSessions
                .waitUntilOwnershipTransitionsAreSettled()
            ownershipRetryWaiters.remove(tab.id)
            guard settled,
                  let retry = pendingOwnershipRetries.removeValue(forKey: tab.id)
            else {
                pendingOwnershipRetries.removeValue(forKey: tab.id)
                return
            }
            _ = rebuild(
                tab: retry.tab,
                preferredPrimaryWindowID: retry.preferredPrimaryWindowID,
                targetURL: retry.targetURL,
                configuration: retry.configuration,
                reason: retry.reason,
                intentRevision: retry.intentRevision,
                rebuildKind: retry.rebuildKind
            )
        }
    }

    private func discard(_ replacement: PreparedWebViewReplacement) {
        replacement.replacements.forEach(replacement.tab.cleanupCloneWebView)
    }

    private func identityOrder(_ lhs: WKWebView, _ rhs: WKWebView) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs))
            < UInt(bitPattern: ObjectIdentifier(rhs))
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
