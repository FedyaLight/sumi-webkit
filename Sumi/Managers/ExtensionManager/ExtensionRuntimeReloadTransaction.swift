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
        let allowWhenExtensionsNotLoaded: Bool
        let requestedProfileID: UUID?
        let extensionsLoaded: Bool
        let runtime: ExtensionManagerRuntime
        let windowQuery: (any ExtensionWindowQuery)?
    }

    struct Commit {
        let generation: UInt64
        let preparedTabCount: Int
        let activeWindow: BrowserWindowState?
        let activeTab: Tab?
    }

    struct ActivationTarget {
        let window: BrowserWindowState
        let tab: Tab
    }

    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let publicationGate: ExtensionRuntimePublicationGate
    private let adapterResolution: ExtensionAdapterCatalog
    private let controllers: any ExtensionTabControllerQuery
    private let controllerReconciler: ExtensionProfileWebViewRuntimeReconciler
    private let tabPublication: any ExtensionNormalTabOpening
    private let tabEvents: any ExtensionTabLifecycleEventSink
    private let isAuxiliarySessionTab: @MainActor (Tab) -> Bool
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let contentInventory: ExtensionBrowserContentInventory

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        normalWindows: ExtensionNormalWindowLifecycle,
        publicationGate: ExtensionRuntimePublicationGate,
        adapterResolution: ExtensionAdapterCatalog,
        controllers: any ExtensionTabControllerQuery,
        controllerReconciler: ExtensionProfileWebViewRuntimeReconciler,
        tabPublication: any ExtensionNormalTabOpening,
        tabEvents: any ExtensionTabLifecycleEventSink,
        isAuxiliarySessionTab: @escaping @MainActor (Tab) -> Bool,
        diagnostics: ExtensionRuntimeDiagnostics,
        contentInventory: ExtensionBrowserContentInventory = .init()
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.normalWindows = normalWindows
        self.publicationGate = publicationGate
        self.adapterResolution = adapterResolution
        self.controllers = controllers
        self.controllerReconciler = controllerReconciler
        self.tabPublication = tabPublication
        self.tabEvents = tabEvents
        self.isAuxiliarySessionTab = isAuxiliarySessionTab
        self.diagnostics = diagnostics
        self.contentInventory = contentInventory
    }

    /// Closes the old WebKit graph, settles every new Tab binding while normal
    /// windows are unavailable, republishes complete windows, and only then
    /// emits the new generation's Tab events.
    func reload(
        _ request: Request,
        publicationClaim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Commit? {
        guard request.extensionsLoaded
            || request.allowWhenExtensionsNotLoaded
        else {
            return nil
        }

        let oldGeneration = runtimeSession.tabOpenNotificationGeneration
        let oldTabs = normalBrowserTabs(in: request.runtime)
        guard let token = normalWindows.beginRuntimeReconciliation(
            allowWhenExtensionsNotLoaded:
                request.allowWhenExtensionsNotLoaded,
            closePublishedTabs: { [weak self] in
                self?.closePublishedTabs(
                    oldTabs,
                    generation: oldGeneration,
                    runtime: request.runtime
                )
            }
        ) else {
            return nil
        }

        // A WebKit close callback may synchronously start another lifecycle
        // operation. Never overwrite a generation chosen by that operation.
        guard runtimeSession.tabOpenNotificationGeneration == oldGeneration
        else {
            _ = normalWindows.finishRuntimeReconciliation(
                token,
                republishing: []
            )
            return nil
        }

        let generation = oldGeneration &+ 1
        runtimeSession.tabOpenNotificationGeneration = generation

        for profileID in profileIDsToUpdate(for: request) {
            guard runtimeSession.tabOpenNotificationGeneration == generation
            else {
                _ = normalWindows.finishRuntimeReconciliation(
                    token,
                    republishing: []
                )
                return nil
            }
            controllerReconciler.reconcile(
                profileID: profileID,
                allowWhenExtensionsNotLoaded:
                    request.allowWhenExtensionsNotLoaded,
                reason: request.reason
            )
        }

        guard runtimeSession.tabOpenNotificationGeneration == generation
        else {
            _ = normalWindows.finishRuntimeReconciliation(
                token,
                republishing: []
            )
            return nil
        }

        let tabs = normalBrowserTabs(in: request.runtime)
        diagnostics.trace(
            "extensionRuntimeReload start reason=\(request.reason) generation=\(generation) tabs=\(tabs.count) allowWhenNotLoaded=\(request.allowWhenExtensionsNotLoaded)"
        )
        let preparedTabs = prepareTabs(
            tabs,
            generation: generation,
            runtime: request.runtime,
            windowQuery: request.windowQuery
        )
        let windows = request.windowQuery?.allExtensionWindowStates ?? []

        guard runtimeSession.tabOpenNotificationGeneration == generation,
              normalWindows.finishRuntimeReconciliation(
                  token,
                  republishing: windows
              )
        else {
            return nil
        }
        guard publicationGate.beginBrowserEventHandoff(publicationClaim) else {
            return nil
        }

        for tab in preparedTabs {
            guard runtimeSession.tabOpenNotificationGeneration == generation
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

        guard runtimeSession.tabOpenNotificationGeneration == generation
        else {
            return nil
        }

        let activeWindow = request.windowQuery?.activeExtensionWindowState
        let activeTab = activeWindow.flatMap { window in
            request.windowQuery?.currentExtensionTab(in: window)
        }.flatMap { tab in
            tab.extensionPageRuntimeOwner.isEligible(for: generation)
                ? tab
                : nil
        }
        diagnostics.trace(
            "extensionRuntimeReload complete reason=\(request.reason) generation=\(generation) preparedTabs=\(preparedTabs.count)"
        )
        return Commit(
            generation: generation,
            preparedTabCount: preparedTabs.count,
            activeWindow: activeWindow,
            activeTab: activeTab
        )
    }

    /// Balances the old Tab graph while its window projections and controllers
    /// are still readable, then leaves normal-window publication unavailable.
    func retireRuntime(
        _ runtime: ExtensionManagerRuntime
    ) -> RetirementOutcome {
        let generation = runtimeSession.tabOpenNotificationGeneration
        let tabs = normalBrowserTabs(in: runtime)
        let didRetire = normalWindows.closeAllForRuntimeTeardown(
            closePublishedTabs: { [weak self] in
                self?.closePublishedTabs(
                    tabs,
                    generation: generation,
                    runtime: runtime
                )
            }
        )
        return didRetire ? .retired : .alreadyUnavailable
    }

    /// Revalidates the exact focus target after `didFocusWindow`, which is an
    /// external synchronous callback and may replace the generation, active
    /// window, or selected Tab before activation is emitted.
    func activationTarget(
        after commit: Commit,
        windowQuery: (any ExtensionWindowQuery)?
    ) -> ActivationTarget? {
        guard runtimeSession.tabOpenNotificationGeneration
                == commit.generation,
              let expectedWindow = commit.activeWindow,
              let expectedTab = commit.activeTab,
              let windowQuery,
              let activeWindow = windowQuery.activeExtensionWindowState,
              activeWindow === expectedWindow,
              windowQuery.extensionWindowState(for: activeWindow.id)
                === activeWindow,
              let activeTab = windowQuery.currentExtensionTab(
                  in: activeWindow
              ),
              activeTab === expectedTab,
              activeTab.extensionPageRuntimeOwner.isEligible(
                  for: commit.generation
              ),
              normalWindows.prepareTabActivation(activeTab)
        else {
            return nil
        }
        return ActivationTarget(window: activeWindow, tab: activeTab)
    }

    private func closePublishedTabs(
        _ tabs: [Tab],
        generation: UInt64,
        runtime: ExtensionManagerRuntime
    ) {
        for tab in tabs {
            guard tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
                let profileID = resolvedProfileID(for: tab, runtime: runtime),
                let controller = profileRuntime.controller(for: profileID),
                controllers.existingController(for: tab) === controller,
                let adapter = adapterResolution.stableAdapter(for: tab),
                profileRuntime.contexts(for: profileID).values.contains(
                    where: { context in
                        context.openTabs.contains { openTab in
                            (openTab as AnyObject) === adapter
                        }
                    }
                )
            else {
                continue
            }
            // Reserve the close before entering WebKit. Reentrant teardown can
            // still query the old projection, but cannot deliver this close a
            // second time.
            guard tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    generation: generation
                )
            else {
                continue
            }
            tabEvents.emitDidCloseTab(
                tab,
                controller: controller,
                adapter: adapter
            )
        }
    }

    private func prepareTabs(
        _ tabs: [Tab],
        generation: UInt64,
        runtime: ExtensionManagerRuntime,
        windowQuery: (any ExtensionWindowQuery)?
    ) -> [Tab] {
        var candidates: [Tab] = []
        candidates.reserveCapacity(tabs.count)

        for tab in tabs {
            tab.extensionPageRuntimeOwner.prepareGeneration(generation)
            guard tab.isEphemeral == false,
                  let profileID = resolvedProfileID(for: tab, runtime: runtime),
                  let controller = profileRuntime.controller(for: profileID),
                  controllers.existingController(for: tab) === controller,
                  adapterResolution.stableAdapter(for: tab) != nil,
                  contentInventory.liveWebViews(for: tab, in: runtime).contains(
                      where: {
                          $0.configuration.webExtensionController === controller
                      }
                  )
            else {
                continue
            }
            candidates.append(tab)
        }

        guard let windowQuery else { return [] }
        let candidateIDs = Set(candidates.map(\.id))
        var prepared: [Tab] = []
        prepared.reserveCapacity(candidates.count)

        for tab in candidates {
            guard let window = windowQuery
                .preferredExtensionWindowState(containing: tab),
                  windowQuery.extensionWindowState(for: window.id) === window,
                  window.isIncognito == false,
                  let selectedTab = windowQuery.currentExtensionTab(in: window),
                  candidateIDs.contains(selectedTab.id),
                  resolvedProfileID(for: selectedTab, runtime: runtime)
                    == resolvedProfileID(for: tab, runtime: runtime)
            else {
                continue
            }
            tab.extensionPageRuntimeOwner.markEligible(for: generation)
            prepared.append(tab)
        }
        return prepared
    }

    private func profileIDsToUpdate(for request: Request) -> Set<UUID> {
        var profileIDs = Set(profileRuntime.controllersByProfile.keys)
        if let requestedProfileID = request.requestedProfileID {
            profileIDs.insert(requestedProfileID)
        }
        if let currentProfileID = profileRuntime.currentProfileId {
            profileIDs.insert(currentProfileID)
        }
        return profileIDs
    }

    private func resolvedProfileID(
        for tab: Tab,
        runtime: ExtensionManagerRuntime
    ) -> UUID? {
        profileRuntime.resolvedProfileId(for: tab, runtime: runtime)
    }

    private func normalBrowserTabs(
        in runtime: ExtensionManagerRuntime
    ) -> [Tab] {
        contentInventory.tabs(in: runtime).filter {
            isAuxiliarySessionTab($0) == false
        }
    }
}
