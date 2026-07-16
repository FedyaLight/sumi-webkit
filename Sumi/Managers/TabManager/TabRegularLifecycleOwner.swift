import Foundation
import SumiDomain
import WebKit

@MainActor
final class TabRegularLifecycleOwner {
    struct Dependencies {
        let withStructuralUpdateTransaction: @MainActor (@MainActor () -> Tab?) -> Tab?
        let withStructuralUpdateTransactionVoid: @MainActor (@MainActor () -> Void) -> Void
        let settings: @MainActor () -> SumiSettingsService?
        let runtimePorts: @MainActor () -> RuntimePortRegistry?
        let contains: @MainActor (Tab) -> Bool
        let attach: @MainActor (Tab) -> Void
        let insertRegularTab: @MainActor (Tab, UUID, Int?) -> Void
        let currentTab: @MainActor () -> Tab?
        let windowStateDisplaying: @MainActor (UUID) -> BrowserWindowState?
        let creationPlacement: TabCreationPlacementService
        let firstIndex: @MainActor (Tab, UUID) -> Int?
        let appendIndex: @MainActor (UUID) -> Int
        let clampedInsertionIndex: @MainActor (Int, UUID) -> Int
        let scheduleStructuralPersistence: @MainActor () -> Void
        let setActiveTab: @MainActor (Tab) -> Void
        let tabFactory: TabFactory
        let liveDocumentURL: @MainActor (Tab) -> URL?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func addTab(_ tab: Tab, regularInsertionIndex: Int? = nil) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard let sid = tab.spaceId else {
                RuntimeDiagnostics.debug("Skipping addTab for '\(tab.name)' because no spaceId was resolved.", category: "TabManager")
                return
            }

            if dependencies.contains(tab) { return }
            dependencies.attach(tab)
            insertRegularTab(tab, in: sid, at: regularInsertionIndex)

            // Load the tab in compositor if it's the current tab.
            if tab.id == dependencies.currentTab()?.id {
                if let windowState = dependencies.windowStateDisplaying(tab.id) {
                    dependencies.runtimePorts()?.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
                } else {
                    dependencies.runtimePorts()?.webViewLifecycle.loadTab(tab)
                }
            }

            RuntimeDiagnostics.debug("Added regular tab '\(tab.name)' to space \(sid.uuidString).", category: "TabManager")
            dependencies.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func adoptGlanceTab(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space? = nil
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            if dependencies.contains(tab) { return tab }

            return dependencies.creationPlacement.withCreationPlacement(
                preferred: space,
                fallbackSpaceId: sourceTab?.spaceId,
                bootstrapProfileId: tab.profileId
                    ?? dependencies.runtimePorts()?.currentProfileId,
                inheritsSpaceProfile: tab.profileId == nil
            ) { placement in
                if tab.profileId == nil {
                    tab.profileId = placement.temporaryProfileOverrideId
                }
                dependencies.attach(tab)
                let insertionIndex: Int? = {
                    if let sourceTab,
                       sourceTab.spaceId == placement.space.id,
                       let sourceIndex = dependencies.firstIndex(
                           sourceTab,
                           placement.space.id
                       ) {
                        return sourceIndex + 1
                    }
                    if sourceTab?.isPinned == true
                        || sourceTab?.shortcutPinRole == .essential {
                        return 0
                    }
                    return nil
                }()

                if let currentURL = dependencies.liveDocumentURL(tab) {
                    tab.url = currentURL
                }
                insertRegularTab(
                    tab,
                    in: placement.space.id,
                    at: insertionIndex
                )
                dependencies.scheduleStructuralPersistence()
                return tab
            }
        } ?? tab
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil,
        executionProfileID: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            let settings = dependencies.settings() ?? dependencies.runtimePorts()?.settings
            let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedUrl = normalizeURL(url, queryTemplate: template)
            guard let validURL = URL(string: normalizedUrl)
            else {
                RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a new tab; falling back to Sumi empty surface.", category: "TabManager")
                return createNewTab(
                    url: SumiSurface.emptyTabURL.absoluteString,
                    in: space,
                    activate: activate,
                    webViewConfigurationOverride: webViewConfigurationOverride,
                    webExtensionContextOverride: webExtensionContextOverride,
                    executionProfileID: executionProfileID,
                    regularInsertionIndex: regularInsertionIndex
                )
            }

