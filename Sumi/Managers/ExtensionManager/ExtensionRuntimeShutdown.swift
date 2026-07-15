import Foundation
import WebKit

/// The single flagless terminal extension-runtime transaction. It captures an
/// exact tab rebuild plan, cancels asynchronous work, retires scoped contexts,
/// then clears bookkeeping and releases controllers only when quiescent.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeShutdown {
    enum Admission {
        case forced
        case ifNoScopedMutations
    }

    enum CompletionStatus: Equatable {
        case mutationInProgress
        case contextsRemaining
        case superseded
        case completed
    }

    struct Result {
        let completionStatus: CompletionStatus
        let contextOutcomes:
            [ExtensionRuntimeResidencyState.ScopedKey:
                ExtensionContextRetirement.Outcome]
        let remainingBindings: Set<ExtensionRuntimeResidencyState.ScopedKey>
        let tabRebuildPlan: ExtensionRuntimeTabRebuildPlan

        var completed: Bool {
            completionStatus == .completed
        }
    }

    private let activityCancellation: ExtensionRuntimeActivityCancellation
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let scopedRetirement: ExtensionScopedRuntimeRetirement
    private let bookkeepingReset: ExtensionRuntimeBookkeepingReset
    private let controllerRelease: ExtensionControllerRuntimeRelease
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let extensionLoadRevisions: ExtensionLoadRevisionAuthority
    private let sourceCache: WebExtensionRuntimeSourceCache
    private let errorObservation: ExtensionContextErrorObservation
    private let optionsWindows: ExtensionOptionsWindowService
    private let actionAnchors: ExtensionActionAnchorStore
    private let nativeMessagingPorts: ExtensionNativeMessagingPortRegistry
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        activityCancellation: ExtensionRuntimeActivityCancellation,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        scopedRetirement: ExtensionScopedRuntimeRetirement,
        bookkeepingReset: ExtensionRuntimeBookkeepingReset,
        controllerRelease: ExtensionControllerRuntimeRelease,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        runtimeCatalog: ExtensionRuntimeCatalog,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        sourceCache: WebExtensionRuntimeSourceCache,
        errorObservation: ExtensionContextErrorObservation,
        optionsWindows: ExtensionOptionsWindowService,
        actionAnchors: ExtensionActionAnchorStore,
        nativeMessagingPorts: ExtensionNativeMessagingPortRegistry,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.activityCancellation = activityCancellation
        self.mutationRegistry = mutationRegistry
        self.scopedRetirement = scopedRetirement
        self.bookkeepingReset = bookkeepingReset
        self.controllerRelease = controllerRelease
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.runtimeCatalog = runtimeCatalog
        self.extensionLoadRevisions = extensionLoadRevisions
        self.sourceCache = sourceCache
        self.errorObservation = errorObservation
        self.optionsWindows = optionsWindows
        self.actionAnchors = actionAnchors
        self.nativeMessagingPorts = nativeMessagingPorts
        self.diagnostics = diagnostics
    }

    @discardableResult
    func shutDown(
        reason: String,
        browserTabs: [Tab],
        liveWebViews: @MainActor (Tab) -> [WKWebView],
        activityResources: ExtensionRuntimeActivityCancellation.Resources,
        admission: Admission = .forced
    ) -> Result {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.runtimeShutdown"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.runtimeShutdown",
                signpostState
            )
        }

        let terminalLease: ExtensionRuntimeTerminalLease?
        switch admission {
        case .forced:
            terminalLease = mutationRegistry.beginTerminal()
        case .ifNoScopedMutations:
            terminalLease = mutationRegistry
                .beginTerminalIfNoScopedMutations()
        }
        guard let terminalLease else {
            diagnostics.trace(
                "runtimeShutdown deferred reason=\(reason) because=mutationInProgress"
            )
            return Result(
                completionStatus: .mutationInProgress,
                contextOutcomes: [:],
                remainingBindings: Set(
                    profileRuntime.contextsByProfile.flatMap {
                        profileID, contexts in
                        contexts.keys.map {
                            ExtensionRuntimeResidencyState.ScopedKey(
                                profileId: profileID,
                                extensionId: $0
                            )
                        }
                    }
                ),
                tabRebuildPlan: .empty
            )
        }
        let knownExtensionIDs = allKnownExtensionIDs()
        let hasLoadedRuntime = knownExtensionIDs.isEmpty == false
            || profileRuntime.controllersByProfile.isEmpty == false
            || runtimeLifecycle.isReadyOrLoading
        let rebuildPlan = ExtensionRuntimeTabRebuildPlan.capture(
            hasLoadedUserRuntime: hasLoadedRuntime,
            controllers: Array(profileRuntime.controllersByProfile.values),
            tabs: browserTabs,
            liveWebViews: liveWebViews
        )

        diagnostics.trace("runtimeShutdown start reason=\(reason)")
        extensionLoadRevisions.advance()
        activityCancellation.cancel(
            reason: reason,
            resources: activityResources
        )

        var outcomes:
            [ExtensionRuntimeResidencyState.ScopedKey:
                ExtensionContextRetirement.Outcome] = [:]
        var scopedRetirementsCompleted = true
        for extensionID in knownExtensionIDs {
            let result = scopedRetirement.retire(
                extensionID: extensionID,
                cause: .disabled,
                admission: .terminal(terminalLease),
                resources: .init(
                    auxiliaryWindows: activityResources.auxiliaryWindows,
                    nativeMessagingWakes:
                        activityResources.nativeMessagingWakes,
                    nativeMessagingRelay:
                        activityResources.nativeMessagingRelay
                )
            )
            outcomes.merge(result.contextOutcomes) { _, latest in latest }
            scopedRetirementsCompleted =
                scopedRetirementsCompleted && result.completed
        }

        let remainingBindings = Set(
            profileRuntime.contextsByProfile.flatMap { profileID, contexts in
                contexts.keys.map {
                    ExtensionRuntimeResidencyState.ScopedKey(
                        profileId: profileID,
                        extensionId: $0
                    )
                }
            }
        )
        guard scopedRetirementsCompleted,
              remainingBindings.isEmpty,
              mutationRegistry.isCurrent(terminalLease)
        else {
            let completionStatus: CompletionStatus =
                mutationRegistry.isCurrent(terminalLease)
                ? .contextsRemaining
                : .superseded
            diagnostics.trace(
                "runtimeShutdown incomplete reason=\(reason) "
                    + "status=\(String(describing: completionStatus)) "
                    + "remaining=\(remainingBindings.map(\.rawValue).sorted().joined(separator: ","))"
            )
            return Result(
                completionStatus: completionStatus,
                contextOutcomes: outcomes,
                remainingBindings: remainingBindings,
                tabRebuildPlan: rebuildPlan
            )
        }

        bookkeepingReset.reset()
        controllerRelease.releaseAfterShutdown()
        guard mutationRegistry.finish(terminalLease) else {
            diagnostics.trace(
                "runtimeShutdown superseded during finalization reason=\(reason)"
            )
            return Result(
                completionStatus: .superseded,
                contextOutcomes: outcomes,
                remainingBindings: [],
                tabRebuildPlan: rebuildPlan
            )
        }
        diagnostics.trace("runtimeShutdown complete reason=\(reason)")
        return Result(
            completionStatus: .completed,
            contextOutcomes: outcomes,
            remainingBindings: [],
            tabRebuildPlan: rebuildPlan
        )
    }

    func executeRebuildPlan(
        _ plan: ExtensionRuntimeTabRebuildPlan,
        reason: String,
        browserAvailable: @MainActor () -> Bool,
        canonicalTab: @MainActor (UUID) -> Tab?,
        rebuildLiveWebViews: @MainActor (Tab)
            -> ExtensionTabWebViewRebuildSubmissionOutcome
    ) -> [ExtensionRuntimeTabRebuildPlan.Execution] {
        plan.execute(
            browserAvailable: browserAvailable,
            canonicalTab: canonicalTab,
            rebuildLiveWebViews: rebuildLiveWebViews,
            trace: { [diagnostics] tab, outcome in
                diagnostics.trace(
                    "runtimeShutdown rebuild reason=\(reason) "
                        + "tab=\(tab.id.uuidString) outcome=\(String(describing: outcome))"
                )
            }
        )
    }

    private func allKnownExtensionIDs() -> Set<String> {
        var identifiers = Set(
            profileRuntime.contextsByProfile.values.flatMap(\.keys)
        )
        identifiers.formUnion(runtimeCatalog.extensionIDs)
        identifiers.formUnion(sourceCache.extensionIDs)
        identifiers.formUnion(optionsWindows.extensionIDs)
        identifiers.formUnion(nativeMessagingPorts.extensionIDs)
        identifiers.formUnion(errorObservation.observedExtensionIDs)
        identifiers.formUnion(actionAnchors.extensionIDs)
        return identifiers
    }
}
