import Foundation
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionRequestedTabServicesTests {
    func testPreparedAndPublishedQueriesRejectStaleSameUUIDTab() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let manager = harness.manager
        let tab = harness.sourceTab
        let generation = manager.tabPublicationRevisions.issue()
        let adapter = try XCTUnwrap(
            manager.adapterStore.existingTabAdapter(for: tab.id)
        )

        XCTAssertTrue(manager.preparedExtensionTabs.containsPreparedTab(tab))
        XCTAssertTrue(manager.publishedExtensionTabs.containsPublishedTab(tab))

        XCTAssertTrue(
            tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(generation: generation)
        )
        manager.tabLifecycleEvents.emitDidCloseTab(
            tab,
            controller: harness.controller,
            adapter: adapter
        )
        let replacementClaim = try XCTUnwrap(
            tab.extensionPageRuntimeOwner.reserveDidOpenTab(
                generation: generation
            )
        )
        manager.tabLifecycleEvents.emitDidOpenTab(
            tab,
            controller: harness.controller,
            adapter: adapter
        )

        XCTAssertTrue(manager.preparedExtensionTabs.containsPreparedTab(tab))
        XCTAssertFalse(manager.publishedExtensionTabs.containsPublishedTab(tab))
        XCTAssertNil(
            harness.publishedWindow.activeTab(for: harness.extensionContext)
        )
        XCTAssertFalse(
            harness.publishedWindow.tabs(for: harness.extensionContext)
                .contains { ($0 as? ExtensionTabAdapter)?.tab === tab }
        )
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner.settleDidOpenTabNotification(
                replacementClaim,
                generation: generation
            )
        )
        XCTAssertTrue(manager.publishedExtensionTabs.containsPublishedTab(tab))
        XCTAssertIdentical(
            harness.publishedWindow.activeTab(for: harness.extensionContext)
                as? ExtensionTabAdapter,
            adapter
        )

        XCTAssertTrue(
            manager.adapterStore.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        )
        XCTAssertTrue(manager.preparedExtensionTabs.containsPreparedTab(tab))
        XCTAssertFalse(manager.publishedExtensionTabs.containsPublishedTab(tab))
        XCTAssertIdentical(
            manager.adapterStore.tabAdapter(for: tab, create: { adapter }),
            adapter
        )

        let staleSameUUID = harness.browserManager.tabManager.tabFactory.makeTab(
            id: tab.id,
            url: URL(string: "https://stale.example/same-id")!,
            name: "Stale same UUID",
            spaceId: tab.spaceId,
            index: tab.index
        )
        staleSameUUID.profileId = harness.profile.id
        staleSameUUID.extensionPageRuntimeOwner.prepareGeneration(generation)
        staleSameUUID.extensionPageRuntimeOwner.markEligible(for: generation)

        XCTAssertFalse(
            manager.preparedExtensionTabs.containsPreparedTab(staleSameUUID)
        )
        XCTAssertFalse(
            manager.publishedExtensionTabs.containsPublishedTab(staleSameUUID)
        )
    }

    func testWindowAdapterReadsPreparedTabOnlyInsideDidOpenWindowCallback()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let manager = harness.manager
        var sawPreparedActiveTab = false
        var sawPreparedTabInList = false
        manager.testHooks.didOpenNormalWindow = { windowID in
            guard windowID == harness.window.id else { return }
            guard let window = manager.adapterCatalog
                .publishedNormalWindowAdapter(
                    for: harness.window,
                    extensionContext: harness.extensionContext
                )
            else { return }
            sawPreparedActiveTab = window.activeTab(
                for: harness.extensionContext
            ) != nil
            sawPreparedTabInList = window.tabs(
                for: harness.extensionContext
            ).contains {
                ($0 as? ExtensionTabAdapter)?.tab === harness.sourceTab
            }
        }
        defer { manager.testHooks.didOpenNormalWindow = nil }

        manager.reloadRuntimePublications(
            reason: #function,
            profileID: harness.profile.id
        )

        XCTAssertTrue(sawPreparedActiveTab)
        XCTAssertTrue(sawPreparedTabInList)
        XCTAssertTrue(
            manager.publishedExtensionTabs.containsPublishedTab(
                harness.sourceTab
            )
        )
    }

    func testRejectedDuplicateOpenDoesNotRewriteDocumentBinding()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let manager = harness.manager
        let tab = harness.sourceTab
        let bindingBeforeDuplicate = tab.extensionPageRuntimeOwner
            .documentBindingSnapshot()

        _ = manager.profileRuntime.bumpContextBindingGeneration(
            for: harness.profile.id
        )

        XCTAssertFalse(manager.normalTabOpening.publishOpen(tab))
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.documentBindingSnapshot(),
            bindingBeforeDuplicate
        )
    }

    func testDeferredRegistrationRejectsCapturedTabAfterSameUUIDReplacement()
        async throws {
        let profileID = UUID()
        let tabID = UUID()
        let original = Tab(
            id: tabID,
            url: URL(string: "https://original.example")!,
            name: "Original"
        )
        original.profileId = profileID
        let replacement = Tab(
            id: tabID,
            url: URL(string: "https://replacement.example")!,
            name: "Replacement"
        )
        replacement.profileId = profileID
        let tabPublicationRevision = ExtensionTabPublicationRevision(
            generation: 7
        )
        replacement.extensionPageRuntimeOwner.prepareGeneration(
            tabPublicationRevision
        )
        replacement.extensionPageRuntimeOwner.markEligible(
            for: tabPublicationRevision
        )
        let replacementClaim = try XCTUnwrap(
            replacement.extensionPageRuntimeOwner.reserveDidOpenTab(
                generation: tabPublicationRevision
            )
        )
        XCTAssertTrue(
            replacement.extensionPageRuntimeOwner.settleDidOpenTabNotification(
                replacementClaim,
                generation: tabPublicationRevision
            )
        )
        XCTAssertTrue(
            replacement.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(
                    for: tabPublicationRevision
                )
        )
        var currentTab: Tab? = original
        let tabs = BrowserExtensionTabQueryAdapter(
            regularTab: { _ in currentTab },
            allTabs: { [original, replacement] },
            windows: { [] },
            isTransient: { _ in false },
            isAuxiliaryMiniWindow: { _ in false },
            isPinned: { _ in false }
        )
        let profiles = AdversarialTabProfileQuery(profileID: profileID)
        let loadStarted = expectation(description: "context load started")
        let loader = SuspendedInitialDocumentContextLoader(
            onStart: { loadStarted.fulfill() }
        )
        let resumer = RecordingDeferredTabResumer()
        let extensionLoadRevisions = ExtensionLoadRevisionAuthority()
        let registration = ExtensionDeferredTabRegistration(
            extensionLoadRevisions: extensionLoadRevisions,
            tabs: tabs,
            profiles: profiles,
            contextLoading: loader
        )
        registration.bind(resumer: resumer)

        let task = registration
            .scheduleDeferredTabNotificationAfterContextLoad(
                original,
                profileId: profileID,
                extensionLoadRevision: extensionLoadRevisions.issue(),
                reason: #function
            )
        await fulfillment(of: [loadStarted], timeout: 1)

        currentTab = replacement
        loader.resume()
        await task.value

        XCTAssertEqual(loader.loadedProfileIDs, [profileID])
        XCTAssertTrue(resumer.resumedTabs.isEmpty)
        XCTAssertNil(registration.task(for: tabID))
    }

    func testPropertyPublisherRetriesURLAfterReentrantAdapterRemoval()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let manager = harness.manager
        let tab = harness.sourceTab
        let adapter = try XCTUnwrap(
            manager.adapterStore.existingTabAdapter(for: tab.id)
        )
        let webView = try XCTUnwrap(
            harness.browserManager.webViewRuntime.ownershipQuery.webView(
                for: tab.id,
                in: harness.window.id
            )
        )
        let publishedTabs = AdversarialPublishedTabQuery(tab: tab)
        let profiles = AdversarialTabProfileQuery(
            profileID: harness.profile.id
        )
        let liveWebViews = ReentrantLiveWebViewQuery(webView: webView)
        liveWebViews.onNextResolution = { [weak store = manager.adapterStore] in
            store?.removeTabAdapter(for: tab.id)
        }
        var publications: [WKWebExtension.TabChangedProperties] = []
        let publisher = ExtensionTabPropertyPublisher(
            publishedTabs: publishedTabs,
            profiles: profiles,
            profileRuntime: manager.profileRuntime,
            adapters: manager.adapterStore,
            liveWebViews: liveWebViews,
            didPublish: { publishedTabID, properties in
                guard publishedTabID == tab.id else { return }
                publications.append(properties)
            }
        )
        tab.extensionPageRuntimeOwner.lastReportedURL = nil

        publisher.publishChange(for: tab, requested: [.URL])

        XCTAssertNil(tab.extensionPageRuntimeOwner.lastReportedURL)
        XCTAssertTrue(publications.isEmpty)
        XCTAssertNil(manager.adapterStore.existingTabAdapter(for: tab.id))

        XCTAssertIdentical(
            manager.adapterStore.tabAdapter(for: tab, create: { adapter }),
            adapter
        )
        let expectedURL = webView.url ?? tab.url

        publisher.publishChange(for: tab, requested: [.URL])
        publisher.publishChange(for: tab, requested: [.URL])

        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.lastReportedURL?.absoluteString,
            expectedURL.absoluteString
        )
        XCTAssertEqual(publications.count, 1)
        XCTAssertTrue(publications[0].contains(.URL))
    }

    func testRebindClaimsOpenBeforeReentrantCloseAndBalancesLifecycleOnce()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let manager = harness.manager
        let tab = harness.sourceTab
        let generation = manager.tabPublicationRevisions.issue()
        var lifecycleOrder: [String] = []
        var didReenter = false
        manager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            lifecycleOrder.append("close")
            XCTAssertNil(
                tab.extensionPageRuntimeOwner.currentOpenPublicationClaim(
                    generation: generation
                )
            )
            guard didReenter == false else { return }
            didReenter = true
            manager.tabLifecycleRebind.rebindBeforeCommittedNavigation(
                tab,
                reason: "\(#function).reentrant"
            )
        }
        manager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            lifecycleOrder.append("open")
        }
        defer {
            manager.testHooks.didCloseTab = nil
            manager.testHooks.didOpenTab = nil
        }
        tab.extensionPageRuntimeOwner.committedMainDocumentURL = tab.url
        tab.extensionPageRuntimeOwner.documentSequence = 1
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0

        manager.tabLifecycleRebind.rebindBeforeCommittedNavigation(
            tab,
            reason: #function
        )

        XCTAssertTrue(didReenter)
        XCTAssertEqual(lifecycleOrder, ["close", "open"])
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(for: generation)
        )
    }

    func testColdManagerDoesNotMaterializeNormalTabRuntimeComposition()
        throws {
        let container = try makeTestContainer()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Cold normal Tab runtime")
        )

        XCTAssertNil(manager.normalTabRuntimeComposition)
        XCTAssertNil(manager.runtimePublicationComposition)
        XCTAssertNil(manager.loadedDeferredTabRegistration)
    }

    func testRetainedNormalTabLeafCollaboratorsDoNotRetainManager() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Normal Tab leaf lifetime")
        var manager: ExtensionManager? = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            extensionPreferences: UserDefaults(
                suiteName: UUID().uuidString
            )!
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager?.attach(browserManager: browserManager)
        _ = manager?.normalTabRegistration
        let composition = try XCTUnwrap(manager?.normalTabRuntimeComposition)
        let materializer = composition.requestedTabWebViewMaterializer
        let space = browserManager.tabManager.spaceStateOwner.firstSpace(
            forProfile: profile.id
        ) ?? browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Released manager materializer",
            profileId: profile.id
        )
        let materializerProbe = browserManager.tabManager
            .regularTabLifecycleOwner.createNewTab(
                url: "https://released-materializer.example",
                in: space,
                activate: false
            )
        materializerProbe.profileId = profile.id
        materializerProbe.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        XCTAssertNil(materializerProbe.resolvedCurrentWebView())
        let retainedLeaves: [AnyObject] = [
            composition.tabLifecycleEvents,
            composition.preparedTabs,
            composition.publishedTabs,
            composition.deferredTabRegistration,
            composition.tabOpening,
            composition.tabRegistration,
            composition.liveWebViewPreparation,
            composition.tabProperties,
            composition.tabRebind,
        ]
        weak var releasedManager = manager
        let probeTab = Tab(
            url: URL(string: "https://released-manager.example")!,
            name: "Released manager probe"
        )
        let originalEligibleGeneration = probeTab.extensionPageRuntimeOwner
            .currentEligibleGeneration()

        manager = nil

        XCTAssertNil(releasedManager)
        materializer.materializeNormalTabIfNeeded(
            materializerProbe,
            targetWindow: nil
        )
        XCTAssertNil(materializerProbe.resolvedCurrentWebView())
        XCTAssertFalse(composition.preparedTabs.containsPreparedTab(probeTab))
        composition.tabRegistration.register(
            probeTab,
            reason: #function
        )
        XCTAssertEqual(
            probeTab.extensionPageRuntimeOwner.currentEligibleGeneration(),
            originalEligibleGeneration
        )
        withExtendedLifetime((retainedLeaves, browserManager)) {}
    }
}

