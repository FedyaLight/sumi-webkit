import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeReloadActiveTarget {
    let window: BrowserWindowState
    let tab: Tab
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeReloadTabInventory {
    private let tabs: any ExtensionTabInventory
    private let isAuxiliarySessionTab: @MainActor (Tab) -> Bool
    private let windows: any ExtensionWindowQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let profileRuntime: ExtensionProfileRuntime
    private let controllers: any ExtensionTabControllerQuery
    private let adapterResolution: ExtensionAdapterCatalog
    private let webViews: any ExtensionTabWebViewResidenceQuery

    init(
        tabs: any ExtensionTabInventory,
        isAuxiliarySessionTab: @escaping @MainActor (Tab) -> Bool,
        windows: any ExtensionWindowQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        controllers: any ExtensionTabControllerQuery,
        adapterResolution: ExtensionAdapterCatalog,
        webViews: any ExtensionTabWebViewResidenceQuery
    ) {
        self.tabs = tabs
        self.isAuxiliarySessionTab = isAuxiliarySessionTab
        self.windows = windows
        self.tabProfiles = tabProfiles
        self.profileRuntime = profileRuntime
        self.controllers = controllers
        self.adapterResolution = adapterResolution
        self.webViews = webViews
    }

    var allWindowStates: [BrowserWindowState] {
        windows.allExtensionWindowStates
    }

    func normalBrowserTabs() -> [Tab] {
        tabs.allExtensionTabs.filter { isAuxiliarySessionTab($0) == false }
    }

    func prepareTabs(
        _ tabs: [Tab],
        generation: ExtensionTabPublicationRevision
    ) -> [Tab] {
        let candidates = tabs.filter { tab in
            tab.extensionPageRuntimeOwner.prepareGeneration(generation)
            guard tab.isEphemeral == false,
                  let profileID = tabProfiles.profileID(for: tab),
                  let controller = profileRuntime.controller(for: profileID),
                  controllers.existingController(for: tab) === controller,
                  adapterResolution.stableAdapter(for: tab) != nil
            else { return false }
            return webViews.extensionLiveWebViews(for: tab).contains {
                $0.configuration.webExtensionController === controller
            }
        }
        let candidateIDs = Set(candidates.map(\.id))
        return candidates.filter { tab in
            guard let window = windows.preferredExtensionWindowState(
                containing: tab
            ), windows.extensionWindowState(for: window.id) === window,
                window.isIncognito == false,
                let selectedTab = windows.currentExtensionTab(in: window),
                candidateIDs.contains(selectedTab.id),
                tabProfiles.profileID(for: selectedTab)
                    == tabProfiles.profileID(for: tab)
            else { return false }
            tab.extensionPageRuntimeOwner.markEligible(for: generation)
            return true
        }
    }

    func activeTarget(
        for generation: ExtensionTabPublicationRevision
    ) -> ExtensionRuntimeReloadActiveTarget? {
        guard let window = windows.activeExtensionWindowState,
              let tab = windows.currentExtensionTab(in: window),
              tab.extensionPageRuntimeOwner.isEligible(for: generation)
        else { return nil }
        return ExtensionRuntimeReloadActiveTarget(window: window, tab: tab)
    }

    func activeTarget(
        expectedWindow: BrowserWindowState,
        expectedTab: Tab,
        generation: ExtensionTabPublicationRevision
    ) -> ExtensionRuntimeReloadActiveTarget? {
        guard let window = windows.activeExtensionWindowState,
              window === expectedWindow,
              windows.extensionWindowState(for: window.id) === window,
              let tab = windows.currentExtensionTab(in: window),
              tab === expectedTab,
              tab.extensionPageRuntimeOwner.isEligible(for: generation)
        else { return nil }
        return ExtensionRuntimeReloadActiveTarget(window: window, tab: tab)
    }
}
