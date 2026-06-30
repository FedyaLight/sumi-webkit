import Foundation
import WebKit

enum BrowserTabOpenActivationPolicy {
    case foreground(windowState: BrowserWindowState, loadPolicy: TabSelectionLoadPolicy)
    case background
}

extension BrowserTabOpeningOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            canMaterializeBackgroundTab: { [weak browserManager] tab in
                browserManager?.canMaterializeNormalTabWebViewDuringStartup(tab) ?? true
            },
            deferBackgroundTabUntilStartupReady: { [weak browserManager] tab in
                browserManager?.deferBackgroundTabUntilStartupReady(tab)
            },
            selectTab: { [weak browserManager] tab, windowState, loadPolicy in
                browserManager?.selectTab(tab, in: windowState, loadPolicy: loadPolicy)
            }
        )
    }
}

struct BrowserTabOpenContext {
    let windowState: BrowserWindowState?
    let sourceTab: Tab?
    let preferredSpaceId: UUID?
    let regularInsertionIndex: Int?
    let activationPolicy: BrowserTabOpenActivationPolicy

    static func foreground(
        windowState: BrowserWindowState,
        sourceTab: Tab? = nil,
        preferredSpaceId: UUID? = nil,
        regularInsertionIndex: Int? = nil,
        loadPolicy: TabSelectionLoadPolicy = .deferred
    ) -> BrowserTabOpenContext {
        BrowserTabOpenContext(
            windowState: windowState,
            sourceTab: sourceTab,
            preferredSpaceId: preferredSpaceId,
            regularInsertionIndex: regularInsertionIndex,
            activationPolicy: .foreground(windowState: windowState, loadPolicy: loadPolicy)
        )
    }

    static func background(
        windowState: BrowserWindowState? = nil,
        sourceTab: Tab? = nil,
        preferredSpaceId: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> BrowserTabOpenContext {
        BrowserTabOpenContext(
            windowState: windowState,
            sourceTab: sourceTab,
            preferredSpaceId: preferredSpaceId,
            regularInsertionIndex: regularInsertionIndex,
            activationPolicy: .background
        )
    }
}

@MainActor
final class BrowserTabOpeningOwner {
    struct Dependencies {
        let tabManager: () -> TabManager
        let settings: () -> SumiSettingsService?
        let activeWindow: () -> BrowserWindowState?
        let windowStateContainingTab: (Tab) -> BrowserWindowState?
        let canMaterializeBackgroundTab: (Tab) -> Bool
        let deferBackgroundTabUntilStartupReady: (Tab) -> Void
        let selectTab: (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func createNewTab() -> Tab {
        if let activeWindow = dependencies.activeWindow() {
            return openNewTab(context: .foreground(windowState: activeWindow))
        }

        return dependencies.tabManager().createNewTab()
    }

    @discardableResult
    func createNewTab(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        openNewTab(
            url: url,
            context: .foreground(windowState: windowState)
        )
    }

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        guard !windowState.isIncognito else {
            return openNewTab(
                url: url,
                context: .foreground(windowState: windowState)
            )
        }

        let tabManager = dependencies.tabManager()
        let targetSpace = resolvedTabOpenSpace(
            for: .foreground(windowState: windowState)
        )
        let newTab = tabManager.createNewTab(
            url: url,
            in: targetSpace,
            activate: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) { [weak self, weak newTab] in
            guard let self, let newTab, self.dependencies.tabManager().tab(for: newTab.id) != nil else { return }
            self.dependencies.selectTab(newTab, windowState, .deferred)
        }

        return newTab
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: BrowserTabOpenContext
    ) -> Tab {
        let tabManager = dependencies.tabManager()
        let resolvedWindowState = resolvedWindowState(for: context)

        if let resolvedWindowState,
           resolvedWindowState.isIncognito,
           let profile = resolvedWindowState.ephemeralProfile {
            let template = dependencies.settings()?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedURL = normalizeURL(url, queryTemplate: template)
            guard let resolvedUrl = URL(string: normalizedURL) else {
                return tabManager.createEphemeralTab(
                    url: SumiSurface.emptyTabURL,
                    in: resolvedWindowState,
                    profile: profile
                )
            }

            let previousTabId = resolvedWindowState.currentTabId
            let newTab = tabManager.createEphemeralTab(
                url: resolvedUrl,
                in: resolvedWindowState,
                profile: profile
            )

            switch context.activationPolicy {
            case .foreground(let windowState, let loadPolicy):
                dependencies.selectTab(newTab, windowState, loadPolicy)
            case .background:
                resolvedWindowState.currentTabId = previousTabId
                prepareBackgroundTabIfNeeded(
                    newTab,
                    in: resolvedWindowState
                )
            }

            return newTab
        }

        let targetSpace = resolvedTabOpenSpace(for: context)
        let regularInsertionIndex = context.regularInsertionIndex
            ?? tabManager.regularChildInsertionIndex(
                openedFrom: context.sourceTab,
                in: targetSpace
            )
        let newTab = tabManager.createNewTab(
            url: url,
            in: targetSpace,
            activate: false,
            regularInsertionIndex: regularInsertionIndex
        )

        switch context.activationPolicy {
        case .foreground(let windowState, let loadPolicy):
            dependencies.selectTab(newTab, windowState, loadPolicy)
        case .background:
            prepareBackgroundTabIfNeeded(
                newTab,
                in: resolvedWindowState
            )
        }

        return newTab
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        let tabManager = dependencies.tabManager()
        let targetSpace =
            windowState.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            }
            ?? tab.spaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? tabManager.currentSpace
        let insertIndex = tabManager.regularChildInsertionIndex(
            openedFrom: tab,
            in: targetSpace
        )

