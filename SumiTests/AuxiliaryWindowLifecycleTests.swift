//
//  AuxiliaryWindowLifecycleTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import SwiftData
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
final class AuxiliaryWindowLifecycleTests: XCTestCase {
    private final class RecordingWKWebView: WKWebView {
        private(set) var loadedRequestURLs: [URL] = []

        override func load(_ request: URLRequest) -> WKNavigation? {
            if let url = request.url {
                loadedRequestURLs.append(url)
            }
            return nil
        }
    }

    private struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let sourceTab: Tab
        let windowState: BrowserWindowState
    }

    struct ExtensionHarness {
        let container: ModelContainer
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let extensionManager: ExtensionManager
        let sourceTab: Tab
        let profile: Profile
        let windowState: BrowserWindowState
        let appKitWindow: NSWindow
        let extensionContext: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    func testCloseAllForExtensionIdClosesExternalAuthPopupWithoutContextOverride() {
        let harness = makeHarness()
        let extensionURL = URL(string: "safari-web-extension://owner-extension-id/popup.html")!
        harness.sourceTab.url = extensionURL

        let popupWebView = harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab,
            extensionOwnedSourceURL: extensionURL
        )

        XCTAssertNotNil(popupWebView)
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView!),
            "owner-extension-id"
        )
        XCTAssertNil(harness.sourceTab.webExtensionContextOverride)

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "owner-extension-id")
        XCTAssertFalse(harness.browserManager.auxiliaryWindows.sessions.contains(popupWebView!))
    }

    func testCloseAllForExtensionIdPreservesUnrelatedWebPopup() {
        let harness = makeHarness()

        let popupWebView = harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://example.com/popup")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab
        )

        XCTAssertNotNil(popupWebView, "Expected generic web popup to open")
        XCTAssertNil(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView!),
            "Generic web popup must not inherit extension ownership"
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "owner-extension-id")
        XCTAssertTrue(harness.browserManager.auxiliaryWindows.sessions.contains(popupWebView!))

        harness.browserManager.auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
    }

    func testCloseAllForExtensionIdRemovesRegisteredMiniWindowAdapter()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        XCTAssertFalse(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(
            forExtensionID: "adapter-owner"
        )
        XCTAssertTrue(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
    }

    func testParentWindowFrameUnchangedAfterPresentExtensionExternalWebPopupWithExtensionHarness()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let mainWindow = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        let originalMainFrame = mainWindow.frame
        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }

        XCTAssertEqual(mainWindow.frame, originalMainFrame)
    }

    func testPrivateExtensionPopupWindowIsBlockedBeforeProfileRuntimeMaterializes() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "private-popup-owner",
            allowNormalTabRuntimeWithoutInstalledExtensions: false
        )
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .popup,
            tabURLs: [URL(string: "safari-web-extension://private-popup-owner/popup.html")!],
            shouldBePrivate: true
        ).windowConfiguration

        XCTAssertNil(harness.extensionManager.extensionController)

        let adapter = await harness.browserManager.auxiliaryWindows.extensionWindows.present(
            configuration: configuration,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            extensionManager: harness.extensionManager,
            parentWindow: harness.windowRegistry.appKitWindow(for: harness.windowState)
        )

        XCTAssertNil(adapter)
        XCTAssertTrue(harness.browserManager.tabManager.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertTrue(
            harness.extensionManager.adapterStore.miniWindowAdaptersSnapshot()
                .isEmpty
        )
        XCTAssertNil(
            harness.extensionManager.extensionController,
            "Private extension popups must not create the normal profile-backed extension controller"
        )
    }

    func testNonPrivateExtensionPopupWindowStillUsesProfileRuntime() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "normal-popup-owner")
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .popup,
            tabURLs: [URL(string: "safari-web-extension://normal-popup-owner/popup.html")!],
            shouldBePrivate: false
        ).windowConfiguration

        let maybeAdapter = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                configuration: configuration,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                extensionManager: harness.extensionManager,
                parentWindow: harness.windowRegistry.appKitWindow(for: harness.windowState)
            )
        let adapter = try XCTUnwrap(maybeAdapter)
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: adapter.sessionId)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: session.webView,
                reason: .bulkCleanup
            )
        }

        XCTAssertFalse(session.isPrivate)
        XCTAssertIdentical(
            session.webView.configuration.websiteDataStore,
            harness.extensionManager.getExtensionDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            session.webView.configuration.webExtensionController,
            harness.extensionManager.ensureExtensionController(for: harness.profile.id)
        )
    }

    func testPrivateExtensionNormalWindowIsRejectedBeforeTabCreation() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "private-window-owner",
            allowNormalTabRuntimeWithoutInstalledExtensions: false
        )
        let initialRegularTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot().values
            .flatMap(\.self)
            .filter { $0.isAuxiliaryMiniWindow == false }
            .count
        let openedWindow = expectation(description: "private extension window rejected")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .normal,
            tabURLs: [URL(string: "https://account.example.test/private")!],
            shouldBePrivate: true
        ).windowConfiguration

        harness.extensionManager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            openNewWindowUsing: configuration,
            for: harness.extensionContext
        ) { window, error in
            completionWindow = window
            completionError = error
            openedWindow.fulfill()
        }

        await fulfillment(of: [openedWindow], timeout: 2.0)

        XCTAssertNil(completionWindow)
        XCTAssertNotNil(completionError)
        XCTAssertTrue(harness.browserManager.tabManager.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot().values
                .flatMap { $0 }
                .filter { $0.isAuxiliaryMiniWindow == false }
                .count,
            initialRegularTabCount
        )
        XCTAssertNil(
            harness.extensionManager.extensionController,
            "Private extension windows must not create the normal profile-backed extension controller"
        )
    }

    func testExtensionRequestedTeardownClosesAuxiliaryMiniWindowSession()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        XCTAssertFalse(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: popupWebView,
            reason: .extensionRequestedClose
        )

        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
        XCTAssertTrue(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
    }

    func testRemoveTabAuxiliaryRoutesThroughFullTeardown() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        XCTAssertFalse(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
        let auxiliaryTab = try XCTUnwrap(
            harness.browserManager.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.values.first
        )

        harness.browserManager.tabManager.tabClosureService.removeTab(
            auxiliaryTab.id
        )

        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
        XCTAssertTrue(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertNil(
            harness.browserManager.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID[auxiliaryTab.id]
        )
    }

    func testFocusedMiniWindowAdapterDoesNotCrossContaminateBetweenExtensions()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "owner-a"
        )
        harness.extensionManager.setExtensionContext(
            try await makeExtensionContext(ownerExtensionID: "owner-b"),
            extensionId: "owner-b",
            profileId: harness.profile.id
        )

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
            extensionOwnedSourceURL: URL(
                string: "safari-web-extension://owner-a/popup.html"
            )!
        )
        _ = auxiliaryWindows.popups.presentExtensionExternalWebPopup(
            configuration: extensionPopupConfiguration(for: harness),
            request: URLRequest(
                url: URL(string: "https://auth-b.example/login")!
            ),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab,
            extensionOwnedSourceURL: URL(
                string: "safari-web-extension://owner-b/popup.html"
            )!
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
                in: harness,
                ownerExtensionID: ownerExtensionID
            )
        )
        let firstSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: firstWebView)
        )
        let secondWebView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness,
                ownerExtensionID: ownerExtensionID
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
        let publications = harness.extensionManager.windowPublications

        XCTAssertIdentical(
            publications.publishedAuxiliaryWindowAdapters(
                ownerExtensionID: ownerExtensionID,
                profileID: harness.profile.id
            ).first,
            secondSession.miniWindowAdapter
        )

        harness.browserManager.auxiliaryWindows.focus.focus(
            sessionID: firstSession.id
        )
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
        let extensionURL = URL(
            string: "safari-web-extension://adapter-owner/popup.html"
        )!
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

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: secondWebView,
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
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }

        mainWindow.makeKeyAndOrderFront(nil)

        let focusedWindow = harness.extensionManager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            focusedWindowFor: harness.extensionContext
        )
        let focusedMiniWindow = focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertNotNil(focusedMiniWindow)
        XCTAssertEqual(
            focusedMiniWindow?.sessionId,
            harness.extensionManager.windowVisibilityResolver.miniWindowAdapters(
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
        let controller = harness.extensionManager.ensureExtensionController(
            for: harness.profile.id
        )
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView),
            "adapter-owner"
        )
        XCTAssertFalse(
            harness.extensionManager.adapterStore.miniWindowAdaptersSnapshot()
                .isEmpty,
            "Expected extension-owned mini-window presentation to register a mini-window adapter"
        )

        let openWindows = harness.extensionManager.controllerDelegateBridge.webExtensionController(
            controller,
            openWindowsFor: harness.extensionContext
        )
        let ownerMiniWindowAdapter = try XCTUnwrap(
            harness.extensionManager.windowVisibilityResolver.miniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let mainWindowAdapter = try XCTUnwrap(
            harness.extensionManager.windowPublications
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
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }

        let focusedWindow = try XCTUnwrap(
            harness.extensionManager.controllerDelegateBridge.webExtensionController(
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
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }

        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: popupWebView)
        )
        session.window.makeKeyAndOrderFront(nil)
        harness.extensionManager.focusPublishedWindow(harness.windowState)

        let focusedWindow = harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertEqual(focusedWindow?.sessionId, session.id)
    }

    func testExtensionRequestedExternalTabFromMiniWindowCreatesNormalSameProfileTab() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
            harness.browserManager.tabManager.spaceStateOwner.currentSpace!.id
        ]?.count ?? 0

        let sourcePopupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://popup.example/start")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
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
            harness.browserManager.tabManager.spaceStateOwner.currentSpace?.id
        )

        let sourceMiniWindow = try XCTUnwrap(
            harness.extensionManager.windowVisibilityResolver.miniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let authURL = URL(string: "https://account.example.test/login?client_id=abc")!

        let authTab = try harness.extensionManager.requestedTabOpening.open(
            url: authURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: sourceMiniWindow,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            reason: "AuxiliaryWindowLifecycleTests"
        )

        XCTAssertTrue(harness.browserManager.auxiliaryWindows.sessions.contains(sourcePopupWebView))
        XCTAssertFalse(harness.browserManager.tabManager.transientWebKitTabLifecycleOwner.isAuxiliaryMiniWindowTab(authTab))
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertNil(authTab.profileId)
        XCTAssertIdentical(authTab.resolveProfile(), harness.profile)
        XCTAssertEqual(authTab.spaceId, harness.browserManager.tabManager.spaceStateOwner.currentSpace?.id)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
                harness.browserManager.tabManager.spaceStateOwner.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertNil(harness.browserManager.auxiliaryWindows.sessions.session(for: authTab))
        XCTAssertEqual(harness.windowState.currentTabId, authTab.id)

        harness.extensionManager.runtimeDemand
            .recordRuntimeDemandWithoutEnabledExtensions()
        let webView = try XCTUnwrap(authTab.resolvedAssignedWebView() ?? authTab.resolvedCurrentWebView())
        harness.extensionManager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: nil,
            reason: "AuxiliaryWindowLifecycleTests.materializedExternalNormalTab"
        )
        harness.extensionManager.extensionCreatedTabRegistrar.register(
            authTab,
            runtime: harness.extensionManager.runtime,
            reason: "AuxiliaryWindowLifecycleTests.materializedExternalNormalTab"
        )
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            harness.extensionManager.getExtensionDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            harness.extensionManager.ensureExtensionController(for: harness.profile.id)
        )
        XCTAssertNotNil(harness.extensionManager.adapterCatalog.stableAdapter(for: authTab))
        XCTAssertTrue(authTab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testExtensionExternalWindowCreateUsesNormalBrowserTab() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner",
            publishNormalWindow: true
        )
        let controller = harness.extensionManager.ensureExtensionController(
            for: harness.profile.id
        )
        let publishedMainWindow = try XCTUnwrap(
            harness.extensionManager.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                )
        )
        let mainWindow = try XCTUnwrap(harness.windowRegistry.appKitWindow(for: harness.windowState))
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
            harness.browserManager.tabManager.spaceStateOwner.currentSpace!.id
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

        harness.extensionManager.openExtensionWindowUsingTabURLs(
            [authURL],
            controller: controller,
            extensionContext: harness.extensionContext,
            completionHandler: { window, error in
                completionWindow = window
                completionError = error
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow, openedTab], timeout: 2.0)

        XCTAssertNil(completionError)
        let window = try XCTUnwrap(completionWindow as? ExtensionWindowAdapter)
        XCTAssertIdentical(window, publishedMainWindow)
        XCTAssertIdentical(
            harness.extensionManager.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                ),
            publishedMainWindow
        )
        XCTAssertEqual(window.windowId, harness.windowState.id)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        let authTab = try XCTUnwrap(
            harness.browserManager.tabManager.tabCollectionMembershipOwner
                .tab(for: try XCTUnwrap(openedTabID))
        )
        let authSpaceId = try XCTUnwrap(authTab.spaceId)
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[authSpaceId]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertEqual(authTab.url, authURL)
        XCTAssertNil(authTab.profileId)
        XCTAssertIdentical(authTab.resolveProfile(), harness.profile)
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertNil(authTab.webExtensionContextOverride)
        XCTAssertNil(harness.browserManager.auxiliaryWindows.sessions.session(for: authTab))
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

    func testUnsizedNestedPopupStillUsesConfiguredInPlacePolicy() {
        let harness = makeHarness()
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let permissions = AuxiliaryWindowPermissionStub()
        let delegate = AuxiliaryWindowUIDelegate(
            sessions: auxiliaryWindows.sessions,
            popups: auxiliaryWindows.popups,
            teardown: auxiliaryWindows.teardown,
            permissions: permissions,
            nestingPolicy: auxiliaryWindows.nestingPolicy,
            openerTab: harness.sourceTab,
            nestedDepth: auxiliaryWindows.nestingPolicy.maximumDepth
        )
        let recordingWebView = RecordingWKWebView()
        let targetURL = URL(string: "https://example.com/nested-unsized")!
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: targetURL,
            webView: recordingWebView
        )

        let childWebView = delegate.webView(
            recordingWebView,
            createWebViewWith: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(recordingWebView.loadedRequestURLs, [targetURL])
    }

    func testPrivatePopupTabStaysEphemeralAndOutOfRegularPersistence() throws {
        let harness = makeHarness()
        let privateProfile = Profile.createEphemeral()
        let privateWindow = BrowserWindowState()
        privateWindow.tabManager = harness.browserManager.tabManager
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

        let sourceTab = harness.browserManager.tabManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: URL(string: "https://private.example/source")!,
            in: privateWindow,
            profile: privateProfile
        )
        let regularTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot().values
            .flatMap(\.self)
            .count

        let popupTab = try XCTUnwrap(
            harness.browserManager.tabLifecycleService.opening.createPopupTab(
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
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot().values.flatMap { $0 }.count,
            regularTabCount
        )
        XCTAssertFalse(harness.browserManager.tabManager.structuralPersistence.shouldPersistRegularTab(popupTab))
    }

    private func makeHarness() -> Harness {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.sumiSettings = settings
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.bindAppKitWindow(
            NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
            ),
            to: windowState
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.selectTab(sourceTab, in: windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            sourceTab: sourceTab,
            windowState: windowState
        )
    }

    func makeExtensionHarness(
        ownerExtensionID: String,
        allowNormalTabRuntimeWithoutInstalledExtensions: Bool = true,
        publishNormalWindow: Bool = false
    ) async throws -> ExtensionHarness {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            moduleRegistry: registry
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))
        extensionManager.attach(browserManager: browserManager)
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        if allowNormalTabRuntimeWithoutInstalledExtensions {
            extensionManager.runtimeDemand
                .recordRuntimeDemandWithoutEnabledExtensions()
        }
        extensionManager.markExtensionRuntimePublicationReady()

        let space = Space(name: "Primary", profileId: profile.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        let appKitWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        appKitWindow.isReleasedWhenClosed = false
        windowRegistry.bindAppKitWindow(appKitWindow, to: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        addTeardownBlock { @MainActor in
            windowRegistry.unregister(windowState.id)
            appKitWindow.close()
        }

        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "safari-web-extension://\(ownerExtensionID)/popup.html",
            in: space,
            activate: true
        )
        sourceTab.profileId = profile.id
        browserManager.selectTab(sourceTab, in: windowState)

        let extensionContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        extensionManager.setExtensionContext(
            extensionContext,
            extensionId: ownerExtensionID,
            profileId: profile.id
        )
        let controller: WKWebExtensionController
        if publishNormalWindow {
            controller = extensionManager.ensureExtensionController(
                for: profile.id
            )
            try controller.load(extensionContext)
            addTeardownBlock {
                guard controller.extensionContexts.contains(extensionContext) else {
                    return
                }
                try controller.unload(extensionContext)
            }
            let sourceWebView = try XCTUnwrap(
                sourceTab.makeNormalTabWebView(
                    reason: "AuxiliaryWindowLifecycleTests.makeExtensionHarness"
                )
            )
            browserManager.testWebViewRuntime().trackedWebViewAdmission
                .attemptAssignment(
                    sourceWebView,
                    to: sourceTab,
                    in: windowState.id,
                    replaySemanticOperation: {
                        XCTFail("Unexpected source WebView deferral")
                    }
                )
            extensionManager.reloadRuntimePublications(
                reason: "AuxiliaryWindowLifecycleTests.makeExtensionHarness",
                profileID: profile.id
            )
            XCTAssertTrue(
                extensionManager.preparedExtensionTabs
                    .containsPreparedTab(sourceTab)
            )
            XCTAssertNotNil(
                extensionManager.adapterStore.existingWindowAdapter(
                    for: windowState.id
                )
            )
        } else {
            controller = WKWebExtensionController(
                configuration: .nonPersistent()
            )
        }

        return ExtensionHarness(
            container: container,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            extensionManager: extensionManager,
            sourceTab: sourceTab,
            profile: profile,
            windowState: windowState,
            appKitWindow: appKitWindow,
            extensionContext: extensionContext,
            controller: controller
        )
    }

    func extensionPopupConfiguration(
        for harness: ExtensionHarness
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.profile.dataStore
        configuration.webExtensionController = harness.extensionManager
            .ensureExtensionController(for: harness.profile.id)
        return configuration
    }

    func presentOwnerPopup(
        in harness: ExtensionHarness,
        ownerExtensionID: String = "adapter-owner",
        configuration: WKWebViewConfiguration? = nil
    ) -> WKWebView? {
        harness.browserManager.auxiliaryWindows.popups
            .presentExtensionExternalWebPopup(
                configuration: configuration
                    ?? extensionPopupConfiguration(for: harness),
                request: URLRequest(
                    url: URL(string: "https://auth.example/login")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(
                    string: "safari-web-extension://\(ownerExtensionID)/popup.html"
                )!
            )
    }

    func makeExtensionContext(
        ownerExtensionID: String
    ) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Auxiliary \(ownerExtensionID)",
            "version": "1.0",
            "permissions": ["tabs", "windows"],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directory.appendingPathComponent("popup.html"), options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }

    private func popupNavigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            AuxiliaryWindowNavigationFrameMock(
                isMainFrame: true,
                request: URLRequest(url: $0),
                securityOrigin: AuxiliaryWindowSecurityOriginMock.new(url: $0),
                webView: webView
            ).frameInfo
        }
        return AuxiliaryWindowNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        ).navigationAction
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@MainActor
private final class AuxiliaryWindowPermissionStub:
    AuxiliaryWindowPermissionHandling {
    func evaluatePopupPermission(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult? {
        nil
    }

    func handleFilePickerOpenPanel(
        _ request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageID: @escaping @MainActor () -> String?,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) -> Bool {
        false
    }
}

@available(macOS 15.5, *)
@MainActor
final class AuxiliaryWindowConfigurationMock: NSObject {
    @objc var windowType: WKWebExtension.WindowType
    @objc var windowState: WKWebExtension.WindowState
    @objc var frame: CGRect
    @objc var tabURLs: [URL]
    @objc var tabs: [Any]
    @objc var shouldBeFocused: Bool
    @objc var shouldBePrivate: Bool

    init(
        windowType: WKWebExtension.WindowType,
        windowState: WKWebExtension.WindowState = .normal,
        frame: CGRect = CGRect(
            x: CGFloat.nan,
            y: CGFloat.nan,
            width: CGFloat.nan,
            height: CGFloat.nan
        ),
        tabURLs: [URL] = [],
        tabs: [Any] = [],
        shouldBeFocused: Bool = false,
        shouldBePrivate: Bool
    ) {
        self.windowType = windowType
        self.windowState = windowState
        self.frame = frame
        self.tabURLs = tabURLs
        self.tabs = tabs
        self.shouldBeFocused = shouldBeFocused
        self.shouldBePrivate = shouldBePrivate
        super.init()
    }

    var windowConfiguration: WKWebExtension.WindowConfiguration {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(
                to: WKWebExtension.WindowConfiguration.self,
                capacity: 1
            ) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
private final class AuxiliaryWindowNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType
    @objc var request: URLRequest
    @objc var isUserInitiated: Bool

    init(
        sourceFrame: WKFrameInfo?,
        targetFrame: WKFrameInfo?,
        navigationType: WKNavigationType,
        request: URLRequest,
        isUserInitiated: Bool = false
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
        self.isUserInitiated = isUserInitiated
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
private final class AuxiliaryWindowNavigationFrameMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        isMainFrame: Bool,
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
@objc
private final class AuxiliaryWindowSecurityOriginMock: WKSecurityOrigin {
    private var mockedProtocol = ""
    private var mockedHost = ""
    private var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    private func setURL(_ url: URL) {
        mockedProtocol = url.scheme ?? ""
        mockedHost = url.host ?? ""
        mockedPort = url.port ?? 0
    }

    static func new(url: URL) -> AuxiliaryWindowSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! AuxiliaryWindowSecurityOriginMock
        mock.setURL(url)
        return mock
    }
}
