import Foundation
import SumiDomain
import WebKit

enum BrowserTabOpenActivationPolicy {
    case foreground(windowState: BrowserWindowState, loadPolicy: TabSelectionLoadPolicy)
    case background
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
    private let tabManagerAction: () -> TabManager?
    private let settingsAction: () -> SumiSettingsService?
    private let activeWindowAction: () -> BrowserWindowState?
    private let windowStateContainingTabAction: (Tab) -> BrowserWindowState?
    private let canMaterializeBackgroundTabAction: (Tab) -> Bool
    private let deferBackgroundTabAction: (Tab) -> Void
    private let selectTabAction: (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void

    init(
        tabManager: @escaping () -> TabManager?,
        settings: @escaping () -> SumiSettingsService?,
        activeWindow: @escaping () -> BrowserWindowState?,
        windowStateContainingTab: @escaping (Tab) -> BrowserWindowState?,
        canMaterializeBackgroundTab: @escaping (Tab) -> Bool,
        deferBackgroundTabUntilStartupReady: @escaping (Tab) -> Void,
        selectTab: @escaping (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void
    ) {
        self.tabManagerAction = tabManager
        self.settingsAction = settings
        self.activeWindowAction = activeWindow
        self.windowStateContainingTabAction = windowStateContainingTab
        self.canMaterializeBackgroundTabAction = canMaterializeBackgroundTab
        self.deferBackgroundTabAction = deferBackgroundTabUntilStartupReady
        self.selectTabAction = selectTab
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.shellRuntime.windowTabs.windowState(containing: tab)
            },
            canMaterializeBackgroundTab: { [weak browserManager] tab in
                browserManager?.startupProtectionRuntime.canMaterializeWebViewDuringStartup(tab) ?? true
            },
            deferBackgroundTabUntilStartupReady: { [weak browserManager] tab in
                browserManager?.startupProtectionRuntime.deferBackgroundTabUntilStartupReady(tab)
            },
            selectTab: { [weak browserManager] tab, windowState, loadPolicy in
                browserManager?.selectTab(tab, in: windowState, loadPolicy: loadPolicy)
            }
        )
    }

    @discardableResult
    func createNewTab() -> Tab {
        if let activeWindow = activeWindowAction() {
            return openNewTab(context: .foreground(windowState: activeWindow))
        }

        let tabManager = requiredTabManager()
        return tabManager.regularTabLifecycleOwner.createNewTab(in: tabManager.spaceStateOwner.spaces.first)
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

        let tabManager = requiredTabManager()
        let targetSpace = resolvedTabOpenSpace(
            for: .foreground(windowState: windowState),
            tabManager: tabManager
        )
        let newTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: targetSpace,
            activate: false
        )
        windowState.markWebKitChildWindowAdopted(by: newTab.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) { [weak self, weak newTab] in
            guard let self,
                  let newTab,
                  self.tabManagerAction()?.tabCollectionMembershipOwner.tab(for: newTab.id) != nil else { return }
            self.selectTabAction(newTab, windowState, .deferred)
        }

