import AppKit
import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewPresentationRoutingTests: XCTestCase {
    func testPageMenuCommandsResolveExactCloneWindowAndFailClosed() throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        harness.settings.themeUseSystemColors = true

        let secondWindow = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        secondWindow.currentProfileId = harness.sourceProfile.id
        secondWindow.currentSpaceId = harness.sourceSpace.id
        secondWindow.currentTabId = harness.sourceTab.id
        harness.windowRegistry.register(secondWindow)

        let firstShell = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        firstShell.appearance = NSAppearance(named: .aqua)
        harness.windowRegistry.bindAppKitWindow(
            firstShell,
            to: harness.sourceWindow
        )
        let secondShell = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        secondShell.appearance = NSAppearance(named: .darkAqua)
        harness.windowRegistry.bindAppKitWindow(secondShell, to: secondWindow)

        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: webViewConfiguration(
                dataStore: harness.sourceProfile.dataStore
            )
        )
        secondWebView.owningTab = harness.sourceTab
        harness.browserManager.testWebViewRuntime().trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                secondWebView,
                for: harness.sourceTab,
                in: secondWindow.id
            )

        let firstAppearance = harness.sourceTab.webPageMenuCommands.appearance(
            for: harness.sourceWebView,
            fallback: nil
        )
        let secondAppearance = harness.sourceTab.webPageMenuCommands.appearance(
            for: secondWebView,
            fallback: nil
        )
        XCTAssertEqual(
            firstAppearance?.bestMatch(from: [.aqua, .darkAqua]),
            .aqua
        )
        XCTAssertEqual(
            secondAppearance?.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua
        )

        XCTAssertTrue(
            harness.sourceTab.webPageMenuCommands.requestBookmarkEditor(
                from: secondWebView
            )
        )
        XCTAssertEqual(
            harness.browserManager.bookmarkEditorPresentationState.request?.windowID,
            secondWindow.id
        )
        XCTAssertEqual(
            harness.browserManager.bookmarkEditorPresentationState.request?.tabID,
            harness.sourceTab.id
        )

        let untracked = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        untracked.owningTab = harness.sourceTab
        XCTAssertFalse(
            harness.sourceTab.webPageMenuCommands.requestBookmarkEditor(
                from: untracked
            )
        )

        let mismatchedTab = Tab(loadsCachedFaviconOnInit: false)
        let mismatched = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        mismatched.owningTab = mismatchedTab
        XCTAssertEqual(
            harness.browserManager.testWebViewRuntime().trackedWebViewAdmission
                .registerAuxiliaryTrackedWebView(
                    mismatched,
                    for: harness.sourceTab,
                    in: secondWindow.id
                ),
            .rejected(.physicalTabIdentityMismatch)
        )
        XCTAssertFalse(
            harness.sourceTab.webPageMenuCommands.requestBookmarkEditor(
                from: mismatched
            )
        )
    }

    func testForegroundAndBackgroundLinksStayInSourceTabSpace() throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }

        let backgroundURL = try XCTUnwrap(
            URL(string: "https://target.example/background")
        )
        XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
            backgroundURL,
            from: harness.sourceWebView,
            disposition: .newTab(selected: false)
        ))

        let backgroundTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.sourceSpace)
                .first { $0.url == backgroundURL }
        )
        XCTAssertEqual(backgroundTab.spaceId, harness.sourceSpace.id)
        XCTAssertEqual(harness.sourceWindow.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(harness.sourceWindow.currentSpaceId, harness.sourceSpace.id)

        let foregroundURL = try XCTUnwrap(
            URL(string: "https://target.example/foreground")
        )
        XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
            foregroundURL,
            from: harness.sourceWebView,
            disposition: .newTab(selected: true)
        ))

        let foregroundTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.sourceSpace)
                .first { $0.url == foregroundURL }
        )
        XCTAssertEqual(foregroundTab.spaceId, harness.sourceSpace.id)
        XCTAssertEqual(harness.sourceWindow.currentTabId, foregroundTab.id)
        XCTAssertEqual(harness.sourceWindow.currentSpaceId, harness.sourceSpace.id)
        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.unrelatedSpace)
                .allSatisfy { $0.url != backgroundURL && $0.url != foregroundURL },
            "Link routing must not fall back to the process-global current space."
        )
    }

    func testPhysicalWebPopupRejectsSourceWithoutPublishedShellBeforeMutation()
        throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        XCTAssertNil(
            harness.windowRegistry.appKitWindow(for: harness.sourceWindow)
        )
        let configuration = webViewConfiguration(
            dataStore: harness.sourceProfile.dataStore
        )
        let existingAuxiliaryTabIDs = Set(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .filter { $0.isAuxiliaryMiniWindow }
                .map(\.id)
        )

        let popupWebView = harness.sourceTab.navigationRuntime
            .physicalWebPopupOpening?.open(
                configuration: configuration,
                request: URLRequest(
                    url: try XCTUnwrap(
                        URL(string: "https://target.example/popup")
                    )
                ),
                windowFeatures: WKWindowFeatures(),
                from: harness.sourceWebView,
                isExtensionOriginated: false
            )

        XCTAssertNil(popupWebView)
        XCTAssertEqual(
            Set(
                harness.browserManager.tabCollectionMembershipOwner
                    .allIdentityWitnesses()
                    .filter { $0.isAuxiliaryMiniWindow }
                    .map(\.id)
            ),
            existingAuxiliaryTabIDs
        )
    }

    func testExtensionTabOpenersRejectUnavailableRegistrarBeforeMutation()
        throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        let sources = physicalSourceResolver(for: harness)
        let tabOpening = PhysicalSourceTabOpeningService(
            spaces: harness.browserManager.spaceStateOwner,
            regularTabs: harness.browserManager.regularTabCollectionOwner,
            regularLifecycle: harness.browserManager.regularTabLifecycleOwner,
            opening: harness.browserManager.tabOpening,
            select: { [weak browserManager = harness.browserManager]
                tab,
                window,
                loadPolicy in
                browserManager?.selectTab(
                    tab,
                    in: window,
                    loadPolicy: loadPolicy
                )
            }
        )
        var externalRegistrar: ExtensionTabRegistrarSpy? =
            ExtensionTabRegistrarSpy()
        let externalOpening = ExtensionExternalTabOpeningService(
            sources: sources,
            tabs: tabOpening,
            extensionTabs: try XCTUnwrap(externalRegistrar)
        )
        externalRegistrar = nil
        let initialTabIDs = regularTabIDs(in: harness)

        XCTAssertFalse(
            externalOpening.open(
                try XCTUnwrap(
                    URL(string: "https://target.example/extension-external")
                ),
                from: harness.sourceWebView
            )
        )
        XCTAssertEqual(regularTabIDs(in: harness), initialTabIDs)

        var childRegistrar: ExtensionTabRegistrarSpy? =
            ExtensionTabRegistrarSpy()
        let childOpening = WebKitChildTabOpeningService(
            sources: sources,
            creation: WebKitChildTabCreationTransaction(
                spaces: harness.browserManager.spaceStateOwner,
                regularTabs: harness.browserManager.regularTabCollectionOwner,
                regularLifecycle: harness.browserManager.regularTabLifecycleOwner,
                ephemeralLifecycle: harness.browserManager.ephemeralLifecycleOwner
            ),
            settlement: WebKitChildTabSettlementTransaction(
                residences: harness.browserManager.tabResidenceAuthority,
                placement: harness.browserManager.testWebViewRuntime()
                    .trackedWebViewAdmission,
                selection: BrowserTabSelectionCommand {
                    [weak browserManager = harness.browserManager]
                    tab,
                    window,
                    loadPolicy in
                    browserManager?.selectTab(
                        tab,
                        in: window,
                        loadPolicy: loadPolicy
                    )
                },
                notifications: harness.browserManager.notificationPresenter,
                extensionTabs: try XCTUnwrap(childRegistrar)
            )
        )
        childRegistrar = nil
        let configuration = webViewConfiguration(
            dataStore: harness.sourceProfile.dataStore
        )

        XCTAssertNil(
            childOpening.open(
                configuration: configuration,
                requestURL: URL(
                    string: "https://target.example/extension-child"
                ),
                from: harness.sourceWebView,
                selected: true,
                isExtensionOriginated: true
            )
        )
        XCTAssertEqual(regularTabIDs(in: harness), initialTabIDs)
    }

    func testWebKitChildTabPlacementRejectionRollsBackCreatedModelAndWebView()
        throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        let placement = RejectingAuxiliaryTrackedPlacement()
        let opening = WebKitChildTabOpeningService(
            sources: physicalSourceResolver(for: harness),
            creation: WebKitChildTabCreationTransaction(
                spaces: harness.browserManager.spaceStateOwner,
                regularTabs: harness.browserManager.regularTabCollectionOwner,
                regularLifecycle: harness.browserManager.regularTabLifecycleOwner,
                ephemeralLifecycle: harness.browserManager.ephemeralLifecycleOwner
            ),
            settlement: WebKitChildTabSettlementTransaction(
                residences: harness.browserManager.tabResidenceAuthority,
                placement: placement,
                selection: BrowserTabSelectionCommand {
                    [weak browserManager = harness.browserManager]
                    tab,
                    window,
                    loadPolicy in
                    browserManager?.selectTab(
                        tab,
                        in: window,
                        loadPolicy: loadPolicy
                    )
                },
                notifications: harness.browserManager.notificationPresenter,
                extensionTabs: ExtensionTabRegistrarSpy()
            )
        )
        let initialTabIDs = regularTabIDs(in: harness)
        let initialSelection = harness.sourceWindow.currentTabId
        let initialChildIdentity = WebKitChildWindowIdentity(
            initialTabID: UUID()
        )
        harness.sourceWindow.webKitChildWindowIdentity = initialChildIdentity

        XCTAssertNil(
            opening.open(
                configuration: webViewConfiguration(
                    dataStore: harness.sourceProfile.dataStore
                ),
                requestURL: URL(
                    string: "https://target.example/rejected-child-tab"
                ),
                from: harness.sourceWebView,
                selected: true,
                isExtensionOriginated: false
            )
        )

        let rejectedTab = try XCTUnwrap(placement.tab)
        let rejectedWebView = try XCTUnwrap(placement.webView)
        XCTAssertEqual(regularTabIDs(in: harness), initialTabIDs)
        XCTAssertNil(
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: rejectedTab.id)
        )
        XCTAssertEqual(harness.sourceWindow.currentTabId, initialSelection)
        XCTAssertEqual(
            harness.sourceWindow.webKitChildWindowIdentity,
            initialChildIdentity
        )
        XCTAssertNil(rejectedWebView.owningTab)
        XCTAssertNil(rejectedWebView.navigationDelegate)
        XCTAssertNil(rejectedWebView.uiDelegate)
    }

    func testWebKitChildWindowPlacementRejectionRollsBackPreparedShellTabAndWebView()
        throws {
        let harness = try makeRegularHarness()
        defer { closePublishedShells(in: harness.windowRegistry) }
        let placement = RejectingAuxiliaryTrackedPlacement()
        let webViews = harness.browserManager.testWebViewRuntime()
        let opening = WebKitChildWindowOpeningService(
            windowTransaction: WebKitChildWindowShellTransaction(
                commands: harness.browserManager.windowCommands,
                restoration: harness.browserManager.windowSessionBundle
                    .restoreService,
                profiles: harness.browserManager.profileManager,
                spaces: harness.browserManager.spaceStateOwner
            ),
            regularTabs: harness.browserManager.regularTabCollectionOwner,
            regularLifecycle: harness.browserManager.regularTabLifecycleOwner,
            ephemeralLifecycle: harness.browserManager.ephemeralLifecycleOwner,
            residences: harness.browserManager.tabResidenceAuthority,
            placement: placement,
            ownershipQuery: webViews.ownershipQuery,
            sourceResolver: physicalSourceResolver(for: harness),
            lifecycle: webViews.lifecycleService,
            extensionPublication: harness.browserManager
                .windowExtensionPublication,
            persistWindowSession: { _ in
                XCTFail("A rejected child window must not persist")
            }
        )
        let initialTabIDs = regularTabIDs(in: harness)
        let initialWindowIDs = Set(harness.windowRegistry.windows.keys)

        XCTAssertNil(
            opening.open(
                configuration: webViewConfiguration(
                    dataStore: harness.sourceProfile.dataStore
                ),
                requestURL: URL(
                    string: "https://target.example/rejected-child-window"
                ),
                from: harness.sourceWebView,
                activate: true,
                isExtensionOriginated: false
            )
        )

        let rejectedTab = try XCTUnwrap(placement.tab)
        let rejectedWebView = try XCTUnwrap(placement.webView)
        XCTAssertEqual(regularTabIDs(in: harness), initialTabIDs)
        XCTAssertEqual(
            Set(harness.windowRegistry.windows.keys),
            initialWindowIDs
        )
        XCTAssertNil(
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: rejectedTab.id)
        )
        XCTAssertNil(rejectedWebView.owningTab)
        XCTAssertNil(rejectedWebView.navigationDelegate)
        XCTAssertNil(rejectedWebView.uiDelegate)
    }

    func testNewWindowLinkCopiesSourceProfileAndSpaceBeforeOpeningTab() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://target.example/window"))
        var existingWindowIDs: Set<UUID> = []
        var observedPreparedWindow = false
        var selectedTabAtRegistration: UUID?
        var initialTabAtRegistration: Tab?
        var profileAtRegistration: UUID?
        var spaceAtRegistration: UUID?
        let harness = try makeRegularHarness { browserManager, windowRegistry in
            existingWindowIDs = Set(windowRegistry.windows.keys)
            let restoration = browserManager.windowSessionBundle.restoration
            installWindowRegistryTestEventSink(
                on: windowRegistry,
                prepareWindowRegistration: { [weak restoration] windowState in
                    if existingWindowIDs.contains(windowState.id) == false {
                        observedPreparedWindow = true
                        selectedTabAtRegistration = windowState.currentTabId
                        initialTabAtRegistration = windowState.currentTabId.flatMap {
                            browserManager.tabCollectionMembershipOwner
                                .tab(for: $0)
                        }
                        profileAtRegistration = windowState.currentProfileId
                        spaceAtRegistration = windowState.currentSpaceId
                    }
                    restoration?.prepareRegistration(windowState)
                },
                publishWindowRegistration: { [weak restoration] windowState in
                    restoration?.commitRegistration(windowState)
                }
            )
        }
        defer { closePublishedShells(in: harness.windowRegistry) }

        XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
            targetURL,
            from: harness.sourceWebView,
            disposition: .newWindow(selected: true)
        ))

        let targetWindow = try XCTUnwrap(
            harness.windowRegistry.allWindows.first {
                existingWindowIDs.contains($0.id) == false
            }
        )
        XCTAssertTrue(observedPreparedWindow)
        XCTAssertEqual(selectedTabAtRegistration, initialTabAtRegistration?.id)
        XCTAssertEqual(initialTabAtRegistration?.url, targetURL)
        XCTAssertEqual(profileAtRegistration, harness.sourceProfile.id)
        XCTAssertEqual(spaceAtRegistration, harness.sourceSpace.id)
        XCTAssertFalse(targetWindow.isIncognito)
        XCTAssertEqual(targetWindow.currentProfileId, harness.sourceProfile.id)
        XCTAssertEqual(targetWindow.currentSpaceId, harness.sourceSpace.id)

        let targetTabID = try XCTUnwrap(targetWindow.currentTabId)
        let targetTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.sourceSpace)
                .first { $0.id == targetTabID }
        )
        XCTAssertIdentical(targetTab, initialTabAtRegistration)
        XCTAssertEqual(targetTab.url, targetURL)
        XCTAssertNil(
            targetTab.profileId,
            "A stable regular Tab inherits its effective profile from its canonical Space."
        )
        XCTAssertEqual(targetTab.spaceId, harness.sourceSpace.id)
        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.unrelatedSpace)
                .allSatisfy { $0.url != targetURL },
            "A contextual new-window link must not use the global current space."
        )
    }

    func testIncognitoNewWindowLinkCreatesOnlyEphemeralTargetState() throws {
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

        let sourceTab = browserManager.tabOpening.openNewTab(
            url: "https://private-source.example",
            context: .foreground(
                windowState: sourceWindow,
                preferredSpaceId: sourceSpace.id
            )
        )
        let existingWindowIDs = Set(windowRegistry.windows.keys)
        let targetURL = try XCTUnwrap(
            URL(string: "https://private-target.example/window")
        )
        let restoration = browserManager.windowSessionBundle.restoration
        var initialTabAtRegistration: Tab?
        var profileAtRegistration: Profile?
        installWindowRegistryTestEventSink(
            on: windowRegistry,
            prepareWindowRegistration: { [weak restoration] window in
                if existingWindowIDs.contains(window.id) == false {
                    initialTabAtRegistration = window.ephemeralTabs.first {
                        $0.id == window.currentTabId
                    }
                    profileAtRegistration = window.ephemeralProfile
                }
                restoration?.prepareRegistration(window)
            },
            publishWindowRegistration: { [weak restoration] window in
                restoration?.commitRegistration(window)
            }
        )

        let sourceConfiguration = WKWebViewConfiguration()
        sourceConfiguration.websiteDataStore = sourceProfile.dataStore
        let sourceWebView = FocusableWKWebView(
            frame: .zero,
            configuration: sourceConfiguration
        )
        sourceWebView.owningTab = sourceTab
        browserManager.testWebViewRuntime().trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            sourceWebView,
            for: sourceTab,
            in: sourceWindow.id
        )

        XCTAssertTrue(sourceTab.linkPresentationCommands.open(
            targetURL,
            from: sourceWebView,
            disposition: .newWindow(selected: true)
        ))

        let targetWindow = try XCTUnwrap(
            windowRegistry.allWindows.first {
                existingWindowIDs.contains($0.id) == false
            }
        )
        let targetProfile = try XCTUnwrap(targetWindow.ephemeralProfile)
        let targetSpace = try XCTUnwrap(targetWindow.ephemeralSpaces.first)
        XCTAssertIdentical(profileAtRegistration, targetProfile)
        XCTAssertTrue(targetWindow.isIncognito)
        XCTAssertNotEqual(targetProfile.id, sourceProfile.id)
        XCTAssertEqual(targetWindow.currentProfileId, targetProfile.id)
        XCTAssertEqual(targetWindow.currentSpaceId, targetSpace.id)
        XCTAssertEqual(targetSpace.profileId, targetProfile.id)
        XCTAssertEqual(targetSpace.name, "Private")
        XCTAssertTrue(targetSpace.isEphemeral)
        XCTAssertEqual(
            windowRegistry.appKitWindow(for: targetWindow)?.title,
            "Private Window - Sumi"
        )

        XCTAssertEqual(targetWindow.ephemeralTabs.count, 1)
        let targetTab = try XCTUnwrap(targetWindow.ephemeralTabs.first)
        XCTAssertIdentical(initialTabAtRegistration, targetTab)
        XCTAssertEqual(targetWindow.currentTabId, targetTab.id)
        XCTAssertEqual(targetTab.url, targetURL)
        XCTAssertTrue(targetTab.isEphemeral)
        XCTAssertEqual(targetTab.profileId, targetProfile.id)
        XCTAssertNil(
            targetTab.spaceId,
            "Private tabs stay window-scoped instead of joining the shared regular-space graph."
        )
        XCTAssertTrue(
            browserManager.regularTabCollectionOwner
                .allTabs(in: browserManager.spaceStateOwner.spaces)
                .allSatisfy { $0.url != targetURL },
            "An incognito new-window link must never enter the persistent regular-tab graph."
        )
        XCTAssertEqual(
            windowRegistry.allWindows
                .flatMap(\.ephemeralTabs)
                .filter { $0.url == targetURL }
                .map(\.id),
            [targetTab.id],
            "The private URL must exist only in the newly created ephemeral window."
        )
    }

    func testRejectedPrivateLinkMaterializationCannotRollbackReplacedAggregate()
        async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: windowRegistry)
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        installRegistrationRestoration(
            from: browserManager,
            on: windowRegistry
        )
        defer { closePublishedShells(in: windowRegistry) }

        let sourceWindow = BrowserWindowState()
        let sourceProfile = browserManager.profileManager
            .createEphemeralProfile(for: sourceWindow.id)
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
        let source = PhysicalWebViewSourceReceipt(
            webView: sourceWebView,
            trackedWebView: TrackedWebViewOwner(
                tabID: sourceTab.id,
                windowID: sourceWindow.id
            ),
            tab: sourceTab,
            window: sourceWindow,
            residence: .privateEphemeral,
            presentationSpace: sourceSpace,
            presentationProfile: sourceProfile,
            executionProfile: sourceProfile,
            dataStore: sourceProfile.dataStore,
            appKitWindow: nil
        )

        var rejectedWindow: BrowserWindowState?
        var originalTab: Tab?
        var replacementProfile: Profile?
        var replacementSpace: Space?
        let replacementSelection = UUID()
        var persistedWindows = 0
        let transaction = BrowserLinkWindowTransaction(
            commands: browserManager.windowCommands,
            restoration: browserManager.windowSessionBundle.restoreService,
            extensionPublication: browserManager.windowExtensionPublication,
            profiles: browserManager.profileManager,
            spaces: browserManager.spaceStateOwner,
            regularLifecycle: browserManager.regularTabLifecycleOwner,
            ephemeralLifecycle: browserManager.ephemeralLifecycleOwner,
            residences: browserManager.tabResidenceAuthority,
            persistWindow: { _ in persistedWindows += 1 },
            materialize: { tab, window in
                rejectedWindow = window
                originalTab = tab
                browserManager.structuralPersistence
                    .scheduleRuntimeStatePersistence(for: tab)
                let profile = browserManager.profileManager
                    .createEphemeralProfile(for: window.id)
                let space = Space(
                    name: "Replacement Private",
                    profileId: profile.id
                )
                space.isEphemeral = true
                replacementProfile = profile
                replacementSpace = space
                window.ephemeralProfile = profile
                window.replaceEphemeralSpaces([space])
                window.currentProfileId = profile.id
                window.currentSpaceId = space.id
                window.currentTabId = replacementSelection
                return nil
            }
        )

        XCTAssertNil(transaction.open(
            try XCTUnwrap(URL(string: "https://private-target.example")),
            from: source,
            activate: false
        ))

        let window = try XCTUnwrap(rejectedWindow)
        let tab = try XCTUnwrap(originalTab)
        let profile = try XCTUnwrap(replacementProfile)
        let space = try XCTUnwrap(replacementSpace)
        XCTAssertEqual(persistedWindows, 0)
        XCTAssertTrue(window.ephemeralProfile === profile)
        XCTAssertEqual(window.currentProfileId, profile.id)
        XCTAssertEqual(window.currentSpaceId, space.id)
        XCTAssertEqual(window.currentTabId, replacementSelection)
        XCTAssertEqual(window.ephemeralSpaces.count, 1)
        XCTAssertTrue(window.ephemeralSpaces.first === space)
        XCTAssertEqual(window.ephemeralTabs.count, 1)
        XCTAssertTrue(window.ephemeralTabs.first === tab)
        XCTAssertTrue(
            browserManager.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: window.id
            )
        )
        let flushedRuntimeStateCount = await browserManager
            .structuralPersistence.flushRuntimeStatePersistenceAwaitingResult()
        XCTAssertEqual(
            flushedRuntimeStateCount,
            0,
            "Private ephemeral tabs never enter durable regular-tab persistence."
        )
    }

    func testPrivateLinkRollbackDefersInventoryUntilAggregateCommit() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: windowRegistry)
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        installRegistrationRestoration(
            from: browserManager,
            on: windowRegistry
        )
        defer { closePublishedShells(in: windowRegistry) }
        let sourceWindow = BrowserWindowState()
        let sourceProfile = browserManager.profileManager
            .createEphemeralProfile(for: sourceWindow.id)
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
        let sourceTab = browserManager.ephemeralLifecycleOwner
            .createEphemeralTab(
                url: try XCTUnwrap(
                    URL(string: "https://private-atomic-source.example")
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
        let source = PhysicalWebViewSourceReceipt(
            webView: sourceWebView,
            trackedWebView: TrackedWebViewOwner(
                tabID: sourceTab.id,
                windowID: sourceWindow.id
            ),
            tab: sourceTab,
            window: sourceWindow,
            residence: .privateEphemeral,
            presentationSpace: sourceSpace,
            presentationProfile: sourceProfile,
            executionProfile: sourceProfile,
            dataStore: sourceProfile.dataStore,
            appKitWindow: nil
        )

        var rejectedWindow: BrowserWindowState?
        var originalTab: Tab?
        var replacementProfile: Profile?
        var replacementSpace: Space?
        var replacementTab: Tab?
        var replacementSelection: UUID?
        var didObserveCommittedAggregate = false
        var inventoryCancellable: AnyCancellable?
        let transaction = BrowserLinkWindowTransaction(
            commands: browserManager.windowCommands,
            restoration: browserManager.windowSessionBundle.restoreService,
            extensionPublication: browserManager.windowExtensionPublication,
            profiles: browserManager.profileManager,
            spaces: browserManager.spaceStateOwner,
            regularLifecycle: browserManager.regularTabLifecycleOwner,
            ephemeralLifecycle: browserManager.ephemeralLifecycleOwner,
            residences: browserManager.tabResidenceAuthority,
            persistWindow: { _ in XCTFail("Rejected window must not persist") },
            materialize: { tab, window in
                rejectedWindow = window
                originalTab = tab
                inventoryCancellable = window.ephemeralInventoryAuthority
                    .tabInventoryChanges
                    .sink {
                        guard didObserveCommittedAggregate == false else {
                            return
                        }
                        didObserveCommittedAggregate = true
                        XCTAssertNil(window.currentTabId)
                        XCTAssertNil(window.currentSpaceId)
                        XCTAssertNil(window.currentProfileId)
                        XCTAssertNil(window.ephemeralProfile)
                        XCTAssertTrue(window.ephemeralTabs.isEmpty)
                        XCTAssertTrue(window.ephemeralSpaces.isEmpty)

                        let profile = browserManager.profileManager
                            .createEphemeralProfile(for: window.id)
                        let space = Space(
                            name: "Replacement Private",
                            profileId: profile.id
                        )
                        space.isEphemeral = true
                        window.ephemeralProfile = profile
                        window.replaceEphemeralSpaces([space])
                        window.currentProfileId = profile.id
                        window.currentSpaceId = space.id
                        let tab = browserManager.ephemeralLifecycleOwner
                            .createEphemeralTab(
                                url: URL(
                                    string: "https://private-atomic-replacement.example"
                                )!,
                                in: window,
                                profile: profile
                            )
                        window.currentTabId = tab.id
                        replacementProfile = profile
                        replacementSpace = space
                        replacementTab = tab
                        replacementSelection = tab.id
                    }
                return nil
            }
        )

        XCTAssertNil(transaction.open(
            try XCTUnwrap(
                URL(string: "https://private-atomic-target.example")
            ),
            from: source,
            activate: false
        ))

        let window = try XCTUnwrap(rejectedWindow)
        let oldTab = try XCTUnwrap(originalTab)
        let profile = try XCTUnwrap(replacementProfile)
        let space = try XCTUnwrap(replacementSpace)
        let tab = try XCTUnwrap(replacementTab)
        XCTAssertTrue(didObserveCommittedAggregate)
        XCTAssertFalse(window.ephemeralTabs.contains { $0 === oldTab })
        XCTAssertTrue(window.ephemeralProfile === profile)
        XCTAssertEqual(window.currentProfileId, profile.id)
        XCTAssertEqual(window.currentSpaceId, space.id)
        XCTAssertEqual(window.currentTabId, replacementSelection)
        XCTAssertEqual(window.ephemeralSpaces.count, 1)
        XCTAssertTrue(window.ephemeralSpaces.first === space)
        XCTAssertEqual(window.ephemeralTabs.count, 1)
        XCTAssertTrue(window.ephemeralTabs.first === tab)
        XCTAssertTrue(
            browserManager.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: window.id
            )
        )
        withExtendedLifetime(inventoryCancellable) {}
    }

    func makeRegularHarness(
        installEventSink: ((BrowserManager, WindowRegistry) -> Void)? = nil
    ) throws -> RegularHarness {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(windowRegistry: windowRegistry)
        let sourceProfile = Profile(name: "Source Profile")
        let unrelatedProfile = Profile(name: "Unrelated Profile")
        let sourceSpace = Space(
            name: "Source Space",
            profileId: sourceProfile.id
        )
        let unrelatedSpace = Space(
            name: "Unrelated Space",
            profileId: unrelatedProfile.id
        )
        let sourceWindow = BrowserWindowState()
        let settings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )

        browserManager.profileManager.profiles = [sourceProfile, unrelatedProfile]
        browserManager.sumiSettings = settings
        browserManager.currentProfile = unrelatedProfile
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        browserManager.spaceStateOwner.replaceSpaces([
            sourceSpace,
            unrelatedSpace,
        ])
        browserManager.spaceStateOwner.replaceCurrentSpace(unrelatedSpace)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: sourceWindow)
        sourceWindow.currentProfileId = sourceProfile.id
        sourceWindow.currentSpaceId = sourceSpace.id
        windowRegistry.register(sourceWindow)
        windowRegistry.setActive(sourceWindow)
        if let installEventSink {
            installEventSink(browserManager, windowRegistry)
        } else {
            installRegistrationRestoration(
                from: browserManager,
                on: windowRegistry
            )
        }

        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: sourceSpace,
            activate: false
        )
        sourceWindow.currentTabId = sourceTab.id
        let sourceConfiguration = WKWebViewConfiguration()
        sourceConfiguration.websiteDataStore = sourceProfile.dataStore
        let sourceWebView = FocusableWKWebView(
            frame: .zero,
            configuration: sourceConfiguration
        )
        sourceWebView.owningTab = sourceTab
        browserManager.testWebViewRuntime().trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            sourceWebView,
            for: sourceTab,
            in: sourceWindow.id
        )

        XCTAssertTrue(sourceTab.hasBrowserRuntime)
        return RegularHarness(
            browserManager: browserManager,
            settings: settings,
            windowRegistry: windowRegistry,
            sourceWindow: sourceWindow,
            sourceProfile: sourceProfile,
            sourceSpace: sourceSpace,
            unrelatedSpace: unrelatedSpace,
            sourceTab: sourceTab,
            sourceWebView: sourceWebView
        )
    }

    func makeBrowserManager(
        windowRegistry: WindowRegistry = WindowRegistry()
    ) throws -> BrowserManager {
        BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try SumiDatabase.inMemory()
            )
        )
    }

    func physicalSourceResolver(
        for harness: RegularHarness
    ) -> PhysicalWebViewSourceResolver {
        PhysicalWebViewSourceResolver(
            ownership: harness.browserManager.testWebViewRuntime()
                .ownershipQuery,
            sourceContexts: BrowserWindowSourceContextResolver(
                spaces: harness.browserManager.spaceStateOwner,
                regularTabs: harness.browserManager.regularTabCollectionOwner,
                shortcutTabs: harness.browserManager.liveShortcutTabs
            ),
            pins: harness.browserManager.shortcutPinCollectionStateOwner,
            shortcutResolution: harness.browserManager
                .shortcutPinRuntimeResolutionOwner,
            profiles: harness.browserManager.profileManager,
            registry: { [weak registry = harness.windowRegistry] in
                registry
            }
        )
    }

    func makeChildWindowOpening(
        for harness: RegularHarness,
        extensionPublication: WindowExtensionPublicationTransaction
    ) -> WebKitChildWindowOpeningService {
        let webViews = harness.browserManager.testWebViewRuntime()
        return WebKitChildWindowOpeningService(
            windowTransaction: WebKitChildWindowShellTransaction(
                commands: harness.browserManager.windowCommands,
                restoration: harness.browserManager.windowSessionBundle
                    .restoreService,
                profiles: harness.browserManager.profileManager,
                spaces: harness.browserManager.spaceStateOwner
            ),
            regularTabs: harness.browserManager.regularTabCollectionOwner,
            regularLifecycle: harness.browserManager.regularTabLifecycleOwner,
            ephemeralLifecycle: harness.browserManager.ephemeralLifecycleOwner,
            residences: harness.browserManager.tabResidenceAuthority,
            placement: webViews.trackedWebViewAdmission,
            ownershipQuery: webViews.ownershipQuery,
            sourceResolver: physicalSourceResolver(for: harness),
            lifecycle: webViews.lifecycleService,
            extensionPublication: extensionPublication,
            persistWindowSession: { _ in /* Not relevant to routing tests. */ }
        )
    }

    func bindSourceShell(in harness: RegularHarness) -> NSWindow {
        let shell = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        harness.windowRegistry.bindAppKitWindow(
            shell,
            to: harness.sourceWindow
        )
        return shell
    }

    func installExtensionPublication(
        _ publication: WindowExtensionPublicationTransaction,
        events: ChildWindowPublicationEvents,
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry
    ) {
        let restoration = browserManager.windowSessionBundle.restoration
        installWindowRegistryTestEventSink(
            on: windowRegistry,
            prepareWindowRegistration: { [weak restoration] window in
                restoration?.prepareRegistration(window)
                publication.prepareRegistration(window)
            },
            publishWindowRegistration: { [weak restoration] window in
                events.values.append("registry")
                publication.commitRegistration(window)
                restoration?.commitRegistration(window)
            }
        )
    }

    func regularTabIDs(in harness: RegularHarness) -> Set<UUID> {
        Set(
            harness.browserManager.tabStateStore.regularTabs
                .allTabsSnapshot().map(\.id)
        )
    }

    func closePublishedShells(in windowRegistry: WindowRegistry) {
        for windowState in windowRegistry.allWindows {
            let shell = windowRegistry.appKitWindow(for: windowState)
            windowRegistry.unregister(windowState.id)
            shell?.orderOut(nil)
        }
    }

    func installRegistrationRestoration(
        from browserManager: BrowserManager,
        on windowRegistry: WindowRegistry
    ) {
        let restoration = browserManager.windowSessionBundle.restoration
        installWindowRegistryTestEventSink(
            on: windowRegistry,
            prepareWindowRegistration: { [weak restoration] windowState in
                restoration?.prepareRegistration(windowState)
            },
            publishWindowRegistration: { [weak restoration] windowState in
                restoration?.commitRegistration(windowState)
            }
        )
    }

    func webViewConfiguration(
        dataStore: WKWebsiteDataStore
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return configuration
    }
}

