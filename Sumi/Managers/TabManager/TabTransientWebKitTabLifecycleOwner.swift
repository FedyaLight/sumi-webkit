import Foundation
import WebKit

@MainActor
final class TabTransientWebKitTabLifecycleOwner {
    struct Dependencies {
        let settings: () -> SumiSettingsService?
        let runtimeContext: () -> TabManagerRuntimeContext?
        let membershipOwner: () -> TabCollectionMembershipOwner
        let regularTabCollectionOwner: () -> RegularTabCollectionOwner
        let attach: (Tab) -> Void
        let detach: (Tab) -> Void
        let targetSpace: (Space?) -> Space
        let spaceForID: (UUID) -> Space?
        let backfillTargetSpaceProfileIfNeeded: (Space, UUID?) -> Bool
        let insertRegularTab: (Tab, UUID, Int?) -> Void
        let scheduleStructuralPersistence: () -> Void
        let setActiveTab: (Tab) -> Void
        let tabForID: (UUID) -> Tab?
        let faviconService: () -> any BrowserFaviconServicing
        let faviconImageService: () -> any BrowserFaviconImageServicing
        let visitedLinkStore: () -> any BrowserVisitedLinkStoreManaging
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        dependencies.membershipOwner().isTransientExtensionTab(tab)
    }

    @discardableResult
    func createTransientExtensionTab(
        url: String,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let normalizedUrl = normalizeURL(url, queryTemplate: resolvedSearchEngineTemplate)
        let validURL = URL(string: normalizedUrl) ?? SumiSurface.emptyTabURL

        let targetSpace = dependencies.targetSpace(space)
        if dependencies.backfillTargetSpaceProfileIfNeeded(targetSpace, defaultProfileIdForSpaceBootstrap) {
            dependencies.scheduleStructuralPersistence()
        }

        let sid = targetSpace.id
        let nextIndex = dependencies.regularTabCollectionOwner().appendIndex(in: sid)
        let tab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
        tab.profileId = targetSpace.profileId
        tab.webExtensionContextOverride = webExtensionContextOverride
        dependencies.attach(tab)
        dependencies.membershipOwner().registerTransientExtensionTab(tab)
        return tab
    }

    @discardableResult
    func createAuxiliaryMiniWindowTab(
        openerTab: Tab?,
        profileId: UUID?,
        urlString: String?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let blankURL = SumiSurface.emptyTabURL
        let resolvedURL = urlString.flatMap { URL(string: $0) } ?? blankURL
        let resolvedProfileId = profileId
            ?? openerTab?.profileId
            ?? openerTab?.resolveProfile()?.id
            ?? dependencies.runtimeContext()?.currentProfileId

        let tab = Tab(
            url: resolvedURL,
            name: "Popup",
            favicon: "globe",
            spaceId: openerTab?.spaceId,
            index: -1,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
        tab.isAuxiliaryMiniWindow = true
        tab.profileId = resolvedProfileId
        tab.webExtensionContextOverride = webExtensionContextOverride
        dependencies.attach(tab)
        dependencies.membershipOwner().registerAuxiliaryMiniWindowTab(tab)
        return tab
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        dependencies.membershipOwner().removeAuxiliaryMiniWindowTab(tab)
        unloadAndDetach(tab, notifyExtensionClose: false)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        dependencies.membershipOwner().isAuxiliaryMiniWindowTab(tab)
    }

    @discardableResult
    func promoteTransientExtensionTab(
        _ tab: Tab,
        in space: Space?,
        activate: Bool
    ) -> Bool {
        guard let targetSpace = space ?? tab.spaceId.flatMap(dependencies.spaceForID) else {
            RuntimeDiagnostics.debug("Skipping transient extension tab promotion for '\(tab.name)' because no target space was resolved.", category: "TabManager")
            return false
        }
        guard dependencies.membershipOwner().promoteTransientExtensionTab(tab) else { return false }

        dependencies.insertRegularTab(tab, targetSpace.id, nil)
        dependencies.scheduleStructuralPersistence()
        if activate {
            dependencies.setActiveTab(tab)
        }
        return true
    }

    @discardableResult
    func removeTransientExtensionTab(id: UUID) -> Bool {
        guard let tab = dependencies.membershipOwner().removeTransientExtensionTab(id: id) else {
            return false
        }
        unloadAndDetach(tab, notifyExtensionClose: true)
        return true
    }

    @discardableResult
    func closeAuxiliaryMiniWindowTabIfPresent(id: UUID) -> Bool {
        guard let auxiliaryTab = dependencies.membershipOwner().auxiliaryMiniWindowTab(for: id) else {
            return false
        }
        dependencies.runtimeContext()?.closeAuxiliaryMiniWindow(
            for: dependencies.tabForID(id) ?? auxiliaryTab,
            reason: .extensionRequestedClose
        )
        return true
    }

    private var resolvedSearchEngineTemplate: String {
        dependencies.settings()?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
    }

    private var defaultProfileIdForSpaceBootstrap: UUID? {
        dependencies.runtimeContext()?.currentProfileId ?? dependencies.runtimeContext()?.defaultProfileId
    }

    private func unloadAndDetach(_ tab: Tab, notifyExtensionClose: Bool) {
        guard let runtimeContext = dependencies.runtimeContext() else {
            preconditionFailure(
                "TabManager.runtimeContext is nil. Transient WebKit tab cleanup requires BrowserManagerRuntimeWiring.attach(to:) before destructive tab operations."
            )
        }
        if notifyExtensionClose {
            runtimeContext.notifyTabClosedIfLoaded(tab)
        }
        runtimeContext.unloadTab(tab)
        runtimeContext.requireRemoveAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )
        dependencies.detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
    }
}
