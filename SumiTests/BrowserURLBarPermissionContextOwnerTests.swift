import Combine
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLBarPermissionContextOwnerTests: XCTestCase {
    func testPermissionContextUsesInjectedRuntimeStores() throws {
        let harness = try makeHarness()
        let owner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: harness.browserManager)
        )

        let context = owner.context
        let loadDependencies = owner.loadDependencies

        XCTAssertIdentical(context.popupStore, harness.blockedPopupStore)
        XCTAssertIdentical(context.externalSchemeStore, harness.externalSchemeStore)
        XCTAssertIdentical(context.indicatorEventStore, harness.indicatorEventStore)
        XCTAssertIdentical(context.runtimeController as AnyObject, harness.runtimeController)
        XCTAssertIdentical(loadDependencies.blockedPopupStore, harness.blockedPopupStore)
        XCTAssertIdentical(loadDependencies.externalSchemeSessionStore, harness.externalSchemeStore)
        XCTAssertIdentical(loadDependencies.indicatorEventStore, harness.indicatorEventStore)
        XCTAssertIdentical(loadDependencies.siteActivityStore, harness.siteActivityStore)
        XCTAssertIdentical(
            try XCTUnwrap(loadDependencies.runtimeController) as AnyObject,
            harness.runtimeController
        )
    }

    func testPermissionContextSiteActivityRevisionIsFresh() throws {
        let harness = try makeHarness()
        let owner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: harness.browserManager)
        )
        let context = owner.context

        XCTAssertEqual(context.siteActivityRevision(), 0)

        harness.siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: permissionKey(),
            state: .allow,
            reason: "url-bar-permission-owner-test"
        )

        XCTAssertEqual(context.siteActivityRevision(), harness.siteActivityStore.revision)
    }

    func testPermissionChangePublishersForwardRuntimeStoreChanges() throws {
        let harness = try makeHarness()
        let owner = BrowserURLBarPermissionContextOwner(
            dependencies: .live(browserManager: harness.browserManager)
        )
        var cancellables = Set<AnyCancellable>()
        var blockedPopupChangeCount = 0
        var externalSchemeChangeCount = 0
        var indicatorEventChangeCount = 0
        var siteActivityChangeCount = 0

        owner.blockedPopupChanges
            .sink { blockedPopupChangeCount += 1 }
            .store(in: &cancellables)
        owner.externalSchemeChanges
            .sink { externalSchemeChangeCount += 1 }
            .store(in: &cancellables)
        owner.indicatorEventChanges
            .sink { indicatorEventChangeCount += 1 }
            .store(in: &cancellables)
        owner.siteActivityChanges
            .sink { siteActivityChangeCount += 1 }
            .store(in: &cancellables)

        harness.blockedPopupStore.record(blockedPopupRecord())
        harness.externalSchemeStore.record(externalSchemeRecord())
        harness.indicatorEventStore.record(indicatorEventRecord())
        harness.siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: permissionKey(),
            state: .deny,
            reason: "url-bar-permission-owner-test"
        )

        XCTAssertEqual(blockedPopupChangeCount, 1)
        XCTAssertEqual(externalSchemeChangeCount, 1)
        XCTAssertEqual(indicatorEventChangeCount, 1)
        XCTAssertEqual(siteActivityChangeCount, 1)
    }

    func testBrowserURLBarContextFacadeUsesPermissionOwnerRuntimeStores() throws {
        let harness = try makeHarness()

        let context = harness.browserManager.urlBarContextOwner.urlBarContext

        XCTAssertIdentical(context.permission.popupStore, harness.blockedPopupStore)
        XCTAssertIdentical(context.permission.externalSchemeStore, harness.externalSchemeStore)
        XCTAssertIdentical(context.permission.indicatorEventStore, harness.indicatorEventStore)
        XCTAssertIdentical(context.hub.permissionDependencies.blockedPopupStore, harness.blockedPopupStore)
        XCTAssertIdentical(context.hub.permissionDependencies.externalSchemeSessionStore, harness.externalSchemeStore)
        XCTAssertIdentical(context.hub.permissionDependencies.indicatorEventStore, harness.indicatorEventStore)
        XCTAssertIdentical(context.hub.permissionDependencies.siteActivityStore, harness.siteActivityStore)
    }

    private func makeHarness() throws -> Harness {
        let container = try makeInMemoryStartupContainer()
        let systemPermissionService = FakeSumiSystemPermissionService()
        let permissionCoordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: systemPermissionService
            ),
            persistentStore: nil,
            antiAbuseStore: nil,
            sessionOwnerId: "url-bar-permission-context-owner-tests"
        )
        let runtimeController = FakeSumiRuntimePermissionController()
        let indicatorEventStore = SumiPermissionIndicatorEventStore()
        let siteActivityStore = try makeSiteActivityStore()
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalSchemeStore = SumiExternalSchemeSessionStore()

        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container),
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            runtimePermissionController: runtimeController,
            permissionIndicatorEventStore: indicatorEventStore,
            permissionSiteActivityStore: siteActivityStore,
            blockedPopupStore: blockedPopupStore,
            externalAppResolver: SumiPermissionIntegrationExternalAppResolver(),
            externalSchemeSessionStore: externalSchemeStore
        )

        return Harness(
            browserManager: browserManager,
            runtimeController: runtimeController,
            indicatorEventStore: indicatorEventStore,
            siteActivityStore: siteActivityStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeStore: externalSchemeStore
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeSiteActivityStore() throws -> SumiPermissionSiteActivityStore {
        SumiPermissionSiteActivityStore(
            userDefaults: try XCTUnwrap(
                UserDefaults(suiteName: "BrowserURLBarPermissionContextOwnerTests-\(UUID().uuidString)")
            )
        )
    }

    private func permissionKey() -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )
    }

    private func blockedPopupRecord() -> SumiBlockedPopupRecord {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiBlockedPopupRecord(
            id: "popup-a",
            tabId: "tab-a",
            pageId: "page-a",
            requestingOrigin: origin,
            topOrigin: origin,
            targetURL: URL(string: "https://popup.example"),
            sourceURL: URL(string: "https://example.com"),
            lastBlockedAt: Date(timeIntervalSince1970: 10),
            reason: .blockedByDefault,
            profilePartitionId: "profile-a",
            attemptCount: 1
        )
    }

    private func externalSchemeRecord() -> SumiExternalSchemeAttemptRecord {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiExternalSchemeAttemptRecord(
            id: "external-a",
            tabId: "tab-a",
            pageId: "page-a",
            requestingOrigin: origin,
            topOrigin: origin,
            scheme: "mailto",
            redactedTargetURLString: "mailto:person@example.com",
            lastAttemptAt: Date(timeIntervalSince1970: 11),
            result: .blockedByDefault,
            reason: "test",
            profilePartitionId: "profile-a",
            attemptCount: 1
        )
    }

    private func indicatorEventRecord() -> SumiPermissionIndicatorEventRecord {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionIndicatorEventRecord(
            id: "indicator-a",
            tabId: "tab-a",
            pageId: "page-a",
            displayDomain: "example.com",
            permissionTypes: [.camera],
            category: .activeRuntime,
            visualStyle: .active,
            priority: .activeCamera,
            reason: "test",
            requestingOrigin: origin,
            topOrigin: origin,
            profilePartitionId: "profile-a",
            createdAt: Date(timeIntervalSince1970: 12)
        )
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let runtimeController: FakeSumiRuntimePermissionController
    let indicatorEventStore: SumiPermissionIndicatorEventStore
    let siteActivityStore: SumiPermissionSiteActivityStore
    let blockedPopupStore: SumiBlockedPopupStore
    let externalSchemeStore: SumiExternalSchemeSessionStore
}