@available(macOS 15.5, *)
@MainActor
private final class AdversarialTabProfileQuery:
    ExtensionTabProfileResolving {
    private let profileID: UUID

    init(profileID: UUID) {
        self.profileID = profileID
    }

    func profileID(for _: Tab) -> UUID? { profileID }
}

@available(macOS 15.5, *)
@MainActor
private final class AdversarialPublishedTabQuery:
    ExtensionPublishedTabQuery {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func containsPublishedTab(_ tab: Tab) -> Bool {
        self.tab === tab
    }
}

@available(macOS 15.5, *)
@MainActor
private final class SuspendedInitialDocumentContextLoader:
    ExtensionInitialDocumentContextLoading {
    private let onStart: () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var loadedProfileIDs: [UUID] = []

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func ensureInitialExtensionContextsLoaded(for profileId: UUID) async {
        loadedProfileIDs.append(profileId)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecordingDeferredTabResumer:
    ExtensionDeferredTabRuntimeResuming {
    private(set) var resumedTabs: [Tab] = []

    func resumeAfterInitialContextsLoaded(_ tab: Tab, reason _: String) {
        resumedTabs.append(tab)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ReentrantLiveWebViewQuery:
    ExtensionTabLiveWebViewQuery {
    private let webView: WKWebView
    var onNextResolution: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func extensionLiveWebView(for _: Tab) -> WKWebView? {
        let action = onNextResolution
        onNextResolution = nil
        action?()
        return webView
    }
}