@MainActor
struct RegularHarness {
    let browserManager: BrowserManager
    let settings: SumiSettingsService
    let windowRegistry: WindowRegistry
    let sourceWindow: BrowserWindowState
    let sourceProfile: Profile
    let sourceSpace: Space
    let unrelatedSpace: Space
    let sourceTab: Tab
    let sourceWebView: FocusableWKWebView
}

@MainActor
final class ExtensionTabRegistrarSpy: ExtensionCreatedTabRegistering {
    func registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
        _: Tab,
        reason _: String
    ) {}
}

@MainActor
final class RejectingAuxiliaryTrackedPlacement:
    AuxiliaryTrackedWebViewPlacing {
    private(set) var tab: Tab?
    private(set) var webView: FocusableWKWebView?

    func registerAuxiliaryTrackedWebView(
        _ webView: FocusableWKWebView,
        for tab: Tab,
        in _: UUID
    ) -> TrackedWebViewAdmissionOutcome {
        self.tab = tab
        self.webView = webView
        return .placed(
            .rejected(.trackedRegistration(.protectedCandidate))
        )
    }
}

@MainActor
final class ChildWindowPublicationEvents {
    var values: [String] = []
    var tabPublicationSawPublishedWindow = false
}

@MainActor
final class ChildWindowExtensionPublicationProbe:
    InitialTabExtensionPreparing,
    BrowserWindowExtensionPublishing {
    enum Preparation {
        case prepared
        case suppressed
    }

    weak var registry: WindowRegistry?
    let events: ChildWindowPublicationEvents
    let preparation: Preparation
    private(set) var windowNotificationSawPublishedWindow = false

    init(
        registry: WindowRegistry,
        events: ChildWindowPublicationEvents,
        preparation: Preparation
    ) {
        self.registry = registry
        self.events = events
        self.preparation = preparation
    }

    func prepareInitialTabExtensionPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason _: String
    ) -> InitialTabExtensionPreparation {
        events.values.append("prepare")
        switch preparation {
        case .prepared:
            guard let registry else { return .rejected }
            return .prepared(
                ChildWindowInitialTabPublicationProbe(
                    window: window,
                    tab: tab,
                    webView: webView,
                    registry: registry,
                    events: events
                )
            )
        case .suppressed:
            return .suppressed
        }
    }

    func publishWindowIfLoaded(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        windowNotificationSawPublishedWindow =
            registry?.windows[windowState.id] === windowState
        events.values.append("window")
        return .published(
            ChildWindowPublicationLease(
                window: windowState,
                registry: registry
            )
        )
    }
}

