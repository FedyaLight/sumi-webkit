import Foundation
import SwiftData
import WebKit
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerTests {
    private func changedPropertyRawValues(
        from values: [WKWebExtension.TabChangedProperties]
    ) -> [WKWebExtension.TabChangedProperties.RawValue] {
        values.map(\.rawValue)
    }

    func testRegisterExistingWindowStateDoesNotBackfillLiveTabs() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/live-tab",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab._webView = WKWebView()
        manager.extensionsLoaded = true

        var openNotifications: [UUID] = []
        var hooks = manager.testHooks
        hooks.didOpenTab = { tabID in
            openNotifications.append(tabID)
        }
        manager.testHooks = hooks

        manager.registerExistingWindowStateIfAttached()
        manager.registerExistingWindowStateIfAttached()

        XCTAssertTrue(openNotifications.isEmpty)
        XCTAssertFalse(tab.didNotifyOpenToExtensions)
        XCTAssertEqual(tab.lastExtensionOpenNotificationGeneration, 0)
        XCTAssertEqual(tab.extensionRuntimeEligibleGeneration, 0)

        manager.tabOpenNotificationGeneration &+= 1
        manager.registerExistingWindowStateIfAttached()

        XCTAssertTrue(openNotifications.isEmpty)
        XCTAssertEqual(tab.lastExtensionOpenNotificationGeneration, 0)
    }

    func testRegisterExistingWindowStateSkipsLiveTabOpenBeforeInitialExtensionLoadCompletes() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/live-tab",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab._webView = WKWebView()

        var openNotifications: [UUID] = []
        var hooks = manager.testHooks
        hooks.didOpenTab = { tabID in
            openNotifications.append(tabID)
        }
        manager.testHooks = hooks

        manager.registerExistingWindowStateIfAttached()

        XCTAssertTrue(openNotifications.isEmpty)
        XCTAssertFalse(tab.didNotifyOpenToExtensions)
        XCTAssertEqual(tab.lastExtensionOpenNotificationGeneration, 0)
    }

    func testNotifyTabPropertiesChangedCoalescesRepeatedURLAndLoadingSnapshots() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/start",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab._webView = WKWebView()
        manager.extensionsLoaded = true
        tab.prepareExtensionRuntimeGeneration(manager.tabOpenNotificationGeneration)
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration
        manager.notifyTabOpenedIfNeeded(tab)

        var reportedProperties: [WKWebExtension.TabChangedProperties] = []
        var hooks = manager.testHooks
        hooks.didChangeTabProperties = { _, properties in
            reportedProperties.append(properties)
        }
        manager.testHooks = hooks

        tab.loadingState = .didStartProvisionalNavigation
        manager.notifyTabPropertiesChanged(tab, properties: [.loading])

        tab.loadingState = .didCommit
        manager.notifyTabPropertiesChanged(tab, properties: [.loading])

        let committedURL = try XCTUnwrap(URL(string: "https://example.com/committed"))
        tab.url = committedURL
        tab.noteCommittedMainDocumentNavigation(to: committedURL)
        manager.notifyTabPropertiesChanged(tab, properties: [.URL, .loading])

        tab.loadingState = .didFinish
        manager.notifyTabPropertiesChanged(tab, properties: [.loading])
        manager.notifyTabPropertiesChanged(tab, properties: [.loading, .URL])

        XCTAssertEqual(
            changedPropertyRawValues(from: reportedProperties),
            [
                WKWebExtension.TabChangedProperties.loading.rawValue,
                WKWebExtension.TabChangedProperties.URL.rawValue,
                WKWebExtension.TabChangedProperties.loading.rawValue,
            ]
        )
        XCTAssertEqual(tab.extensionRuntimeLastReportedURL?.absoluteString, committedURL.absoluteString)
        XCTAssertEqual(tab.extensionRuntimeLastReportedLoadingComplete, true)
        XCTAssertEqual(tab.extensionRuntimeDocumentSequence, 1)
        XCTAssertEqual(tab.extensionRuntimeCommittedMainDocumentURL?.absoluteString, committedURL.absoluteString)
    }

    func testCommittedNavigationPromotesPreviouslyOpenTabOnFirstCommit() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/restored",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab._webView = WKWebView()
        manager.extensionsLoaded = true

        var openNotifications: [UUID] = []
        var hooks = manager.testHooks
        hooks.didOpenTab = { tabID in
            openNotifications.append(tabID)
        }
        manager.testHooks = hooks

        manager.registerTabWithExtensionRuntime(tab, reason: "restored-setup")
        XCTAssertEqual(openNotifications, [tab.id])
        XCTAssertEqual(tab.extensionRuntimeEligibleGeneration, manager.tabOpenNotificationGeneration)

        manager.markTabEligibleAfterCommittedNavigation(tab, reason: "restored-commit-1")
        XCTAssertEqual(openNotifications, [tab.id])
    }

    func testCommittedNavigationDoesNotReconcileSnapshotRedundantly() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/live-tab",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab._webView = WKWebView()
        tab.loadingState = .didFinish
        tab.name = "Live Tab"
        manager.extensionsLoaded = true

        var openNotifications: [UUID] = []
        var reportedProperties: [WKWebExtension.TabChangedProperties] = []
        var hooks = manager.testHooks
        hooks.didOpenTab = { tabID in
            openNotifications.append(tabID)
        }
        hooks.didChangeTabProperties = { _, properties in
            reportedProperties.append(properties)
        }
        manager.testHooks = hooks

        manager.registerTabWithExtensionRuntime(tab, reason: "unit-test-setup")
        XCTAssertEqual(openNotifications, [tab.id])

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "unit-test"
        )
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "unit-test"
        )

        XCTAssertEqual(openNotifications, [tab.id])
        XCTAssertEqual(reportedProperties.count, 0,
            "markTabEligibleAfterCommittedNavigation should not fire redundant property notifications; the navigation delegate handles those")

        manager.tabOpenNotificationGeneration &+= 1
        manager.registerTabWithExtensionRuntime(tab, reason: "unit-test-generation-bump-setup")
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "unit-test-generation-bump"
        )

        XCTAssertEqual(openNotifications, [tab.id, tab.id])
        XCTAssertEqual(reportedProperties.count, 0)
    }

    func testWindowAdapterHidesTabsUntilReloadOrCommittedNavigation() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "No Backfill Adapter Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        let extensionContext = try await makeExtensionContext(at: extensionRoot)

        let oldTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/already-open",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        oldTab._webView = WKWebView()

        let eligibleTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/reloaded",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        eligibleTab._webView = WKWebView()

        activeWindow.currentSpaceId = oldTab.spaceId ?? eligibleTab.spaceId
        activeWindow.currentTabId = oldTab.id
        if let currentSpaceId = activeWindow.currentSpaceId {
            activeWindow.activeTabForSpace[currentSpaceId] = oldTab.id
        }
        manager.extensionsLoaded = true

        let windowAdapter = try XCTUnwrap(manager.windowAdapter(for: activeWindow.id))
        XCTAssertNil(windowAdapter.activeTab(for: extensionContext))
        XCTAssertTrue(windowAdapter.tabs(for: extensionContext).isEmpty)

        manager.registerTabWithExtensionRuntime(eligibleTab, reason: "unit-test-setup")
        manager.markTabEligibleAfterCommittedNavigation(
            eligibleTab,
            reason: "unit-test-reload"
        )

        let visibleTabs = windowAdapter.tabs(for: extensionContext)
        XCTAssertEqual(visibleTabs.count, 1)
        XCTAssertEqual((visibleTabs.first as? ExtensionTabAdapter)?.tabId, eligibleTab.id)

        activeWindow.currentTabId = eligibleTab.id
        if let currentSpaceId = activeWindow.currentSpaceId {
            activeWindow.activeTabForSpace[currentSpaceId] = eligibleTab.id
        }

        XCTAssertEqual(
            (windowAdapter.activeTab(for: extensionContext) as? ExtensionTabAdapter)?.tabId,
            eligibleTab.id
        )
    }

    /// After a generation bump, WebKit expects the focused window's active tab to stay in sync with
    /// `tabs(for:)`; resync re-binds every open tab so the current tab is not left ineligible while
    /// background tabs are eligible (which previously produced `tabsForWebExtensionContext` warnings).
    func testResyncAfterGenerationBumpReconcilesCurrentTabWithTabsList() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Generation Resync Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        let extensionContext = try await makeExtensionContext(at: extensionRoot)

        let currentTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/current",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        currentTab._webView = WKWebView()

        let backgroundTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/background",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        backgroundTab._webView = WKWebView()

        activeWindow.currentSpaceId = currentTab.spaceId ?? backgroundTab.spaceId
        activeWindow.currentTabId = currentTab.id
        if let currentSpaceId = activeWindow.currentSpaceId {
            activeWindow.activeTabForSpace[currentSpaceId] = currentTab.id
        }
        manager.extensionsLoaded = true

        let windowAdapter = try XCTUnwrap(manager.windowAdapter(for: activeWindow.id))

        manager.registerTabWithExtensionRuntime(currentTab, reason: "unit-test-setup-current")
        manager.registerTabWithExtensionRuntime(backgroundTab, reason: "unit-test-setup-background")
        manager.markTabEligibleAfterCommittedNavigation(
            currentTab,
            reason: "unit-test-setup-current"
        )
        manager.markTabEligibleAfterCommittedNavigation(
            backgroundTab,
            reason: "unit-test-setup-background"
        )

        XCTAssertEqual(
            (windowAdapter.activeTab(for: extensionContext) as? ExtensionTabAdapter)?.tabId,
            currentTab.id
        )
        XCTAssertEqual(windowAdapter.tabs(for: extensionContext).count, 2)

        manager.tabOpenNotificationGeneration &+= 1
        manager.registerTabWithExtensionRuntime(
            backgroundTab,
            reason: "unit-test-partial-rebind"
        )

        XCTAssertNil(
            windowAdapter.activeTab(for: extensionContext),
            "Current tab should not be exposed while it is still on the previous extension-runtime generation"
        )
        XCTAssertEqual(windowAdapter.tabs(for: extensionContext).count, 1)
        XCTAssertEqual(
            (windowAdapter.tabs(for: extensionContext).first as? ExtensionTabAdapter)?.tabId,
            backgroundTab.id
        )

        manager.resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(reason: "unit-test-resync")

        XCTAssertEqual(
            (windowAdapter.activeTab(for: extensionContext) as? ExtensionTabAdapter)?.tabId,
            currentTab.id
        )
        let tabIdsAfterResync = Set(
            windowAdapter.tabs(for: extensionContext).compactMap { ($0 as? ExtensionTabAdapter)?.tabId }
        )
        XCTAssertEqual(tabIdsAfterResync, [currentTab.id, backgroundTab.id])
    }

    func testTabAdapterRefusesWebViewAndMutationsUntilReloadOrCommittedNavigation() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "No Backfill Tab Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        let extensionContext = try await makeExtensionContext(at: extensionRoot)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/already-open",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.name = "Already Open"
        tab._webView = WKWebView()
        activeWindow.currentSpaceId = tab.spaceId
        activeWindow.currentTabId = tab.id
        if let currentSpaceId = activeWindow.currentSpaceId {
            activeWindow.activeTabForSpace[currentSpaceId] = tab.id
        }
        manager.extensionsLoaded = true

        let tabAdapter = try XCTUnwrap(manager.stableAdapter(for: tab))
        XCTAssertNil(tabAdapter.url(for: extensionContext))
        XCTAssertNil(tabAdapter.title(for: extensionContext))
        XCTAssertNil(tabAdapter.webView(for: extensionContext))
        XCTAssertNil(tabAdapter.window(for: extensionContext))

        var reloadError: Error?
        tabAdapter.reload(fromOrigin: false, for: extensionContext) { error in
            reloadError = error
        }
        XCTAssertNotNil(reloadError)

        var loadURLError: Error?
        tabAdapter.loadURL(URL(string: "https://example.com/should-not-load")!, for: extensionContext) { error in
            loadURLError = error
        }
        XCTAssertNotNil(loadURLError)
        XCTAssertEqual(tab.url.absoluteString, "https://example.com/already-open")

        manager.registerTabWithExtensionRuntime(tab, reason: "unit-test-setup")
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "unit-test-reload"
        )

        XCTAssertEqual(tabAdapter.url(for: extensionContext)?.absoluteString, tab.url.absoluteString)
        XCTAssertEqual(tabAdapter.title(for: extensionContext), "Already Open")
        XCTAssertNotNil(tabAdapter.webView(for: extensionContext))
        XCTAssertNotNil(tabAdapter.window(for: extensionContext))
    }

    func testOAuthExtensionWindowRouteUsesActiveWindowTabInsteadOfCreatingWindow() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentSpaceId = browserManager.tabManager.currentSpace?.id
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let controller = try requireRuntimeController(
            for: manager,
            reason: .extensionAction
        )
        let oauthURL = try XCTUnwrap(
            URL(
                string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=test&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback&response_type=code"
            )
        )

        var createWindowCalls = 0
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: Error?

        manager.openExtensionWindowUsingTabURLs(
            [oauthURL],
            controller: controller,
            createWindow: {
                createWindowCalls += 1
            },
            awaitWindowRegistration: { _ in nil }
        ) { window, error in
            completionWindow = window
            completionError = error
        }

        XCTAssertEqual(createWindowCalls, 0)
        XCTAssertNil(completionError)
        XCTAssertNotNil(completionWindow)
        XCTAssertEqual(windowRegistry.windows.count, 1)

        let openedTab = try XCTUnwrap(browserManager.tabManager.allTabs().last)
        XCTAssertEqual(openedTab.url.absoluteString, oauthURL.absoluteString)
        XCTAssertEqual(activeWindow.currentTabId, openedTab.id)
    }

    func testRegularExtensionWindowRouteStillCreatesNewSumiWindow() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentSpaceId = browserManager.tabManager.currentSpace?.id
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let controller = try requireRuntimeController(
            for: manager,
            reason: .extensionAction
        )
        let regularURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let createdWindow = BrowserWindowState()
        createdWindow.tabManager = browserManager.tabManager
        createdWindow.currentSpaceId = browserManager.tabManager.currentSpace?.id
        createdWindow.currentProfileId = browserManager.currentProfile?.id

        var createWindowCalls = 0
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: Error?

        manager.openExtensionWindowUsingTabURLs(
            [regularURL],
            controller: controller,
            createWindow: {
                createWindowCalls += 1
                windowRegistry.register(createdWindow)
            },
            awaitWindowRegistration: { existingWindowIDs in
                await windowRegistry.awaitNextRegisteredWindow(excluding: existingWindowIDs)
            }
        ) { window, error in
            completionWindow = window
            completionError = error
        }

        try await waitUntil(timeout: 2) {
            completionWindow != nil || completionError != nil
        }

        XCTAssertEqual(createWindowCalls, 1)
        XCTAssertNil(completionError)
        XCTAssertNotNil(completionWindow)
        XCTAssertEqual(windowRegistry.windows.count, 2)

        let openedTab = try XCTUnwrap(browserManager.currentTab(for: createdWindow))
        XCTAssertEqual(openedTab.url.absoluteString, regularURL.absoluteString)
        XCTAssertEqual(createdWindow.currentTabId, openedTab.id)
    }

    func testExtensionTabsCreateBrowserStartUsesSingleCanonicalTabRouteDuringInstall() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let activeWindow = BrowserWindowState()
        activeWindow.tabManager = browserManager.tabManager
        activeWindow.currentSpaceId = browserManager.tabManager.currentSpace?.id
        activeWindow.currentProfileId = browserManager.currentProfile?.id
        windowRegistry.register(activeWindow)
        windowRegistry.setActive(activeWindow)
        manager.debugAttachBrowserManager(browserManager)
        defer { cleanupBrowserWindowTestRuntime(browserManager, windowRegistry: windowRegistry) }

        let controller = try requireRuntimeController(
            for: manager,
            reason: .install
        )
        let browserStartURL = try XCTUnwrap(URL(string: "https://bitwarden.com/browser-start/"))
        manager.extensionsLoaded = false

        let openedTab = try manager.openExtensionRequestedTab(
            url: browserStartURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: nil,
            controller: controller,
            reason: "unit-test-bitwarden-onInstalled"
        )

        let allTabs = browserManager.tabManager.allTabs()
        XCTAssertEqual(allTabs.count, 1)
        XCTAssertEqual(allTabs.first?.id, openedTab.id)
        XCTAssertEqual(openedTab.url.absoluteString, browserStartURL.absoluteString)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertEqual(activeWindow.currentTabId, openedTab.id)
        XCTAssertTrue(manager.isTabEligibleForCurrentExtensionRuntime(openedTab))
        XCTAssertTrue(openedTab.didNotifyOpenToExtensions)
        XCTAssertEqual(
            openedTab.lastExtensionOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )

        XCTAssertTrue(
            Tab.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: URL(string: "webkit-extension://bitwarden/background.html"),
                requestURL: browserStartURL
            )
        )
        XCTAssertTrue(manager.consumeRecentlyOpenedExtensionTabRequest(for: browserStartURL))
        XCTAssertFalse(manager.consumeRecentlyOpenedExtensionTabRequest(for: browserStartURL))
        XCTAssertFalse(allTabs.contains { $0.isPopupHost || $0.url.absoluteString == "about:blank" })
    }

    func testDisableThenUninstallTearsDownRuntimeArtifacts() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Cleanup Fixture",
                "version": "1.0",
                "externally_connectable": [
                    "matches": ["https://accounts.example.com/*"]
                ],
            ]
        )
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json")
        )
        let record = makeInstalledExtensionRecord(
            id: "cleanup.extension",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )
        container.mainContext.insert(ExtensionEntity(record: record))
        try container.mainContext.save()

        let storageDirectory = try makeWebExtensionStorageDirectory(
            for: manager,
            extensionId: record.id
        )
        let localStorageURL = storageDirectory.appendingPathComponent("LocalStorage.db")
        try Data().write(to: localStorageURL)

        var cleanedWebExtensionDataIDs: [String] = []
        var hooks = manager.testHooks
        hooks.webExtensionDataCleanup = { extensionId in
            cleanedWebExtensionDataIDs.append(extensionId)
            try? FileManager.default.removeItem(at: localStorageURL)
            return true
        }
        manager.testHooks = hooks

        manager.debugReplaceInstalledExtensions([record])
        manager.debugSetLoadedManifest(record.manifest, for: record.id)
        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )
        manager.debugInsertRuntimeArtifacts(for: record.id)

        var snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertEqual(snapshot.installedPageBridgeIDs, [record.id])
        XCTAssertEqual(snapshot.actionAnchorIDs, [record.id])
        XCTAssertEqual(snapshot.optionWindowIDs, [record.id])
        XCTAssertEqual(snapshot.nativeMessageExtensionIDs, [record.id])

        try await manager.disableExtension(record.id)

        snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertTrue(snapshot.loadedManifestIDs.isEmpty)
        XCTAssertTrue(snapshot.installedPageBridgeIDs.isEmpty)
        XCTAssertTrue(snapshot.actionAnchorIDs.isEmpty)
        XCTAssertTrue(snapshot.optionWindowIDs.isEmpty)
        XCTAssertTrue(snapshot.nativeMessageExtensionIDs.isEmpty)
        XCTAssertFalse(manager.installedExtensions.contains(where: { $0.id == record.id && $0.isEnabled }))
        XCTAssertTrue(cleanedWebExtensionDataIDs.isEmpty)

        try await manager.uninstallExtension(record.id)

        XCTAssertEqual(cleanedWebExtensionDataIDs, [record.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageDirectory.path))
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ExtensionEntity>()).isEmpty
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: extensionRoot.path))
    }

    func testSwitchProfileUpdatesControllerDataStore() throws {
        let harness = try makeExtensionRuntimeHarness()
        let initialProfile = Profile(name: "Initial")
        let manager = makeExtensionManager(in: harness, initialProfile: initialProfile)
        let nextProfile = Profile(name: "Next")
        manager.switchProfile(nextProfile)

        XCTAssertEqual(manager.debugCurrentProfileId, nextProfile.id)
    }

    func testSwitchProfilePreservesLoadedExtensionsAndReconcilesPageBridges() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Profile Switch Fixture",
                "version": "1.0",
                "externally_connectable": [
                    "matches": ["https://accounts.example.com/*"]
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json")
        )
        let record = makeInstalledExtensionRecord(
            id: "profile.switch.fixture",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )
        container.mainContext.insert(ExtensionEntity(record: record))
        try container.mainContext.save()

        let initialProfile = Profile(name: "Initial")
        let manager = makeExtensionManager(in: harness, initialProfile: initialProfile)

        _ = try await requireRuntimeReadyController(
            for: manager,
            reason: .refresh,
            allowWithoutEnabledExtensions: false
        )

        let controllerBeforeSwitch = manager.nativeController
        let nextProfile = Profile(name: "Next")
        manager.switchProfile(nextProfile)

        try await waitUntil(timeout: 5) {
            manager.extensionsLoaded && manager.loadedContextIDs == [record.id]
        }

        XCTAssertTrue(
            manager.nativeController === controllerBeforeSwitch
        )
        XCTAssertEqual(manager.debugCurrentProfileId, nextProfile.id)
        XCTAssertNotNil(manager.getExtensionContext(for: record.id))
        XCTAssertEqual(
            manager.debugRuntimeStateSnapshot.installedPageBridgeIDs,
            [record.id]
        )
    }

    func testExtensionOriginatedPopupNavigationDetectionRecognizesExtensionSchemes() {
        XCTAssertTrue(
            Tab.isExtensionOriginatedPopupNavigation(
                sourceURL: URL(string: "webkit-extension://example/source.html"),
                requestURL: URL(string: "https://example.com")
            )
        )
        XCTAssertTrue(
            Tab.isExtensionOriginatedPopupNavigation(
                sourceURL: URL(string: "https://example.com"),
                requestURL: URL(string: "safari-web-extension://example/request.html")
            )
        )
    }

    func testExtensionOriginatedPopupNavigationDetectionIgnoresRegularSites() {
        XCTAssertFalse(
            Tab.isExtensionOriginatedPopupNavigation(
                sourceURL: URL(string: "https://example.com"),
                requestURL: URL(string: "https://example.org")
            )
        )
    }
}
