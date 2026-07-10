import Foundation
import SumiDomain
import WebKit
import SumiWebRuntime

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

    private enum ModelError: Error { case stale }
    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
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
        guard tab.isCurrentWebViewRebuildIntent(intentRevision) else {
            return .failed
        }
        let snapshot = runtime.webViewSessions.snapshot(for: tab.id)
        let targetWindowIDs = Set(snapshot.windowWebViews.keys)
            .intersection(runtime.liveWindowIDs())
        guard targetWindowIDs.isEmpty == false else { return .noLiveWindows }

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
            validateModel: {
                tab.isCurrentWebViewRebuildIntent(intentRevision)
            },
            modelCommit: {
                guard tab.isCurrentWebViewRebuildIntent(intentRevision) else {
                    throw ModelError.stale
                }
                tab.cancelPendingMainFrameNavigation()
                tab.url = targetURL
            },
            modelRollback: {
                tab.url = previousURL
                self.restoreReloadPolicy(prepared)
            },
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
        case .stale, .modelCommitFailed:
            discard(prepared)
            return .failed
        case .invalid:
            discard(prepared)
            return .failed
        case .settlementConflict, .leaseLost:
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
        let protection =
            tab.reloadPolicyStateOwner.protectionAppliedAttachmentState
        let safari = tab.reloadPolicyStateOwner
            .safariContentBlockerAppliedAttachmentState
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
                    restoreReloadPolicy(tab, protection, safari)
                    return nil
                }
                webView = tab.makeAuxiliaryOverrideTabWebView(
                    configuration: webConfiguration,
                    reason: creationReason
                )
            }
            guard let webView else {
                byWindowID.values.forEach(tab.cleanupCloneWebView)
                restoreReloadPolicy(tab, protection, safari)
                return nil
            }
            byWindowID[windowID] = webView
        }

        let replacements = Array(byWindowID.values)
        let navigation = tab.currentMainFrameNavigationIntent()
        return PreparedWebViewReplacement(
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
            previousProtectionState: protection,
            previousSafariContentBlockerState: safari
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
        Task { @MainActor [weak self, weak tab] in
            guard let self, let tab,
                  await runtime.webViewSessions
                    .waitUntilOwnershipTransitionsAreSettled() else {
                return
            }
            _ = rebuild(
                tab: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                targetURL: targetURL,
                configuration: configuration,
                reason: reason,
                intentRevision: intentRevision,
                rebuildKind: rebuildKind
            )
        }
    }

    private func discard(_ replacement: PreparedWebViewReplacement) {
        replacement.replacements.forEach(replacement.tab.cleanupCloneWebView)
        restoreReloadPolicy(replacement)
    }

    private func restoreReloadPolicy(_ replacement: PreparedWebViewReplacement) {
        restoreReloadPolicy(
            replacement.tab,
            replacement.previousProtectionState,
            replacement.previousSafariContentBlockerState
        )
    }

    private func restoreReloadPolicy(
        _ tab: Tab,
        _ protection: SumiProtectionAttachmentState?,
        _ safari: SumiSafariContentBlockerAttachmentState?
    ) {
        tab.reloadPolicyStateOwner.noteContentBlockingWebViewRebuildFailed(
            restoringProtectionState: protection,
            restoringSafariContentBlockerState: safari
        )
    }

    private func identityOrder(_ lhs: WKWebView, _ rhs: WKWebView) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs))
            < UInt(bitPattern: ObjectIdentifier(rhs))
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
