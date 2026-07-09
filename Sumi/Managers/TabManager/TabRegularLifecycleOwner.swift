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
        let resolvedTargetSpace: @MainActor (Space?, UUID?) -> Space
        let backfillTargetSpaceProfileIfNeeded: @MainActor (Space, UUID?) -> Bool
        let backfillTargetSpaceBootstrapProfileIfNeeded: @MainActor (Space) -> Bool
        let firstIndex: @MainActor (Tab, UUID) -> Int?
        let appendIndex: @MainActor (UUID) -> Int
        let clampedInsertionIndex: @MainActor (Int, UUID) -> Int
        let scheduleStructuralPersistence: @MainActor () -> Void
        let setActiveTab: @MainActor (Tab) -> Void
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let visitedLinkStore: @MainActor () -> any BrowserVisitedLinkStoreManaging
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
            dependencies.attach(tab)
            if dependencies.contains(tab) { return tab }

            let targetSpace = dependencies.resolvedTargetSpace(space, sourceTab?.spaceId)
            _ = dependencies.backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                tab.profileId ?? dependencies.runtimePorts()?.currentProfileId
            )

            let insertionIndex: Int? = {
                if let sourceTab,
                   sourceTab.spaceId == targetSpace.id,
                   let sourceIndex = dependencies.firstIndex(sourceTab, targetSpace.id) {
                    return sourceIndex + 1
                }
                if sourceTab?.isPinned == true || sourceTab?.shortcutPinRole == .essential {
                    return 0
                }
                return nil
            }()

            if let currentURL = dependencies.liveDocumentURL(tab) {
                tab.url = currentURL
            }
            insertRegularTab(tab, in: targetSpace.id, at: insertionIndex)
            dependencies.scheduleStructuralPersistence()
            return tab
        } ?? tab
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil,
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
                    regularInsertionIndex: regularInsertionIndex
                )
            }

            let targetSpace = dependencies.resolvedTargetSpace(space, nil)
            if dependencies.backfillTargetSpaceBootstrapProfileIfNeeded(targetSpace) {
                dependencies.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = regularInsertionIndex
                ?? dependencies.appendIndex(sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                faviconService: dependencies.faviconService(),
                faviconImageService: dependencies.faviconImageService(),
                visitedLinkStore: dependencies.visitedLinkStore()
            )
            newTab.profileId = targetSpace.profileId
            newTab.webExtensionContextOverride = webExtensionContextOverride
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            addTab(newTab, regularInsertionIndex: regularInsertionIndex)
            if activate {
                dependencies.setActiveTab(newTab)
            }
            return newTab
        } ?? makeFallbackTab()
    }

    @discardableResult
    func createNewTabWithWebView(
        url: String,
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            let settings = dependencies.settings() ?? dependencies.runtimePorts()?.settings
            let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedUrl = normalizeURL(url, queryTemplate: template)
            guard let validURL = URL(string: normalizedUrl)
            else {
                RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a WebView-backed tab; falling back to Sumi empty surface.", category: "TabManager")
                return createNewTab(
                    url: SumiSurface.emptyTabURL.absoluteString,
                    in: space,
                    activate: true,
                    webViewConfigurationOverride: nil,
                    webExtensionContextOverride: nil,
                    regularInsertionIndex: nil
                )
            }

            let targetSpace = dependencies.resolvedTargetSpace(space, nil)
            if dependencies.backfillTargetSpaceBootstrapProfileIfNeeded(targetSpace) {
                dependencies.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = dependencies.appendIndex(sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                existingWebView: existingWebView,
                faviconService: dependencies.faviconService(),
                faviconImageService: dependencies.faviconImageService(),
                visitedLinkStore: dependencies.visitedLinkStore()
            )
            addTab(newTab, regularInsertionIndex: nil)
            dependencies.setActiveTab(newTab)
            return newTab
        } ?? makeFallbackTab()
    }

    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            let targetSpace = dependencies.resolvedTargetSpace(space, nil)
            if dependencies.backfillTargetSpaceBootstrapProfileIfNeeded(targetSpace) {
                dependencies.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id
            let resolvedIndex = regularInsertionIndex
                .map { dependencies.clampedInsertionIndex($0, sid) }
                ?? dependencies.appendIndex(sid)

            guard let blankURL = URL(string: "about:blank") else {
                preconditionFailure("TabManager: invalid about:blank URL")
            }
            let newTab = Tab(
                url: blankURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: resolvedIndex,
                faviconService: dependencies.faviconService(),
                faviconImageService: dependencies.faviconImageService(),
                visitedLinkStore: dependencies.visitedLinkStore()
            )
            newTab.isPopupHost = true
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            dependencies.attach(newTab)
            insertRegularTab(newTab, in: sid, at: resolvedIndex)
            dependencies.scheduleStructuralPersistence()
            if activate {
                dependencies.setActiveTab(newTab)
            }
            return newTab
        } ?? makeFallbackTab()
    }

    func insertRegularTab(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) {
        dependencies.insertRegularTab(tab, spaceId, insertionIndex)
    }

    @discardableResult
    func duplicateAsRegularForSplit(
        from source: Tab,
        anchor: Tab,
        placeAfterAnchor: Bool = true
    ) -> Tab {
        dependencies.withStructuralUpdateTransaction {
            let targetSpace = dependencies.resolvedTargetSpace(nil, anchor.spaceId)

            let newTab = Tab(
                url: source.url,
                name: source.name,
                favicon: "globe",
                spaceId: targetSpace.id,
                index: 0,
                faviconService: dependencies.faviconService(),
                faviconImageService: dependencies.faviconImageService(),
                visitedLinkStore: dependencies.visitedLinkStore()
            )

            let insertionIndex = dependencies.firstIndex(anchor, targetSpace.id)
                .map { $0 + (placeAfterAnchor ? 1 : 0) }
            addTab(newTab, regularInsertionIndex: insertionIndex)

            return newTab
        } ?? makeFallbackTab()
    }

    private func makeFallbackTab() -> Tab {
        Tab(
            url: SumiSurface.emptyTabURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
    }
}

