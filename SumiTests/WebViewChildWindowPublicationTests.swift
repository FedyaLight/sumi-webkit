import AppKit
import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
extension WebViewPresentationRoutingTests {
    func testWebKitChildWindowPublishesExactTrackedChildBeforeRegistration()
        throws {
        var existingWindowIDs: Set<UUID> = []
        var selectedAtRegistration: UUID?
        var trackedAtRegistration: WKWebView?
        let harness = try makeRegularHarness { browserManager, windowRegistry in
            existingWindowIDs = Set(windowRegistry.windows.keys)
            let restoration = browserManager.windowSessionBundle.restoration
            installWindowRegistryTestEventSink(
                on: windowRegistry,
                prepareWindowRegistration: { [weak restoration] window in
                    if existingWindowIDs.contains(window.id) == false,
                       let tabID = window.currentTabId {
                        selectedAtRegistration = tabID
                        trackedAtRegistration = browserManager
                            .testWebViewRuntime().ownershipQuery.webView(
                                for: tabID,
                                in: window.id
                            )
                    }
                    restoration?.prepareRegistration(window)
                },
                publishWindowRegistration: { [weak restoration] window in
                    restoration?.commitRegistration(window)
                }
            )
        }
        defer { closePublishedShells(in: harness.windowRegistry) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.sourceProfile.dataStore
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__sumiExactChild = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let targetURL = try XCTUnwrap(
            URL(string: "https://target.example/webkit-child")
        )

        let childWebView = harness.sourceTab.navigationRuntime
            .webKitChildWindowOpening?.open(
                configuration: configuration,
                requestURL: targetURL,
                from: harness.sourceWebView,
                activate: false,
                isExtensionOriginated: false
            )

        let exactChild = try XCTUnwrap(childWebView)
        let targetWindow = try XCTUnwrap(
            harness.windowRegistry.allWindows.first {
                existingWindowIDs.contains($0.id) == false
            }
        )
        let targetShell = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: targetWindow)
        )
        let targetTabID = try XCTUnwrap(targetWindow.currentTabId)
        let targetTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner
                .tab(for: targetTabID)
        )
        XCTAssertEqual(selectedAtRegistration, targetTabID)
        XCTAssertIdentical(trackedAtRegistration, exactChild)
        XCTAssertIdentical(
            harness.browserManager.testWebViewRuntime().ownershipQuery.webView(
                for: targetTabID,
                in: targetWindow.id
            ),
            exactChild
        )
        XCTAssertIdentical(
            exactChild.configuration.websiteDataStore,
            harness.sourceProfile.dataStore
        )
        XCTAssertEqual(targetTab.profileId, harness.sourceProfile.id)
        XCTAssertEqual(targetTab.spaceId, harness.sourceSpace.id)
        XCTAssertEqual(
            targetWindow.webKitChildWindowIdentity,
            WebKitChildWindowIdentity(initialTabID: targetTabID)
        )
        XCTAssertNil(targetTab.webViewConfigurationOverride)
        XCTAssertTrue(
            exactChild.configuration.userContentController.userScripts
                .map(\.source)
                .contains("window.__sumiExactChild = true;")
        )
        XCTAssertEqual(
            harness.windowRegistry.activeWindowId,
            harness.sourceWindow.id,
            "A background WebKit child window must not steal activation."
        )

        let shellClosed = expectation(
            description: "The dedicated WebKit child shell closes."
        )
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: targetShell,
            queue: .main
        ) { _ in
            shellClosed.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        XCTAssertTrue(
            harness.browserManager.webViewCloseRouter
                .handleNormalWebViewDidClose(exactChild)
        )
        wait(for: [shellClosed], timeout: 0.2)
        XCTAssertNil(targetWindow.webKitChildWindowIdentity)
        XCTAssertNil(
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: targetTabID),
            "Closing the sole physical residence must remove the script-created Tab from the durable graph."
        )
        XCTAssertNil(
            harness.browserManager.testWebViewRuntime().ownershipQuery.webView(
                for: targetTabID,
                in: targetWindow.id
            )
        )
        XCTAssertFalse(
            targetShell.isVisible,
            "A still-dedicated script-created shell must close."
        )
    }

    func testWebKitChildWindowRejectsMismatchedDataStoreWithoutMutation()
        throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        let windowIDs = Set(harness.windowRegistry.windows.keys)
        let tabIDs = Set(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().map(\.id)
        )
        let mismatched = WKWebViewConfiguration()
        mismatched.websiteDataStore = .nonPersistent()

        let childWebView = harness.sourceTab.navigationRuntime
            .webKitChildWindowOpening?.open(
                configuration: mismatched,
                requestURL: URL(
                    string: "https://target.example/rejected"
                ),
                from: harness.sourceWebView,
                activate: true,
                isExtensionOriginated: false
            )

        XCTAssertNil(childWebView)
        XCTAssertEqual(Set(harness.windowRegistry.windows.keys), windowIDs)
        XCTAssertEqual(
            Set(
                harness.browserManager.tabStateStore.regularTabs
                    .allTabsSnapshot()
                    .map(\.id)
            ),
            tabIDs
        )
    }

    func testExtensionWebKitChildWindowPublishesRegistryThenWindowThenExactTab()
        throws {
        let events = ChildWindowPublicationEvents()
        var capturedProbe: ChildWindowExtensionPublicationProbe?
        var capturedPublication: WindowExtensionPublicationTransaction?
        let harness = try makeRegularHarness { browserManager, windowRegistry in
            let probe = ChildWindowExtensionPublicationProbe(
                registry: windowRegistry,
                events: events,
                preparation: .prepared
            )
            let publication = WindowExtensionPublicationTransaction(
                preparation: probe,
                publication: probe
            )
            capturedProbe = probe
            capturedPublication = publication
            self.installExtensionPublication(
                publication,
                events: events,
                browserManager: browserManager,
                windowRegistry: windowRegistry
            )
        }
        defer { closePublishedShells(in: harness.windowRegistry) }
        let probe = try XCTUnwrap(capturedProbe)
        let publication = try XCTUnwrap(capturedPublication)
        let opening = makeChildWindowOpening(
            for: harness,
            extensionPublication: publication
        )
        let configuration = webViewConfiguration(
            dataStore: harness.sourceProfile.dataStore
        )

        let childWebView = opening.open(
            configuration: configuration,
            requestURL: URL(
                string: "https://target.example/extension-child-window"
            ),
            from: harness.sourceWebView,
            activate: false,
            isExtensionOriginated: true
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(
            events.values,
            ["prepare", "validate", "validate", "registry", "window", "tab"]
        )
        XCTAssertTrue(probe.windowNotificationSawPublishedWindow)
        XCTAssertTrue(events.tabPublicationSawPublishedWindow)
    }

    func testExtensionWebKitChildWindowRejectsSuppressedProjectionAndRollsBack()
        throws {
        let events = ChildWindowPublicationEvents()
        var capturedPublication: WindowExtensionPublicationTransaction?
        let harness = try makeRegularHarness { browserManager, windowRegistry in
            let probe = ChildWindowExtensionPublicationProbe(
                registry: windowRegistry,
                events: events,
                preparation: .suppressed
            )
            let publication = WindowExtensionPublicationTransaction(
                preparation: probe,
                publication: probe
            )
            capturedPublication = publication
            self.installExtensionPublication(
                publication,
                events: events,
                browserManager: browserManager,
                windowRegistry: windowRegistry
            )
        }
        defer { closePublishedShells(in: harness.windowRegistry) }
        let sourceShell = bindSourceShell(in: harness)
        let initialWindowIDs = Set(harness.windowRegistry.windows.keys)
        let initialTabIDs = regularTabIDs(in: harness)
        let publication = try XCTUnwrap(capturedPublication)
        let opening = makeChildWindowOpening(
            for: harness,
            extensionPublication: publication
        )

        let childWebView = opening.open(
            configuration: webViewConfiguration(
                dataStore: harness.sourceProfile.dataStore
            ),
            requestURL: URL(
                string: "https://target.example/suppressed-extension-child"
            ),
            from: harness.sourceWebView,
            activate: true,
            isExtensionOriginated: true
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(events.values, ["prepare"])
        XCTAssertEqual(
            Set(harness.windowRegistry.windows.keys),
            initialWindowIDs
        )
        XCTAssertEqual(regularTabIDs(in: harness), initialTabIDs)
        withExtendedLifetime(sourceShell) {}
    }

    func testOrdinaryWebKitChildWindowAllowsSuppressedExtensionProjection()
        throws {
        let events = ChildWindowPublicationEvents()
        var capturedProbe: ChildWindowExtensionPublicationProbe?
        var capturedPublication: WindowExtensionPublicationTransaction?
        let harness = try makeRegularHarness { browserManager, windowRegistry in
            let probe = ChildWindowExtensionPublicationProbe(
                registry: windowRegistry,
                events: events,
                preparation: .suppressed
            )
            let publication = WindowExtensionPublicationTransaction(
                preparation: probe,
                publication: probe
            )
            capturedProbe = probe
            capturedPublication = publication
            self.installExtensionPublication(
                publication,
                events: events,
                browserManager: browserManager,
                windowRegistry: windowRegistry
            )
        }
        defer { closePublishedShells(in: harness.windowRegistry) }
        let initialWindowIDs = Set(harness.windowRegistry.windows.keys)
        let probe = try XCTUnwrap(capturedProbe)
        let publication = try XCTUnwrap(capturedPublication)
        let opening = makeChildWindowOpening(
            for: harness,
            extensionPublication: publication
        )

        let childWebView = opening.open(
            configuration: webViewConfiguration(
                dataStore: harness.sourceProfile.dataStore
            ),
            requestURL: URL(
                string: "https://target.example/suppressed-ordinary-child"
            ),
            from: harness.sourceWebView,
            activate: false,
            isExtensionOriginated: false
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(events.values, ["prepare", "registry"])
        XCTAssertEqual(
            harness.windowRegistry.windows.keys.filter {
                initialWindowIDs.contains($0) == false
            }.count,
            1
        )
        XCTAssertFalse(probe.windowNotificationSawPublishedWindow)
        XCTAssertFalse(events.tabPublicationSawPublishedWindow)
    }

    func testPrivateWebKitChildWindowSharesPartitionUntilLastWindowCloses()
        async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: windowRegistry)
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        defer { closePublishedShells(in: windowRegistry) }

        let sourceWindow = BrowserWindowState()
        let sourceProfile = browserManager.profileManager.createEphemeralProfile(
            for: sourceWindow.id
        )
        let sourceSpace = Space(
            name: "Private Source",
            profileId: sourceProfile.id
        )
        sourceSpace.isEphemeral = true
        sourceWindow.isIncognito = true
        sourceWindow.ephemeralProfile = sourceProfile
        sourceWindow.replaceEphemeralSpaces([sourceSpace])
        sourceWindow.currentProfileId = sourceProfile.id
        sourceWindow.currentSpaceId = sourceSpace.id
        browserManager.tabResidenceAuthority.establishResidenceSession(on: sourceWindow)
        windowRegistry.register(sourceWindow)
        windowRegistry.setActive(sourceWindow)
        installRegistrationRestoration(
            from: browserManager,
            on: windowRegistry
        )

        let sourceTab = browserManager.ephemeralLifecycleOwner
            .createEphemeralTab(
                url: try XCTUnwrap(
                    URL(string: "https://private-source.example")
                ),
                in: sourceWindow,
                profile: sourceProfile
            )
        let sourceConfiguration = WKWebViewConfiguration()
        sourceConfiguration.websiteDataStore = sourceProfile.dataStore
        let sourceWebView = FocusableWKWebView(
            frame: .zero,
            configuration: sourceConfiguration
        )
        sourceWebView.owningTab = sourceTab
        browserManager.testWebViewRuntime().trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                sourceWebView,
                for: sourceTab,
                in: sourceWindow.id
            )
        let existingWindowIDs = Set(windowRegistry.windows.keys)
        let childConfiguration = WKWebViewConfiguration()
        childConfiguration.websiteDataStore = sourceProfile.dataStore

        let childWebView = sourceTab.navigationRuntime
            .webKitChildWindowOpening?.open(
                configuration: childConfiguration,
                requestURL: nil,
                from: sourceWebView,
                activate: true,
                isExtensionOriginated: false
            )

        let exactChild = try XCTUnwrap(childWebView)
        let targetWindow = try XCTUnwrap(
            windowRegistry.allWindows.first {
                existingWindowIDs.contains($0.id) == false
            }
        )
        let targetTab = try XCTUnwrap(targetWindow.ephemeralTabs.first)
        XCTAssertIdentical(targetWindow.ephemeralProfile, sourceProfile)
        XCTAssertEqual(targetWindow.currentProfileId, sourceProfile.id)
        XCTAssertEqual(targetTab.profileId, sourceProfile.id)
        XCTAssertIdentical(
            exactChild.configuration.websiteDataStore,
            sourceProfile.dataStore
        )

        await browserManager.windowCommands.closeIncognitoWindow(sourceWindow)
        XCTAssertIdentical(
            browserManager.profileManager.ephemeralProfile(
                withID: sourceProfile.id
            ),
            sourceProfile
        )
        XCTAssertIdentical(targetWindow.ephemeralProfile, sourceProfile)

        await browserManager.windowCommands.closeIncognitoWindow(targetWindow)
        XCTAssertNil(
            browserManager.profileManager.ephemeralProfile(
                withID: sourceProfile.id
            )
        )
    }

}
