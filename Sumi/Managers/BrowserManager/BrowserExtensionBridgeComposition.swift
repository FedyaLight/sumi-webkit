//
//  BrowserExtensionBridgeComposition.swift
//  Sumi
//
//  App-level construction of the browser capabilities exposed to WebExtensions.
//

import Foundation

/// Composition root only. Extension consumers receive the exact capability
/// they need; this type intentionally exposes no forwarding methods.
@MainActor
final class BrowserExtensionBridgeComposition {
    let availability: ExtensionBrowserRuntimeAvailability
    let tabResidences: BrowserTabResidenceAuthority
    let profiles: ExtensionBrowserProfileQuery
    let websiteDataAdmission: ExtensionWebsiteDataMutationAdmission
    let windows: BrowserExtensionWindowQueryAdapter
    let tabs: BrowserExtensionTabQueryAdapter
    let requestedTabTargets: BrowserRequestedTabTargetAdapter
    let tabMutation: BrowserExtensionTabMutationAdapter
    let windowActivation: BrowserExtensionWindowActivationAdapter
    let webViews: BrowserExtensionWebViewAdapter
    let auxiliaryWindows: BrowserExtensionAuxiliaryWindowAdapter
    let presentation: BrowserExtensionWindowPresentationAdapter
    let requestedWindows: BrowserExtensionRequestedWindowTransaction

    init(
        browserManager: BrowserManager,
        tabCommands: BrowserExtensionTabCommands
    ) {
        availability = ExtensionBrowserRuntimeAvailability {
            [weak browserManager] in browserManager != nil
        }
        tabResidences = browserManager.tabResidenceAuthority
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let profileManager = browserManager.profileManager
        let tabStore = browserManager.runtimeStore
        let windowSelection = browserManager.shellRuntime.windowSelection
        let windowTabs = browserManager.shellRuntime.windowTabs
        let membership = browserManager
            .tabCollectionMembershipOwner
        let auxiliaryTabs = browserManager.auxiliaryMiniWindowTabs
        let shortcutPresentation = browserManager
            .shortcutPresentationOwner
        let spaces = browserManager.spaceStateOwner
        profiles = ExtensionBrowserProfileQuery(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            profile: { [profileManager] profileID in
                profileManager.profiles.first {
                    $0.id == profileID
                }
            },
            ephemeralProfile: { [weak browserManager] profileID in
                browserManager?.windowRegistry.windows.values
                    .compactMap(\.ephemeralProfile)
                    .first { $0.id == profileID }
            }
        )
        websiteDataAdmission = ExtensionWebsiteDataMutationAdmission(
            isBlocked: { [weak browserManager] profileID in
                browserManager?.webViewRuntime.websiteDataCleanupService
                    .admissionIsBlocked(profileID: profileID) ?? false
            },
            wait: { [weak browserManager] profileID in
                guard let browserManager else { return false }
                return await browserManager.webViewRuntime
                    .websiteDataCleanupService.waitForAdmission(
                        profileID: profileID
                    )
            }
        )
        let webViewOwnershipQuery = browserManager.webViewRuntime.ownershipQuery
        let extensionTabWebViewReplacement = browserManager.webViewRuntime
            .extensionTabWebViewReplacement
        let windows = BrowserExtensionWindowQueryAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            primaryTrackedWindowID: { [webViewOwnershipQuery] tabID in
                webViewOwnershipQuery.primaryWindowID(for: tabID)
            },
            tabs: { [windowSelection, tabStore] windowState in
                windowSelection.tabsForWebExtensionWindow(
                        in: windowState,
                        tabStore: tabStore
                    )
            },
            currentTab: { [windowTabs] windowState in
                windowTabs.currentTab(for: windowState)
            },
            currentTabForActiveWindow: { [weak browserManager, windowTabs] in
                guard let browserManager,
                      let activeWindow = browserManager.windowRegistry.activeWindow
                else { return nil }
                return windowTabs.currentTab(for: activeWindow)
            },
            windowContainingTab: { [windowTabs] tab in
                windowTabs.windowState(containing: tab)
            }
        )