        let newTab = Tab(
            url: tab.url,
            name: tab.name,
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0
        )
        newTab.favicon = tab.favicon
        newTab.faviconIsTemplateGlobePlaceholder = tab.faviconIsTemplateGlobePlaceholder
        newTab.profileId = tab.profileId

        tabManager.addTab(newTab, regularInsertionIndex: insertIndex)
        dependencies.selectTab(newTab, windowState, .immediate)
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        let tabManager = dependencies.tabManager()
        let sourceWindowState = dependencies.windowStateContainingTab(sourceTab)
        if sourceTab.isEphemeral || sourceWindowState?.isIncognito == true {
            guard let sourceWindowState,
                  let profile = sourceWindowState.ephemeralProfile,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }

            let previousTabId = sourceWindowState.currentTabId
            let popupTab = tabManager.createEphemeralTab(
                url: blankURL,
                in: sourceWindowState,
                profile: profile
            )
            popupTab.isPopupHost = true
            if let webViewConfigurationOverride {
                popupTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            if activate == false {
                sourceWindowState.currentTabId = previousTabId
            }
            return popupTab
        }

        let context = BrowserTabOpenContext.background(
            windowState: sourceWindowState,
            sourceTab: sourceTab,
            preferredSpaceId: sourceTab.spaceId
        )
        let targetSpace = resolvedTabOpenSpace(for: context)
        let insertionIndex = tabManager.regularChildInsertionIndex(
            openedFrom: sourceTab,
            in: targetSpace
        )
        return tabManager.createPopupTab(
            in: targetSpace,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            regularInsertionIndex: insertionIndex
        )
    }

    func resolvedTabOpenSpace(for context: BrowserTabOpenContext) -> Space? {
        let tabManager = dependencies.tabManager()
        let resolvedWindowState = resolvedWindowState(for: context)

        if let preferredSpaceId = context.preferredSpaceId,
           let preferredSpace = tabManager.spaces.first(where: { $0.id == preferredSpaceId }) {
            return preferredSpace
        }

        if let windowSpaceId = resolvedWindowState?.currentSpaceId,
           let windowSpace = tabManager.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let sourceSpaceId = context.sourceTab?.spaceId,
           let sourceSpace = tabManager.spaces.first(where: { $0.id == sourceSpaceId }) {
            return sourceSpace
        }

        if let profileId = resolvedWindowState?.currentProfileId,
           let profileSpace = tabManager.spaces.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        if let sourceProfileId = context.sourceTab?.profileId,
           let sourceProfileSpace = tabManager.spaces.first(where: { $0.profileId == sourceProfileId }) {
            return sourceProfileSpace
        }

        return tabManager.currentSpace ?? tabManager.spaces.first
    }

    func prepareBackgroundTabIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState?
    ) {
        guard tab.requiresPrimaryWebView else { return }
        guard dependencies.canMaterializeBackgroundTab(tab) else {
            dependencies.deferBackgroundTabUntilStartupReady(tab)
            return
        }
        _ = windowState
        tab.loadWebViewIfNeeded()
    }

    private func resolvedWindowState(for context: BrowserTabOpenContext) -> BrowserWindowState? {
        if let windowState = context.windowState {
            return windowState
        }

        if let sourceTab = context.sourceTab,
           let windowState = dependencies.windowStateContainingTab(sourceTab) {
            return windowState
        }

        return dependencies.activeWindow()
    }
}
