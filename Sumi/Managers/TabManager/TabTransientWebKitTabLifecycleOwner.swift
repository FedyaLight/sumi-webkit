import Foundation
import SumiDomain
import WebKit

@MainActor
final class TabTransientWebKitTabLifecycleOwner {
    struct Dependencies {
        let settings: () -> SumiSettingsService?
        let runtimePorts: () -> RuntimePortRegistry?
        let membershipOwner: () -> TabCollectionMembershipOwner
        let regularTabCollectionOwner: () -> RegularTabCollectionOwner
        let attach: (Tab) -> Void
        let detach: (Tab) -> Void
        let targetSpace: (Space?) -> Space
        let spaceForID: (UUID) -> Space?
        let backfillTargetSpaceBootstrapProfileIfNeeded: (Space) -> Bool
        let insertRegularTab: (Tab, UUID, Int?) -> Void
        let scheduleStructuralPersistence: () -> Void
        let setActiveTab: (Tab) -> Void
        let tabForID: (UUID) -> Tab?
        let tabFactory: TabFactory
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
        if dependencies.backfillTargetSpaceBootstrapProfileIfNeeded(targetSpace) {
            dependencies.scheduleStructuralPersistence()
        }

        let sid = targetSpace.id
        let nextIndex = dependencies.regularTabCollectionOwner().appendIndex(in: sid)
        let tab = dependencies.tabFactory.makeTab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex
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
            ?? dependencies.runtimePorts()?.currentProfileId

        let tab = dependencies.tabFactory.makeTab(
            url: resolvedURL,
            name: "Popup",
            favicon: "globe",
            spaceId: openerTab?.spaceId,
            index: -1
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
        dependencies.runtimePorts()?.closeAuxiliaryMiniWindow(
            for: dependencies.tabForID(id) ?? auxiliaryTab,
            reason: .extensionRequestedClose
        )
        return true
    }

    private var resolvedSearchEngineTemplate: String {
        dependencies.settings()?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
    }

    private func unloadAndDetach(_ tab: Tab, notifyExtensionClose: Bool) {
        guard let runtimePorts = dependencies.runtimePorts() else {
            preconditionFailure(
                "TabManager.runtimePorts is nil. Transient WebKit tab cleanup requires "
                    + "BrowserManagerRuntimeWiring.attach(to:) before destructive tab operations."
            )
        }
        if notifyExtensionClose {
            runtimePorts.notifyTabClosedIfLoaded(tab)
        }
        runtimePorts.webViewLifecycle.unloadTab(tab)
        runtimePorts.webViewLifecycle.requireRemoveAllWebViews(
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

extension TabTransientWebKitTabLifecycleOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            settings: { [weak tabManager] in tabManager?.sumiSettings ?? tabManager?.runtimePorts?.settings },
            runtimePorts: { [weak tabManager] in tabManager?.runtimePorts },
            membershipOwner: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.tabCollectionMembershipOwner
            },
            regularTabCollectionOwner: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.regularTabCollectionOwner
            },
            attach: { [weak tabManager] tab in tabManager?.tabCollectionMembershipOwner.attach(tab) },
            detach: { [weak tabManager] tab in tabManager?.tabCollectionMembershipOwner.detach(tab) },
            targetSpace: { [weak tabManager] space in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.spaceLifecycleOwner.resolvedTargetSpace(preferred: space)
            },
            spaceForID: { [weak tabManager] spaceId in
                tabManager?.spaceStateOwner.space(with: spaceId)
            },
            backfillTargetSpaceBootstrapProfileIfNeeded: { [weak tabManager] space in
                tabManager?.spaceLifecycleOwner.backfillTargetSpaceBootstrapProfileIfNeeded(space) ?? false
            },
            insertRegularTab: { [weak tabManager] tab, spaceId, insertionIndex in
                tabManager?.regularTabLifecycleOwner.insertRegularTab(tab, in: spaceId, at: insertionIndex)
            },
            scheduleStructuralPersistence: { [weak tabManager] in tabManager?.scheduleStructuralPersistence() },
            setActiveTab: { [weak tabManager] tab in tabManager?.activeSelectionOwner.setActiveTab(tab) },
            tabForID: { [weak tabManager] id in tabManager?.tabCollectionMembershipOwner.tab(for: id) },
            tabFactory: tabManager.tabFactory
        )
    }
}