        return newTab
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: BrowserTabOpenContext
    ) -> Tab {
        let tabManager = requiredTabManager()
        let resolvedWindowState = resolvedWindowState(for: context)

        if let resolvedWindowState,
           resolvedWindowState.isIncognito,
           let profile = resolvedWindowState.ephemeralProfile {
            let template = settingsAction()?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedURL = normalizeURL(url, queryTemplate: template)
            guard let resolvedUrl = URL(string: normalizedURL) else {
                return tabManager.ephemeralLifecycleOwner.createEphemeralTab(
                    url: SumiSurface.emptyTabURL,
                    in: resolvedWindowState,
                    profile: profile
                )
            }

            let previousTabId = resolvedWindowState.currentTabId
            let newTab = tabManager.ephemeralLifecycleOwner.createEphemeralTab(
                url: resolvedUrl,
                in: resolvedWindowState,
                profile: profile
            )
            resolvedWindowState.markWebKitChildWindowAdopted(by: newTab.id)

            switch context.activationPolicy {
            case .foreground(let windowState, let loadPolicy):
                selectTabAction(newTab, windowState, loadPolicy)
            case .background:
                resolvedWindowState.currentTabId = previousTabId
                prepareBackgroundTabIfNeeded(
                    newTab,
                    in: resolvedWindowState
                )
            }

            return newTab
        }

        let targetSpace = resolvedTabOpenSpace(
            for: context,
            tabManager: tabManager
        )
        let regularInsertionIndex = context.regularInsertionIndex
            ?? tabManager.regularTabCollectionOwner.childInsertionIndex(
                openedFrom: context.sourceTab,
                in: targetSpace
            )
        let newTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: targetSpace,
            activate: false,
            regularInsertionIndex: regularInsertionIndex
        )
        resolvedWindowState?.markWebKitChildWindowAdopted(by: newTab.id)

        switch context.activationPolicy {
        case .foreground(let windowState, let loadPolicy):
            selectTabAction(newTab, windowState, loadPolicy)
        case .background:
            prepareBackgroundTabIfNeeded(
                newTab,
                in: resolvedWindowState
            )
        }

        return newTab
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        guard let tabManager = tabManagerAction() else { return }
        let targetSpace = resolvedTabOpenSpace(
            for: .background(
                windowState: windowState,
                sourceTab: tab
            ),
            tabManager: tabManager
        )
        let insertIndex = tabManager.regularTabCollectionOwner.childInsertionIndex(
            openedFrom: tab,
            in: targetSpace
        )

        let newTab = tabManager.tabFactory.makeTab(
            url: tab.url,
            name: tab.name,
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0
        )
        newTab.faviconPresentation = tab.faviconPresentation
        newTab.faviconIsTemplateGlobePlaceholder = tab.faviconIsTemplateGlobePlaceholder
        newTab.profileId = tab.profileId

        tabManager.regularTabLifecycleOwner.addTab(newTab, regularInsertionIndex: insertIndex)
        selectTabAction(newTab, windowState, .immediate)
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        guard let tabManager = tabManagerAction() else { return nil }
        let sourceWindowState = windowStateContainingTabAction(sourceTab)
        if sourceTab.isEphemeral || sourceWindowState?.isIncognito == true {
            guard let sourceWindowState,
                  let profile = sourceWindowState.ephemeralProfile,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }

            let previousTabId = sourceWindowState.currentTabId
            let popupTab = tabManager.ephemeralLifecycleOwner.createEphemeralTab(
                url: blankURL,
                in: sourceWindowState,
                profile: profile
            )
            sourceWindowState.markWebKitChildWindowAdopted(by: popupTab.id)
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
        let targetSpace = resolvedTabOpenSpace(
            for: context,
            tabManager: tabManager
        )
        let insertionIndex = tabManager.regularTabCollectionOwner.childInsertionIndex(
            openedFrom: sourceTab,
            in: targetSpace
        )
        let popupTab = tabManager.regularTabLifecycleOwner.createPopupTab(
            in: targetSpace,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            regularInsertionIndex: insertionIndex
        )
        sourceWindowState?.markWebKitChildWindowAdopted(by: popupTab.id)
        return popupTab
    }

    func resolvedTabOpenSpace(for context: BrowserTabOpenContext) -> Space? {
        guard let tabManager = tabManagerAction() else { return nil }
        return resolvedTabOpenSpace(for: context, tabManager: tabManager)
    }

    private func resolvedTabOpenSpace(
        for context: BrowserTabOpenContext,
        tabManager: TabManager
    ) -> Space? {
        let resolvedWindowState = resolvedWindowState(for: context)

        if let preferredSpaceId = context.preferredSpaceId,
           let preferredSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == preferredSpaceId }) {
            return preferredSpace
        }

        if let windowSpaceId = resolvedWindowState?.currentSpaceId,
           let windowSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let sourceSpaceId = context.sourceTab?.spaceId,
           let sourceSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == sourceSpaceId }) {
            return sourceSpace
        }

        if let profileId = resolvedWindowState?.currentProfileId,
           let profileSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        if let sourceProfileId = context.sourceTab?.profileId,
           let sourceProfileSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == sourceProfileId }) {
            return sourceProfileSpace
        }

        return tabManager.spaceStateOwner.spaces.first
    }

    private func requiredTabManager() -> TabManager {
        guard let tabManager = tabManagerAction() else {
            preconditionFailure(
                "A tab-creation command requires a live browser kernel"
            )
        }
        return tabManager
    }

    func prepareBackgroundTabIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState?
    ) {
        guard tab.requiresPrimaryWebView else { return }
        guard canMaterializeBackgroundTabAction(tab) else {
            deferBackgroundTabAction(tab)
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
           let windowState = windowStateContainingTabAction(sourceTab) {
            return windowState
        }

        return activeWindowAction()
    }
}