        let tabs = BrowserExtensionTabQueryAdapter(
            regularTab: { [membership] tabID in
                membership.tab(for: tabID)
            },
            allTabs: { [membership, windows] in
                membership.allTabs()
                    + windows.allExtensionWindowStates.flatMap(\.ephemeralTabs)
            },
            windows: { [windows] in
                windows.allExtensionWindowStates
            },
            isTransient: { [tabCommands] tab in
                tabCommands.containsTransient(tab)
            },
            isAuxiliaryMiniWindow: { [auxiliaryTabs] tab in
                auxiliaryTabs.containsExact(tab)
            },
            isPinned: { [shortcutPresentation] tab in
                tab.isPinned || shortcutPresentation.activeShortcutTabs()
                    .contains(where: { $0.id == tab.id }) == true
            }
        )

        let requestedTabTargets = BrowserRequestedTabTargetAdapter(
            windows: windows,
            space: { [spaces] spaceID in
                spaces.space(with: spaceID)
            },
            firstSpace: { [spaces] profileID in
                spaces.firstSpace(forProfile: profileID)
            },
            auxiliarySessions: browserManager.auxiliaryWindows.sessions
        )

        let tabMutation = BrowserExtensionTabMutationComposition.make(
            commands: tabCommands,
            selection: browserManager.browserTabSelection
        )

        let windowActivation = BrowserExtensionWindowActivationAdapter(
            activate: { [weak browserManager] windowState in
                browserManager?.windowRegistry.setActive(windowState)
            }
        )