@MainActor
final class ChildWindowPublicationLease:
    BrowserWindowExtensionPublication {
    weak var window: BrowserWindowState?
    weak var registry: WindowRegistry?

    init(window: BrowserWindowState, registry: WindowRegistry?) {
        self.window = window
        self.registry = registry
    }

    func isCurrent() -> Bool {
        guard let window else { return false }
        return registry?.windows[window.id] === window
    }

    func revokeIfCurrent() {}
}

@MainActor
final class ChildWindowInitialTabPublicationProbe:
    InitialTabExtensionPublication {
    let window: BrowserWindowState
    let tab: Tab
    let webView: FocusableWKWebView
    weak var registry: WindowRegistry?
    let events: ChildWindowPublicationEvents
    var isPending = true

    init(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        registry: WindowRegistry,
        events: ChildWindowPublicationEvents
    ) {
        self.window = window
        self.tab = tab
        self.webView = webView
        self.registry = registry
        self.events = events
    }

    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        isPending
            && self.window === window
            && self.tab === tab
            && self.webView === webView
    }

    func validateBeforeWindowPublication() -> Bool {
        events.values.append("validate")
        return isPending
            && window.currentTabId == tab.id
            && webView.owningTab === tab
    }

    func publishInitialTab(
        afterWindowOpened publishedWindow: BrowserWindowState
    ) -> Bool {
        guard isPending, publishedWindow === window else { return false }
        events.tabPublicationSawPublishedWindow =
            registry?.windows[window.id] === window
        events.values.append("tab")
        isPending = false
        return true
    }

    func cancel() -> Bool {
        guard isPending else { return false }
        events.values.append("cancel")
        isPending = false
        return true
    }
}