            let newTab = dependencies.creationPlacement.withCreationPlacement(
                preferred: space,
                inheritsSpaceProfile: executionProfileID == nil
            ) { placement in
                let nextIndex = regularInsertionIndex
                    ?? dependencies.appendIndex(placement.space.id)
                let tab = dependencies.tabFactory.makeTab(
                    url: validURL,
                    name: "New Tab",
                    favicon: "globe",
                    spaceId: placement.space.id,
                    index: nextIndex
                )
                tab.profileId = executionProfileID
                    ?? placement.temporaryProfileOverrideId
                tab.webExtensionContextOverride = webExtensionContextOverride
                if let webViewConfigurationOverride {
                    tab.applyWebViewConfigurationOverride(
                        webViewConfigurationOverride
                    )
                }
                addTab(tab, regularInsertionIndex: regularInsertionIndex)
                return tab
            }
            if activate {
                dependencies.setActiveTab(newTab)
            }
            return newTab
        } ?? makeFallbackTab()
    }

    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        executionProfileID: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            guard let blankURL = URL(string: "about:blank") else {
                preconditionFailure("TabManager: invalid about:blank URL")
            }
            let newTab = dependencies.creationPlacement.withCreationPlacement(
                preferred: space,
                inheritsSpaceProfile: executionProfileID == nil
            ) { placement in
                let resolvedIndex = regularInsertionIndex
                    .map {
                        dependencies.clampedInsertionIndex(
                            $0,
                            placement.space.id
                        )
                    }
                    ?? dependencies.appendIndex(placement.space.id)
                let tab = dependencies.tabFactory.makeTab(
                    url: blankURL,
                    name: "New Tab",
                    favicon: "globe",
                    spaceId: placement.space.id,
                    index: resolvedIndex
                )
                tab.profileId = executionProfileID
                    ?? placement.temporaryProfileOverrideId
                tab.isPopupHost = true
                if let webViewConfigurationOverride {
                    tab.applyWebViewConfigurationOverride(
                        webViewConfigurationOverride
                    )
                }
                dependencies.attach(tab)
                insertRegularTab(
                    tab,
                    in: placement.space.id,
                    at: resolvedIndex
                )
                dependencies.scheduleStructuralPersistence()
                return tab
            }
            if activate {
                dependencies.setActiveTab(newTab)
            }
            return newTab
        } ?? makeFallbackTab()
    }

    func insertRegularTab(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) {
        dependencies.insertRegularTab(tab, spaceId, insertionIndex)
    }

    private func makeFallbackTab() -> Tab {
        dependencies.tabFactory.makeTab(
            url: SumiSurface.emptyTabURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0
        )
    }
}

extension TabRegularLifecycleOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            settings: { [weak tabManager] in
                tabManager?.runtimePortConnection.current?.settings
            },
            runtimePorts: { [weak tabManager] in
                tabManager?.runtimePorts
            },
            contains: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.contains(tab) ?? false
            },
            attach: { [weak tabManager] tab in
                tabManager?.tabCollectionMembershipOwner.attach(tab)
            },
            insertRegularTab: { [weak tabManager] tab, spaceId, insertionIndex in
                tabManager?.regularTabCollectionOwner.insert(tab, in: spaceId, at: insertionIndex)
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            windowStateDisplaying: { [weak tabManager] tabId in
                tabManager?.shortcutTabWindowQuery.windowStateDisplaying(tabId: tabId)
            },
            creationPlacement: tabManager.spaceServices.placement,
            firstIndex: { [weak tabManager] tab, spaceId in
                tabManager?.regularTabCollectionOwner.firstIndex(of: tab, in: spaceId)
            },
            appendIndex: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.appendIndex(in: spaceId) ?? 0
            },
            clampedInsertionIndex: { [weak tabManager] index, spaceId in
                tabManager?.regularTabCollectionOwner.clampedInsertionIndex(index, in: spaceId) ?? index
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            setActiveTab: { [weak tabManager] tab in
                tabManager?.activeSelectionOwner.setActiveTab(tab)
            },
            tabFactory: tabManager.tabFactory,
            liveDocumentURL: { [weak tabManager] tab in
                tabManager?.runtimePorts?.webViewLifecycle.anyLiveWebView(for: tab)?.url
            }
        )
    }
}