extension TabRegularLifecycleOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.withStructuralUpdateTransaction(operation)
            },
            settings: { [weak tabManager] in
                tabManager?.sumiSettings
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
                tabManager?.shortcutLiveTabOwner.windowStateDisplaying(tabId: tabId)
            },
            resolvedTargetSpace: { [weak tabManager] space, fallbackSpaceId in
                guard let tabManager else {
                    preconditionFailure("TabManager dependency used after deallocation")
                }
                return tabManager.spaceLifecycleOwner.resolvedTargetSpace(
                    preferred: space,
                    fallbackSpaceId: fallbackSpaceId
                )
            },
            backfillTargetSpaceProfileIfNeeded: { [weak tabManager] space, profileId in
                tabManager?.spaceLifecycleOwner.backfillTargetSpaceProfileIfNeeded(
                    space,
                    profileId: profileId
                ) ?? false
            },
            backfillTargetSpaceBootstrapProfileIfNeeded: { [weak tabManager] space in
                tabManager?.spaceLifecycleOwner.backfillTargetSpaceBootstrapProfileIfNeeded(space) ?? false
            },
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
                tabManager?.scheduleStructuralPersistence()
            },
            setActiveTab: { [weak tabManager] tab in
                tabManager?.activeSelectionOwner.setActiveTab(tab)
            },
            faviconService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconService
            },
            faviconImageService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconImageService
            },
            visitedLinkStore: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.visitedLinkStore
            },
            liveDocumentURL: { [weak tabManager] tab in
                tabManager?.runtimePorts?.webViewLifecycle.anyLiveWebView(for: tab)?.url
            }
        )
    }
}