        let webViews = BrowserExtensionWebViewAdapter(
            liveWebView: { [webViewOwnershipQuery, tabs] tab in
                guard tabs.extensionTab(for: tab.id) === tab else {
                    return nil
                }
                if let windowID = webViewOwnershipQuery.primaryWindowID(
                    for: tab.id
                ), let webView = webViewOwnershipQuery.webView(
                    for: tab.id,
                    in: windowID
                ), (webView as? FocusableWKWebView)?.owningTab === tab {
                    return webView
                }
                return webViewOwnershipQuery.untrackedOwnedWebView(for: tab)
            },
            liveWebViews: { [webViewOwnershipQuery, tabs] tab in
                guard tabs.extensionTab(for: tab.id) === tab else { return [] }
                var candidates = webViewOwnershipQuery.trackedLiveWebViews(
                    for: tab
                )
                if let untracked = webViewOwnershipQuery
                    .untrackedOwnedWebView(for: tab) {
                    candidates.append(untracked)
                }
                var seen = Set<ObjectIdentifier>()
                return candidates.filter { webView in
                    (webView as? FocusableWKWebView)?.owningTab === tab
                        && seen.insert(ObjectIdentifier(webView)).inserted
                }
            },
            untrackedWebView: { [webViewOwnershipQuery, tabs] tab in
                guard tabs.extensionTab(for: tab.id) === tab else { return nil }
                return webViewOwnershipQuery.untrackedOwnedWebView(for: tab)
            },
            rebuildLiveWebViews: { [weak browserManager, tabs] tab, reason in
                guard tabs.extensionTab(for: tab.id) === tab,
                      let manager = browserManager
                else { return .failed }
                switch manager.webViewRuntime.rebuildService
                    .rebuildLiveWebViewsResult(for: tab, reason: reason) {
                case .committed:
                    return .committed
                case .deferred:
                    return .deferred
                case .noLiveWindows:
                    return .noLiveWindows
                case .failed:
                    return .failed
                }
            },
            materializeVisible: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(
                    tab,
                    in: windowState
                )
            },
            windowOwnedWebView: { [weak browserManager] tab, windowID in
                browserManager?.webViewRoutingService.windowOwnedWebView(
                    for: tab,
                    in: windowID
                )
            },
            replaceLiveWebView: {
                [extensionTabWebViewReplacement]
                tab,
                windowID,
                reason,
                prepareCandidateConfiguration,
                prepareCommittedReplacement,
                validate in
                extensionTabWebViewReplacement.replace(
                    for: tab,
                    in: windowID,
                    reason: reason,
                    prepareCandidateConfiguration: prepareCandidateConfiguration,
                    prepareCommittedReplacement: prepareCommittedReplacement,
                    validate: validate
                ).committedWebView
            },
            reload: { [weak browserManager] tab, webView, window, policy in
                guard let browserManager else { return .failed }
                if let window {
                    guard browserManager.webViewRoutingService
                        .windowOwnedWebView(for: tab, in: window.id) === webView
                    else {
                        return .failed
                    }
                    return browserManager.webViewRoutingService.refreshPage(
                        for: tab,
                        in: window,
                        reason: "ExtensionTabAdapter.reload",
                        policy: policy
                    )
                }

                guard tab.webViewSession.untrackedWebView === webView else {
                    return .failed
                }
                return tab.navigationCommandOwner.refresh(
                    tab,
                    resolvedWebView: { [weak tab] in
                        tab?.webViewSession.untrackedWebView
                    },
                    reason: "ExtensionTabAdapter.reload.untracked",
                    policy: policy,
                    deliverTrackedReload: { [weak tab] intent, policy in
                        guard let tab,
                              let currentWebView =
                                tab.webViewSession.untrackedWebView
                        else {
                            return .failed
                        }
                        return tab.navigationCommandOwner.submitExactReload(
                            on: currentWebView,
                            tab: tab,
                            intent: intent,
                            policy: policy
                        )
                    }
                )
            }
        )

        let auxiliaryWindows = BrowserExtensionAuxiliaryWindowAdapter(
            sessions: browserManager.auxiliaryWindows.sessions,
            focus: browserManager.auxiliaryWindows.focus,
            teardown: browserManager.auxiliaryWindows.teardown
        )

        let presentation = BrowserExtensionWindowPresentationAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            windowQuery: windows,
            extensionWindows: browserManager.auxiliaryWindows.extensionWindows,
            urlHubAnchorView: { [weak browserManager] windowID in
                browserManager?.chromeBundle.commands
                    .urlBarHubPopoverPresenter.anchorView(for: windowID)
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
        let requestedWindows = BrowserExtensionRequestedWindowTransaction(
            commands: browserManager.windowCommands,
            restoration: browserManager.windowSessionBundle.restoreService,
            extensionPublication: browserManager.windowExtensionPublication,
            spaces: spaces,
            regularLifecycle: browserManager
                .regularTabLifecycleOwner,
            residences: browserManager.tabResidenceAuthority,
            ownership: webViewOwnershipQuery,
            registeredWindow: { [weak browserManager] windowID in
                browserManager?.windowRegistry.windows[windowID]
            },
            materialize: { [weak browserManager] tab, window in
                guard let browserManager else { return nil }
                browserManager.materializeVisibleTabWebViewIfNeeded(
                    tab,
                    in: window
                )
                return browserManager.webViewRuntime.ownershipQuery.webView(
                    for: tab.id,
                    in: window.id
                ) as? FocusableWKWebView
            },
            rollbackRegisteredWindow: { [weak browserManager] window in
                guard let registry = browserManager?.windowRegistry,
                      registry.windows[window.id] === window
                else {
                    return false
                }
                let appKitWindow = registry.appKitWindow(for: window)
                guard registry.discardRejectedRegistration(window) else {
                    return false
                }
                appKitWindow?.close()
                return registry.windows[window.id] !== window
            },
            persistWindow: { [weak browserManager] window in
                browserManager?.windowSessionPersistenceCoordinator.persist(window)
            }
        )

        self.windows = windows
        self.tabs = tabs
        self.requestedTabTargets = requestedTabTargets
        self.tabMutation = tabMutation
        self.windowActivation = windowActivation
        self.webViews = webViews
        self.auxiliaryWindows = auxiliaryWindows
        self.presentation = presentation
        self.requestedWindows = requestedWindows
    }
}
