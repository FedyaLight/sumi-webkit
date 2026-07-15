import Foundation

/// Replaces the extension-visible normal-window graph as one ordered batch.
///
/// The transaction deliberately receives concrete runtime capabilities rather
/// than `ExtensionManager`: generation state, WebView binding, adapter
/// resolution, window publication, and Tab publication stay independently
/// testable and no new manager-shaped surface is introduced.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeReloadTransaction {
    enum RetirementOutcome: Equatable {
        case retired
        case alreadyUnavailable
    }

    struct Request {
        let reason: String
        let publicationStage: ExtensionRuntimePublicationStage
        let requestedProfileID: UUID?
    }

    struct Commit {
        let runtimePublication: ExtensionRuntimePublicationEvidence
        let preparedTabCount: Int
        let activeWindow: BrowserWindowState?
        let activeTab: Tab?
    }

    struct ActivationTarget {
        let window: BrowserWindowState
        let tab: Tab
    }

    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let publicationGate: ExtensionRuntimePublicationGate
    private let profiles: ExtensionRuntimeReloadProfileReconciler
    private let tabPublication: any ExtensionNormalTabOpening
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let tabInventory: ExtensionRuntimeReloadTabInventory
    private let tabRetirement: ExtensionRuntimeReloadTabRetirement

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        normalWindows: ExtensionNormalWindowLifecycle,
        publicationGate: ExtensionRuntimePublicationGate,
        profiles: ExtensionRuntimeReloadProfileReconciler,
        tabPublication: any ExtensionNormalTabOpening,
        diagnostics: ExtensionRuntimeDiagnostics,
        tabInventory: ExtensionRuntimeReloadTabInventory,
        tabRetirement: ExtensionRuntimeReloadTabRetirement
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.normalWindows = normalWindows
        self.publicationGate = publicationGate
        self.profiles = profiles
        self.tabPublication = tabPublication
        self.diagnostics = diagnostics
        self.tabInventory = tabInventory
        self.tabRetirement = tabRetirement
    }

    /// Closes the old WebKit graph, settles every new Tab binding while normal
    /// windows are unavailable, republishes complete windows, and only then
    /// emits the new generation's Tab events.
    func reload(
        _ request: Request,
        publicationClaim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Commit? {
        let oldRuntimePublication = runtimePublicationEvidence.issue()
        let oldGeneration = oldRuntimePublication.tabPublication
        let oldTabs = tabInventory.normalBrowserTabs()
        guard let token = normalWindows.beginRuntimeReconciliation(
            publicationStage: request.publicationStage,
            closePublishedTabs: { [weak self] in
                self?.tabRetirement.closePublishedTabs(
                    oldTabs,
                    generation: oldGeneration
                )
            }
        ) else {
            return nil
        }

        // A WebKit close callback may synchronously start another lifecycle
        // operation. Never overwrite a generation chosen by that operation.
        guard runtimePublicationEvidence.isCurrent(oldRuntimePublication)
        else {
            _ = normalWindows.finishRuntimeReconciliation(
                token,
                republishing: []
            )
            return nil
        }

        guard let runtimePublication = runtimePublicationEvidence
            .advanceTabPublication(ifCurrent: oldRuntimePublication)
        else {
            _ = normalWindows.finishRuntimeReconciliation(
                token,
                republishing: []
            )
            return nil
        }
        let generation = runtimePublication.tabPublication

        for profileID in profiles.profileIDs(
            including: request.requestedProfileID
        ) {
            guard runtimePublicationEvidence.isCurrent(runtimePublication)
            else {
                _ = normalWindows.finishRuntimeReconciliation(
                    token,
                    republishing: []
                )
                return nil
            }
            profiles.reconcile(
                profileID: profileID,
                publicationStage: request.publicationStage,
                reason: request.reason
            )
        }

        guard runtimePublicationEvidence.isCurrent(runtimePublication)
        else {
            _ = normalWindows.finishRuntimeReconciliation(
                token,
                republishing: []
            )
            return nil
        }

        let tabs = tabInventory.normalBrowserTabs()
        diagnostics.trace(
            "extensionRuntimeReload start reason=\(request.reason) generation=\(generation) tabs=\(tabs.count) stage=\(String(describing: request.publicationStage))"
        )
        let preparedTabs = tabInventory.prepareTabs(
            tabs,
            generation: generation
        )
        let republishedWindows = tabInventory.allWindowStates

        guard runtimePublicationEvidence.isCurrent(runtimePublication),
              normalWindows.finishRuntimeReconciliation(
                  token,
                  republishing: republishedWindows
              )
        else {
            return nil
        }
        guard publicationGate.beginBrowserEventHandoff(publicationClaim) else {
            return nil
        }

        for tab in preparedTabs {
            guard runtimePublicationEvidence.isCurrent(runtimePublication)
            else {
                return nil
            }
            guard tab.extensionPageRuntimeOwner.isEligible(for: generation),
                  normalWindows.prepareTabOpen(tab)
            else {
                continue
            }
            _ = tabPublication.publishOpen(
                tab,
                during: publicationClaim
            )
        }

        guard runtimePublicationEvidence.isCurrent(runtimePublication)
        else {
            return nil
        }

        let activeTarget = tabInventory.activeTarget(for: generation)
        diagnostics.trace(
            "extensionRuntimeReload complete reason=\(request.reason) generation=\(generation) preparedTabs=\(preparedTabs.count)"
        )
        return Commit(
            runtimePublication: runtimePublication,
            preparedTabCount: preparedTabs.count,
            activeWindow: activeTarget?.window,
            activeTab: activeTarget?.tab
        )
    }

    /// Balances the old Tab graph while its window projections and controllers
    /// are still readable, then leaves normal-window publication unavailable.
    func retireRuntime() -> RetirementOutcome {
        let generation = runtimePublicationEvidence.issue().tabPublication
        let tabs = tabInventory.normalBrowserTabs()
        let didRetire = normalWindows.closeAllForRuntimeTeardown(
            closePublishedTabs: { [weak self] in
                self?.tabRetirement.closePublishedTabs(
                    tabs,
                    generation: generation
                )
            }
        )
        return didRetire ? .retired : .alreadyUnavailable
    }

    /// Revalidates the exact focus target after `didFocusWindow`, which is an
    /// external synchronous callback and may replace the generation, active
    /// window, or selected Tab before activation is emitted.
    func activationTarget(after commit: Commit) -> ActivationTarget? {
        guard runtimePublicationEvidence.isCurrent(
                  commit.runtimePublication
              ),
              let expectedWindow = commit.activeWindow,
              let expectedTab = commit.activeTab,
              let target = tabInventory.activeTarget(
                  expectedWindow: expectedWindow,
                  expectedTab: expectedTab,
                  generation: commit.runtimePublication.tabPublication
              ),
              normalWindows.prepareTabActivation(target.tab)
        else {
            return nil
        }
        return ActivationTarget(window: target.window, tab: target.tab)
    }
}
