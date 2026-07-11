//
//  AuxiliaryWindowPublicationLifecycleTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testExtensionAuxiliaryMiniWindowNotifiesOwnerContextWindowLifecycle() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!

        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertNil(harness.extensionContext.focusedWindow)

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: extensionURL
            )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: popupWebView)
        )

        let openedMiniWindow = try XCTUnwrap(
            harness.extensionContext.openWindows.first as? ExtensionMiniWindowAdapter
        )
        XCTAssertEqual(openedMiniWindow.sessionId, session.id)
        XCTAssertEqual(
            (harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter)?.sessionId,
            session.id
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "adapter-owner")
        XCTAssertFalse(
            harness.extensionContext.openWindows.contains { window in
                (window as? ExtensionMiniWindowAdapter)?.sessionId == session.id
            }
        )
    }

    func testAuxiliaryPublicationOpensOwnerWindowBeforeOwnerTab() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var events: [String] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { sessionID in
            events.append("window")
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.session(for: sessionID),
                let windowAdapter = session.miniWindowAdapter,
                let tabAdapter = harness.extensionManager.adapterStore
                    .tabAdapters[session.tab.id] else {
                return XCTFail("Prepared auxiliary publication is missing")
            }
            XCTAssertTrue(harness.extensionContext.openWindows.contains {
                ($0 as AnyObject) === windowAdapter
            })
            XCTAssertTrue(
                (windowAdapter.tabs(for: harness.extensionContext).first
                    as AnyObject?) === tabAdapter
            )
            XCTAssertFalse(
                session.tab.extensionPageRuntimeOwner
                    .hasDidOpenTabNotification(
                        for: harness.extensionManager.runtimeSession
                            .tabOpenNotificationGeneration
                    )
            )
        }
        hooks.didOpenTab = { tabID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    $0.tab.id == tabID
                }), let windowAdapter = session.miniWindowAdapter,
                let tabAdapter = harness.extensionManager.adapterStore
                    .tabAdapters[tabID] else {
                return
            }
            events.append("tab")
            XCTAssertTrue(harness.extensionContext.openWindows.contains {
                ($0 as AnyObject) === windowAdapter
            })
            XCTAssertTrue(harness.extensionContext.openTabs.contains {
                ($0 as AnyObject) === tabAdapter
            })
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let webView = try XCTUnwrap(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: webView,
                reason: .bulkCleanup
            )
        }
        XCTAssertEqual(events, ["window", "tab"])
    }

    func testAuxiliaryPublicationRejectsContextReplacementDuringDidOpenWindow()
        async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let replacement = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var didReplace = false
        var openedTabCount = 0
        var closedTabCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { _ in
            guard didReplace == false else { return }
            didReplace = true
            harness.extensionManager.setExtensionContext(
                replacement,
                extensionId: ownerExtensionID,
                profileId: harness.profile.id
            )
        }
        hooks.didOpenTab = { tabID in
            if harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().contains(where: { $0.tab.id == tabID }) {
                openedTabCount += 1
            }
        }
        hooks.didCloseTab = { tabID in
            if harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().contains(where: { $0.tab.id == tabID }) {
                closedTabCount += 1
            }
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        XCTAssertTrue(didReplace)
        XCTAssertEqual(openedTabCount, 0)
        XCTAssertEqual(closedTabCount, 0)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(replacement.openWindows.isEmpty)
        XCTAssertTrue(replacement.openTabs.isEmpty)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
    }

    func testAuxiliaryPublicationBalancesReentrantTeardownDuringDidOpenTab()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var openedTabID: UUID?
        var closedTabIDs: [UUID] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = { tabID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    $0.tab.id == tabID
                }) else {
                return
            }
            openedTabID = tabID
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: session.webView,
                reason: .bulkCleanup
            )
        }
        hooks.didCloseTab = { closedTabIDs.append($0) }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        let tabID = try XCTUnwrap(openedTabID)
        XCTAssertEqual(closedTabIDs.filter { $0 == tabID }, [tabID])
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
    }

    func testAuxiliaryPublicationBalancesReentrantTeardownDuringFocus()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var focusedSessionID: UUID?
        var openedTabIDs: [UUID] = []
        var closedTabIDs: [UUID] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = { openedTabIDs.append($0) }
        hooks.didCloseTab = { closedTabIDs.append($0) }
        hooks.didFocusAuxiliaryWindow = { sessionID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.session(for: sessionID) else {
                return
            }
            focusedSessionID = sessionID
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: session.webView,
                reason: .bulkCleanup
            )
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        XCTAssertNotNil(focusedSessionID)
        XCTAssertEqual(openedTabIDs.count, 1)
        XCTAssertEqual(closedTabIDs, openedTabIDs)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
    }

    func testWrongDataStoreRejectsAuxiliaryPublicationWithoutCallbacks()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        var eventCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { _ in eventCount += 1 }
        hooks.didOpenTab = { _ in eventCount += 1 }
        hooks.didCloseTab = { _ in eventCount += 1 }
        hooks.didCloseAuxiliaryWindow = { _ in eventCount += 1 }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let wrongConfiguration = WKWebViewConfiguration()
        wrongConfiguration.websiteDataStore = .nonPersistent()
        wrongConfiguration.webExtensionController = harness.extensionManager
            .ensureExtensionController(for: harness.profile.id)

        XCTAssertNil(
            presentOwnerPopup(
                in: harness,
                configuration: wrongConfiguration
            )
        )
        XCTAssertEqual(eventCount, 0)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
    }

    func testGenericPopupTeardownEmitsNoExtensionTabClose() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        var closedTabCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didCloseTab = { _ in closedTabCount += 1 }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let webView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(
                    url: URL(string: "https://generic.example/popup")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab
            )
        )
        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )

        XCTAssertEqual(closedTabCount, 0)
    }

}
