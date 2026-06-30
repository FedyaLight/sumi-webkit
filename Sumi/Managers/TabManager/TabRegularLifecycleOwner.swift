import Foundation
import WebKit

@MainActor
final class TabRegularLifecycleOwner {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func addTab(_ tab: Tab, regularInsertionIndex: Int?) {
        tabManager.withStructuralUpdateTransaction {
            tabManager.attach(tab)
            if tabManager.contains(tab) { return }

            if tab.spaceId == nil {
                tab.spaceId = tabManager.currentSpace?.id
            }
            guard let sid = tab.spaceId else {
                RuntimeDiagnostics.debug("Skipping addTab for '\(tab.name)' because no spaceId was resolved.", category: "TabManager")
                return
            }
            insertRegularTab(tab, in: sid, at: regularInsertionIndex)

            // Load the tab in compositor if it's the current tab.
            if tab.id == tabManager.currentTab?.id {
                if let activeWindow = tabManager.runtimeContext?.activeWindowState {
                    tabManager.runtimeContext?.materializeVisibleTabWebViewIfNeeded(tab, in: activeWindow)
                } else {
                    tabManager.runtimeContext?.loadTab(tab)
                }
            }

            RuntimeDiagnostics.debug("Added regular tab '\(tab.name)' to space \(sid.uuidString).", category: "TabManager")
            tabManager.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func adoptGlanceTab(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space?
    ) -> Tab {
        tabManager.withStructuralUpdateTransaction {
            tabManager.attach(tab)
            if tabManager.contains(tab) { return tab }

            let targetSpace = tabManager.resolvedTargetSpace(
                preferred: space,
                fallbackSpaceId: sourceTab?.spaceId
            )
            tabManager.backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                profileId: tab.profileId ?? tabManager.runtimeContext?.currentProfileId
            )

            let insertionIndex: Int? = {
                if let sourceTab,
                   sourceTab.spaceId == targetSpace.id,
                   let sourceIndex = tabManager.regularTabCollectionOwner.firstIndex(of: sourceTab, in: targetSpace.id) {
                    return sourceIndex + 1
                }
                if sourceTab?.isPinned == true || sourceTab?.shortcutPinRole == .essential {
                    return 0
                }
                return nil
            }()

            if let currentURL = tab.existingWebView?.url {
                tab.url = currentURL
            }
            insertRegularTab(tab, in: targetSpace.id, at: insertionIndex)
            tabManager.scheduleStructuralPersistence()
            return tab
        }
    }

    @discardableResult
    func createNewTab(
        url: String,
        in space: Space?,
        activate: Bool,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        webExtensionContextOverride: WKWebExtensionContext?,
        regularInsertionIndex: Int?
    ) -> Tab {
        tabManager.withStructuralUpdateTransaction {
            let settings = tabManager.sumiSettings ?? tabManager.runtimeContext?.settings
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

            let targetSpace = tabManager.resolvedTargetSpace(preferred: space)
            if tabManager.backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                profileId: tabManager.defaultProfileIdForSpaceBootstrap
            ) {
                tabManager.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = regularInsertionIndex
                ?? tabManager.regularTabCollectionOwner.appendIndex(in: sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                faviconService: tabManager.faviconService,
                faviconImageService: tabManager.faviconImageService,
                visitedLinkStore: tabManager.visitedLinkStore
            )
            newTab.profileId = targetSpace.profileId
            newTab.webExtensionContextOverride = webExtensionContextOverride
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            addTab(newTab, regularInsertionIndex: regularInsertionIndex)
            if activate {
                tabManager.setActiveTab(newTab)
            }
            return newTab
        }
    }

    @discardableResult
    func createNewTabWithWebView(
        url: String,
        in space: Space?,
        existingWebView: WKWebView?
    ) -> Tab {
        tabManager.withStructuralUpdateTransaction {
            let settings = tabManager.sumiSettings ?? tabManager.runtimeContext?.settings
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

            let targetSpace = tabManager.resolvedTargetSpace(preferred: space)
            if tabManager.backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                profileId: tabManager.defaultProfileIdForSpaceBootstrap
            ) {
                tabManager.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = tabManager.regularTabCollectionOwner.appendIndex(in: sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                existingWebView: existingWebView,
                faviconService: tabManager.faviconService,
                faviconImageService: tabManager.faviconImageService,
                visitedLinkStore: tabManager.visitedLinkStore
            )
            addTab(newTab, regularInsertionIndex: nil)
            tabManager.setActiveTab(newTab)
            return newTab
        }
    }

    @discardableResult
    func createPopupTab(
        in space: Space?,
        activate: Bool,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        regularInsertionIndex: Int?
    ) -> Tab {
        tabManager.withStructuralUpdateTransaction {
            let targetSpace = tabManager.resolvedTargetSpace(preferred: space)
            if tabManager.backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                profileId: tabManager.defaultProfileIdForSpaceBootstrap
            ) {
                tabManager.scheduleStructuralPersistence()
            }
            let sid = targetSpace.id
            let resolvedIndex = regularInsertionIndex
                .map { tabManager.regularTabCollectionOwner.clampedInsertionIndex($0, in: sid) }
                ?? tabManager.regularTabCollectionOwner.appendIndex(in: sid)

            guard let blankURL = URL(string: "about:blank") else {
                preconditionFailure("TabManager: invalid about:blank URL")
            }
            let newTab = Tab(
                url: blankURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: resolvedIndex,
                faviconService: tabManager.faviconService,
                faviconImageService: tabManager.faviconImageService,
                visitedLinkStore: tabManager.visitedLinkStore
            )
            newTab.isPopupHost = true
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            tabManager.attach(newTab)
            insertRegularTab(newTab, in: sid, at: resolvedIndex)
            tabManager.scheduleStructuralPersistence()
            if activate {
                tabManager.setActiveTab(newTab)
            }
            return newTab
        }
    }

    func insertRegularTab(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) {
        tabManager.regularTabCollectionOwner.insert(tab, in: spaceId, at: insertionIndex)
    }
}
