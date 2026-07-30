//
//  AuxiliaryWindowLifecycleTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)

@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testFocusedMiniWindowAdapterDoesNotCrossContaminateBetweenExtensions()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "owner-a"
        )
        let ownerBContext = try await makeExtensionContext(
            ownerExtensionID: "owner-b"
        )
        harness.inspection.contextState.profiles.setContext(
            ownerBContext,
            extensionId: "owner-b",
            profileId: harness.profile.id
        )
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            auxiliaryInstalledExtension(id: "owner-b"),
            durability: .volatileExactRuntime
        )
        let ownerBTab = harness.browserManager
            .regularTabLifecycleOwner.createNewTab(
                url: ownerBContext.baseURL.appendingPathComponent(
                    "popup.html"
                ).absoluteString,
                in: harness.browserManager.spaceStateOwner
                    .currentSpace,
                activate: false,
                webExtensionContextOverride: ownerBContext,
                executionProfileID: harness.profile.id
            )
        defer { ownerBTab.closeTab() }

        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        defer {
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        _ = auxiliaryWindows.popups.presentExtensionExternalWebPopup(
            configuration: extensionPopupConfiguration(for: harness),
            request: URLRequest(
                url: URL(string: "https://auth-a.example/login")!
            ),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab,
            extensionOwnedSourceURL: harness.extensionContext.baseURL
                .appendingPathComponent("popup.html")
        )
        _ = auxiliaryWindows.popups.presentExtensionExternalWebPopup(
            configuration: extensionPopupConfiguration(for: harness),
            request: URLRequest(
                url: URL(string: "https://auth-b.example/login")!
            ),
            windowFeatures: WKWindowFeatures(),
            openerTab: ownerBTab,
            extensionOwnedSourceURL: ownerBContext.baseURL
                .appendingPathComponent("popup.html")
        )

        let adapterA = auxiliaryWindows.focus.focusedMiniWindowAdapter(
            forExtensionID: "owner-a"
        )
        let adapterB = auxiliaryWindows.focus.focusedMiniWindowAdapter(
            forExtensionID: "owner-b"
        )

        XCTAssertNotNil(adapterA)
        XCTAssertNotNil(adapterB)
        XCTAssertNotEqual(adapterA?.sessionId, adapterB?.sessionId)
    }

    func testPublishedAuxiliaryAdaptersPlaceExactFocusedSessionFirst()
        async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let firstWebView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness
            )
        )
        let firstSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: firstWebView)
        )
        let secondWebView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness
            )
        )
        let secondSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: secondWebView)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.closeAll(
                reason: .bulkCleanup
            )
        }
        let publications = harness.attachedRuntime.publications.windowPublications

        XCTAssertIdentical(
            publications.publishedAuxiliaryWindowAdapters(
                ownerExtensionID: ownerExtensionID,
                profileID: harness.profile.id
            ).first,
            secondSession.miniWindowAdapter
        )

        let firstReceipt = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.receipt(
                for: firstSession
            )
        )
        harness.browserManager.auxiliaryWindows.focus.focus(firstReceipt)
        XCTAssertIdentical(
            publications.publishedAuxiliaryWindowAdapters(
                ownerExtensionID: ownerExtensionID,
                profileID: harness.profile.id
            ).first,
            firstSession.miniWindowAdapter
        )
    }

    func testClosingFocusedPopupRestoresPreviousPopupForSameExtension()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")
        let firstWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://first.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        let firstSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: firstWebView)
        )
        let secondWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://second.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        let secondSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: secondWebView)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.closeAll(
                reason: .bulkCleanup
            )
        }

        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.focus
                .focusedMiniWindowAdapter(forExtensionID: "adapter-owner")?
                .sessionId,
            secondSession.id
        )

        harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
            secondWebView,
            reason: .webViewDidClose
        )

        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.focus
                .focusedMiniWindowAdapter(forExtensionID: "adapter-owner")?
                .sessionId,
            firstSession.id
        )
        XCTAssertEqual(
            (harness.extensionContext.focusedWindow
                as? ExtensionMiniWindowAdapter)?.sessionId,
            firstSession.id
        )
    }

    func testFocusedWindowForExtensionContextPrefersOwnerMiniWindowBeforeMainWindow() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        mainWindow.makeKeyAndOrderFront(nil)

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }

        mainWindow.makeKeyAndOrderFront(nil)

        let focusedWindow = harness.inspection.controller.delegateBridge.webExtensionController(
            harness.controller,
            focusedWindowFor: harness.extensionContext
        )
        let focusedMiniWindow = focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertNotNil(focusedMiniWindow)
        XCTAssertEqual(
            focusedMiniWindow?.sessionId,
            harness.attachedRuntime.requestedTabs.windowVisibility.miniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first?.sessionId
        )
    }

    func testOpenWindowsForExtensionContextOrdersOwnerMiniWindowBeforeMainWindow() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner",
            publishNormalWindow: true
        )
        let controller = harness.inspection.controller.provisioning.ensureExtensionController(
            for: harness.profile.id
        )
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView),
            "adapter-owner"
        )
        XCTAssertFalse(
            harness.inspection.normalTabs.adapters.miniWindowAdaptersSnapshot()
                .isEmpty,
            "Expected extension-owned mini-window presentation to register a mini-window adapter"
        )

        let openWindows = harness.inspection.controller.delegateBridge.webExtensionController(
            controller,
            openWindowsFor: harness.extensionContext
        )
        let ownerMiniWindowAdapter = try XCTUnwrap(
            harness.attachedRuntime.requestedTabs.windowVisibility.miniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let mainWindowAdapter = try XCTUnwrap(
            harness.attachedRuntime.publications.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                )
        )

        let firstOpenWindow = try XCTUnwrap(openWindows.first)
        XCTAssertTrue((firstOpenWindow as AnyObject) === ownerMiniWindowAdapter)
        XCTAssertTrue(
            openWindows.dropFirst().contains { window in
                (window as AnyObject) === mainWindowAdapter
            }
        )
    }

    func testFocusedMiniWindowSetFrameDoesNotMutateParentWindowFrame() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        let originalMainFrame = mainWindow.frame

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }

        let focusedWindow = try XCTUnwrap(
            harness.inspection.controller.delegateBridge.webExtensionController(
                harness.controller,
                focusedWindowFor: harness.extensionContext
            ) as? ExtensionMiniWindowAdapter
        )
        let resizedFrame = NSRect(x: 180, y: 160, width: 500, height: 620)
        var callbackError: Error?

        focusedWindow.setFrame(resizedFrame, for: harness.extensionContext) { error in
            callbackError = error
        }

        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: focusedWindow.sessionId)
        )
        XCTAssertNil(callbackError)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        XCTAssertEqual(session.window.frame, resizedFrame)
    }

    func testAuxiliaryMiniWindowFocusSurvivesMainWindowFocusNotification() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }

        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: popupWebView)
        )
        session.window.makeKeyAndOrderFront(nil)
        harness.inspection.browserPublication.events.focus(harness.windowState)

        let focusedWindow = harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertEqual(focusedWindow?.sessionId, session.id)
    }

    func testExtensionRequestedExternalTabFromMiniWindowCreatesNormalSameProfileTab() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
            harness.browserManager.spaceStateOwner.currentSpace!.id
        ]?.count ?? 0

        let sourcePopupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://popup.example/start")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        let sourceSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: sourcePopupWebView)
        )
        XCTAssertEqual(sourceSession.tab.profileId, harness.profile.id)
        XCTAssertEqual(
            sourceSession.tab.spaceId,
            harness.browserManager.spaceStateOwner.currentSpace?.id
        )

        let sourceMiniWindow = try XCTUnwrap(
            harness.attachedRuntime.requestedTabs.windowVisibility.miniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let authURL = URL(string: "https://account.example.test/login?client_id=abc")!
        var lifecycleEvents: [String] = []
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            lifecycleEvents.append("didOpen")
        }
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            lifecycleEvents.append("didClose")
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
        }

        let authTab = try harness.attachedRuntime.requestedTabs.opening.open(
            url: authURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: sourceMiniWindow,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            reason: "AuxiliaryWindowLifecycleTests"
        )

        XCTAssertTrue(harness.browserManager.auxiliaryWindows.sessions.contains(sourcePopupWebView))
        XCTAssertFalse(
            harness.browserManager.auxiliaryMiniWindowTabs
                .containsExact(authTab)
        )
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertNil(authTab.profileId)
        XCTAssertIdentical(authTab.resolveProfile(), harness.profile)
        XCTAssertEqual(authTab.spaceId, harness.browserManager.spaceStateOwner.currentSpace?.id)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
                harness.browserManager.spaceStateOwner.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertNil(harness.browserManager.auxiliaryWindows.sessions.session(for: authTab))
        XCTAssertEqual(harness.windowState.currentTabId, authTab.id)
        XCTAssertTrue(lifecycleEvents.isEmpty)

        harness.inspection.runtimeAuthorities.demand
            .recordRuntimeDemandWithoutEnabledExtensions()
        let webView = try XCTUnwrap(authTab.resolvedAssignedWebView() ?? authTab.resolvedCurrentWebView())
        harness.attachedRuntime.normalTabs.liveWebViewPreparation.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: nil,
            reason: "AuxiliaryWindowLifecycleTests.materializedExternalNormalTab"
        )
        try harness.controller.load(harness.extensionContext)
        defer {
            try? harness.controller.unload(harness.extensionContext)
        }
        XCTAssertTrue(
            harness.attachedRuntime.requestedTabs
                .createdTabRegistrar.register(
                authTab,
                reason: "AuxiliaryWindowLifecycleTests.materializedExternalNormalTab"
            )
        )
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            harness.inspection.controller.provisioning.websiteDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            harness.inspection.controller.provisioning.ensureExtensionController(for: harness.profile.id)
        )
        XCTAssertNotNil(harness.attachedRuntime.adapters.stableAdapter(for: authTab))
        XCTAssertTrue(authTab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
        XCTAssertEqual(lifecycleEvents, ["didOpen"])
    }

    func testExtensionExternalWindowCreateUsesNormalBrowserTab() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner",
            publishNormalWindow: true
        )
        let controller = harness.inspection.controller.provisioning.ensureExtensionController(
            for: harness.profile.id
        )
        let publishedMainWindow = try XCTUnwrap(
            harness.attachedRuntime.publications.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                )
        )
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[
            harness.browserManager.spaceStateOwner.currentSpace!.id
        ]?.count ?? 0
        let openedWindow = expectation(description: "extension external tab opened")
        let openedTab = expectation(description: "extension external tab published")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        var openedTabID: UUID?
        let authURL = URL(string: "https://account.example.test/login?client_id=abc")!
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            openedTabID = tabID
            openedTab.fulfill()
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
        }

        harness.attachedRuntime.requestedTabs.windowRouter.open(
            tabURLs: [authURL],
            controller: controller,
            extensionContext: harness.extensionContext,
            completion: { window, error in
                completionWindow = window
                completionError = error
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow, openedTab], timeout: 2.0)

        XCTAssertNil(completionError)
        let window = try XCTUnwrap(completionWindow as? ExtensionWindowAdapter)
        XCTAssertNotIdentical(window, publishedMainWindow)
        XCTAssertNotEqual(window.windowId, harness.windowState.id)
        let openedWindowState = try XCTUnwrap(
            harness.windowRegistry.allWindows.first {
                $0.id == window.windowId
            }
        )
        XCTAssertIdentical(
            harness.attachedRuntime.publications.windowPublications
                .publishedWindowAdapter(
                    for: openedWindowState,
                    profileID: harness.profile.id
                ),
            window
        )
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        let authTab = try XCTUnwrap(
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: try XCTUnwrap(openedTabID))
        )
        let authSpaceId = try XCTUnwrap(authTab.spaceId)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[authSpaceId]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertEqual(authTab.url, authURL)
        XCTAssertNil(authTab.profileId)
        XCTAssertIdentical(authTab.resolveProfile(), harness.profile)
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertNil(authTab.webExtensionContextOverride)
        XCTAssertNil(harness.browserManager.auxiliaryWindows.sessions.session(for: authTab))
        XCTAssertEqual(openedWindowState.currentTabId, authTab.id)
    }

    func testMaxNestedDepthBlocksSizedPopupWithoutInPlaceLoad() {
        let harness = makeHarness()
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows

        XCTAssertNil(
            auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://example.com/nested-sized")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                nestedDepth: auxiliaryWindows.nestingPolicy.maximumDepth
            ),
            "Sized and unsized popups must be blocked once nested depth reaches maximumDepth"
        )
    }

    func testUnsizedNestedPopupStillUsesConfiguredInPlacePolicy()
        async throws {
        let harness = makeHarness()
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(
            auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: nil,
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                nestedDepth: auxiliaryWindows.nestingPolicy.maximumDepth - 1
            )
        )
        defer {
            auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                webView,
                reason: .bulkCleanup
            )
        }
        let session = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let targetURL = URL(string: "about:blank#nested-unsized")!
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: targetURL,
            webView: webView
        )
        let didStartTargetLoad = expectation(
            description: "unsized popup loads in place"
        )
        let observation = webView.observe(\.url, options: [.initial, .new]) {
            _, change in
            if (change.newValue ?? nil) == targetURL {
                didStartTargetLoad.fulfill()
            }
        }

        let childWebView = session.uiDelegate.webView(
            webView,
            createWebViewWith: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        await fulfillment(of: [didStartTargetLoad], timeout: 2.0)
        withExtendedLifetime(observation) {}
    }

    func testPrivatePopupTabStaysEphemeralAndOutOfRegularPersistence() throws {
        let harness = makeHarness()
        let privateProfile = Profile.createEphemeral()
        let privateWindow = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: privateWindow)
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = privateProfile
        harness.windowRegistry.bindAppKitWindow(
            NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
            ),
            to: privateWindow
        )
        harness.windowRegistry.register(privateWindow)

        let sourceTab = harness.browserManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: URL(string: "https://private.example/source")!,
            in: privateWindow,
            profile: privateProfile
        )
        let regularTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot().values
            .flatMap(\.self)
            .count

        let popupTab = try XCTUnwrap(
            harness.browserManager.tabOpening.createPopupTab(
                from: sourceTab,
                activate: false
            )
        )

        XCTAssertTrue(popupTab.isEphemeral)
        XCTAssertTrue(popupTab.isPopupHost)
        XCTAssertNil(popupTab.spaceId)
        XCTAssertEqual(popupTab.profileId, privateProfile.id)
        XCTAssertTrue(privateWindow.ephemeralTabs.contains { $0.id == popupTab.id })
        XCTAssertEqual(privateWindow.currentTabId, sourceTab.id)
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot().values.flatMap { $0 }.count,
            regularTabCount
        )
        XCTAssertFalse(harness.browserManager.structuralPersistence.shouldPersistRegularTab(popupTab))
    }

}
