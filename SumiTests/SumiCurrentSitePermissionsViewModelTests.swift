import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiCurrentSitePermissionsViewModelTests: XCTestCase {
    func testInvalidOriginProducesEmptyDisabledState() async {
        let viewModel = SumiCurrentSitePermissionsViewModel()
        await viewModel.load(
            context: context(url: URL(string: "sumi://settings")!),
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies()
        )

        XCTAssertEqual(viewModel.rows, [])
        XCTAssertNil(viewModel.summary.activityText)
        XCTAssertFalse(viewModel.context?.isSupportedWebOrigin ?? true)
    }

    func testBuildsOnlyRowsWithUsageOrResolvedDecisions() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        let blockedStore = SumiBlockedPopupStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let autoplayStore = CurrentSiteFakeAutoplayStore()
        await coordinator.seed(key: context.key(for: .microphone), state: .deny)
        await coordinator.seed(key: context.key(for: .externalScheme("mailto")), state: .allow)
        blockedStore.record(blockedPopup(context: context))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .camera))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .screenCapture))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .geolocation))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .notifications))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .storageAccess))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .filePicker))
        try await autoplayStore.setPolicy(.blockAll, for: context.mainFrameURL, profile: nil, source: .user, now: Date())

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(
                coordinator: coordinator,
                autoplayStore: autoplayStore,
                blockedPopupStore: blockedStore,
                indicatorEventStore: indicatorStore
            )
        )

        let ids = viewModel.rows.map(\.id)
        XCTAssertTrue(ids.contains("camera"))
        XCTAssertTrue(ids.contains("microphone"))
        XCTAssertTrue(ids.contains("screen-capture"))
        XCTAssertTrue(ids.contains("geolocation"))
        XCTAssertTrue(ids.contains("notifications"))
        XCTAssertTrue(ids.contains("popups"))
        XCTAssertTrue(ids.contains("external-scheme-mailto"))
        XCTAssertTrue(ids.contains("autoplay"))
        XCTAssertTrue(ids.contains("storage-access"))
        XCTAssertTrue(ids.contains("file-picker"))
        XCTAssertFalse(ids.contains("external-apps"))
        XCTAssertFalse(ids.contains("javascript"))
        XCTAssertFalse(ids.contains("images"))
        XCTAssertFalse(ids.contains("downloads"))
        XCTAssertFalse(ids.contains("ads"))
        XCTAssertFalse(ids.contains("background-sync"))
        XCTAssertFalse(ids.contains("sound"))
    }

    func testDefaultURLHubLoadHidesUnusedPermissionRows() async {
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies()
        )

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.summary.activityText)
    }

    func testAutoplayActivityPersistsAcrossRegistrableSitePages() async throws {
        let defaults = UserDefaults(suiteName: "SumiAutoplaySiteActivity-\(UUID().uuidString)")!
        let siteActivityStore = SumiPermissionSiteActivityStore(userDefaults: defaults)
        let deps = dependencies(siteActivityStore: siteActivityStore)
        let mediaContext = context(
            url: URL(string: "https://video.example.com/watch")!,
            pageId: "tab-a:media"
        )
        let rootContext = context(
            url: URL(string: "https://example.com/")!,
            pageId: "tab-a:root"
        )

        let firstViewModel = SumiCurrentSitePermissionsViewModel()
        await firstViewModel.load(
            context: mediaContext,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            autoplayInUse: true,
            dependencies: deps
        )

        let reloadedStore = SumiPermissionSiteActivityStore(userDefaults: defaults)
        let rootViewModel = SumiCurrentSitePermissionsViewModel()
        await rootViewModel.load(
            context: rootContext,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(siteActivityStore: reloadedStore)
        )

        let autoplay = try XCTUnwrap(rootViewModel.rows.first { $0.id == "autoplay" })
        XCTAssertEqual(autoplay.currentOption, .default)
        XCTAssertEqual(autoplay.subtitle, "Default")
    }

    func testDefaultURLHubLoadDoesNotRequestSystemSnapshots() async throws {
        let system = FakeSumiSystemPermissionService(states: [.camera: .denied])
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(system: system)
        )

        XCTAssertTrue(viewModel.rows.isEmpty)
        let snapshotCallCount = await system.authorizationSnapshotCallCount()
        let stateCallCount = await system.authorizationStateCallCount()
        XCTAssertEqual(snapshotCallCount, 0)
        XCTAssertEqual(stateCallCount, 0)
    }

    func testCameraWriteSemanticsResetAllowAndBlock() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        indicatorStore.record(indicatorEvent(context: context, permissionType: .camera))
        let deps = dependencies(coordinator: coordinator, indicatorEventStore: indicatorStore)

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: deps
        )
        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })

        await viewModel.select(.allow, for: camera, profile: nil, dependencies: deps)
        var record = await coordinator.record(for: context.key(for: .camera))
        XCTAssertEqual(record?.decision.state, .allow)
        XCTAssertEqual(record?.decision.persistence, .persistent)

        await viewModel.select(.block, for: camera, profile: nil, dependencies: deps)
        record = await coordinator.record(for: context.key(for: .camera))
        XCTAssertEqual(record?.decision.state, .deny)

        await viewModel.select(.ask, for: camera, profile: nil, dependencies: deps)
        record = await coordinator.record(for: context.key(for: .camera))
        XCTAssertNil(record)
    }

    func testEphemeralProfileWritesSessionDecisions() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context(isEphemeralProfile: true)
        indicatorStore.record(indicatorEvent(context: context, permissionType: .microphone))
        let deps = dependencies(coordinator: coordinator, indicatorEventStore: indicatorStore)

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: deps
        )
        let microphone = try XCTUnwrap(viewModel.rows.first { $0.id == "microphone" })

        await viewModel.select(.allow, for: microphone, profile: nil, dependencies: deps)

        let record = await coordinator.record(for: context.key(for: .microphone))
        XCTAssertEqual(record?.decision.state, .allow)
        XCTAssertEqual(record?.decision.persistence, .session)
    }

    func testExternalSchemeRowsAreSiteAndSchemeScoped() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let context = context()
        await coordinator.seed(
            key: context.key(for: .externalScheme("mailto")),
            state: .allow
        )
        await coordinator.seed(
            key: context.key(for: .externalScheme("zoommtg")),
            state: .deny
        )

        let viewModel = SumiCurrentSitePermissionsViewModel()
        let deps = dependencies(coordinator: coordinator)
        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: deps
        )

        let mailto = try XCTUnwrap(viewModel.rows.first { $0.id == "external-scheme-mailto" })
        await viewModel.select(.block, for: mailto, profile: nil, dependencies: deps)

        let mailtoRecord = await coordinator.record(for: context.key(for: .externalScheme("mailto")))
        let zoomRecord = await coordinator.record(for: context.key(for: .externalScheme("zoommtg")))
        XCTAssertEqual(mailtoRecord?.decision.state, .deny)
        XCTAssertEqual(zoomRecord?.decision.state, .deny)
    }

    func testSystemDeniedDoesNotBecomeSiteDenyOrRequestAuthorization() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let system = FakeSumiSystemPermissionService(states: [.camera: .denied])
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        indicatorStore.record(indicatorEvent(context: context, permissionType: .camera))

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(
                coordinator: coordinator,
                system: system,
                indicatorEventStore: indicatorStore
            ),
            systemSnapshotMode: .live
        )

        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })
        XCTAssertEqual(camera.currentOption, .ask)
        XCTAssertTrue(camera.showsSystemSettingsAction)
        XCTAssertTrue(camera.systemStatus?.contains("macOS settings") == true)
        let cameraRecord = await coordinator.record(for: context.key(for: .camera))
        let authorizationCallCount = await system.requestAuthorizationCallCount()
        XCTAssertNil(cameraRecord)
        XCTAssertEqual(authorizationCallCount, 0)
        let cameraSnapshotCallCount = await system.authorizationSnapshotCallCount(for: .camera)
        XCTAssertEqual(cameraSnapshotCallCount, 1)
    }

    func testRuntimeStatusUsesCurrentPageRuntimeStateWithoutChangingStoredDecision() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let runtime = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        let deps = dependencies(coordinator: coordinator, runtimeController: runtime)

        await viewModel.load(
            context: context,
            webView: WKWebView(),
            profile: nil,
            reloadRequired: false,
            dependencies: deps
        )

        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })
        let storedCameraRecord = await coordinator.record(for: context.key(for: .camera))
        XCTAssertEqual(camera.runtimeStatus, "Active")
        XCTAssertNil(storedCameraRecord)
    }

    func testOneTimeGrantShowsTemporaryStatusWithoutPersistentAllowSelection() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        await coordinator.seedTransient(
            key: context.key(for: .camera),
            state: .allow
        )

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(coordinator: coordinator)
        )

        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })
        XCTAssertEqual(camera.currentOption, .ask)
        XCTAssertEqual(camera.subtitle, "On")
    }

    func testResetClearsCurrentSitePermissionDecisionsPageEventsAndSiteActivity() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalStore = SumiExternalSchemeSessionStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let siteActivityStore = makeSiteActivityStore()
        let context = context()
        await coordinator.seed(key: context.key(for: .camera), state: .allow)
        await coordinator.seed(key: context.key(for: .popups), state: .deny)
        await coordinator.seed(key: context.key(for: .externalScheme("mailto")), state: .allow)

        blockedPopupStore.record(blockedPopup(context: context))
        indicatorStore.record(indicatorEvent(context: context, permissionType: .notifications))

        let viewModel = SumiCurrentSitePermissionsViewModel()
        let deps = dependencies(
            coordinator: coordinator,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalStore,
            indicatorEventStore: indicatorStore,
            siteActivityStore: siteActivityStore
        )
        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: deps
        )

        await viewModel.resetCurrentSite(profile: nil, dependencies: deps)

        let cameraRecord = await coordinator.record(for: context.key(for: .camera))
        let popupsRecord = await coordinator.record(for: context.key(for: .popups))
        let mailtoRecord = await coordinator.record(for: context.key(for: .externalScheme("mailto")))
        XCTAssertNil(cameraRecord)
        XCTAssertNil(popupsRecord)
        XCTAssertNil(mailtoRecord)
        XCTAssertEqual(blockedPopupStore.records(forPageId: context.pageId!).count, 0)
        XCTAssertEqual(indicatorStore.recordsSnapshot(forPageId: context.pageId!).count, 0)
        XCTAssertTrue(siteActivityStore.records(
            forSiteOf: context.origin,
            profilePartitionId: context.profilePartitionId,
            isEphemeralProfile: context.isEphemeralProfile
        ).isEmpty)
    }

    private func context(
        url: URL = URL(string: "https://example.com/path")!,
        isEphemeralProfile: Bool = false,
        pageId: String = "tab-a:1"
    ) -> SumiCurrentSitePermissionsViewModel.Context {
        let origin = SumiPermissionOrigin(url: url)
        return SumiCurrentSitePermissionsViewModel.Context(
            tabId: "tab-a",
            pageId: pageId,
            committedURL: url,
            visibleURL: url,
            mainFrameURL: url,
            origin: origin,
            profilePartitionId: "profile-a",
            isEphemeralProfile: isEphemeralProfile,
            displayDomain: "example.com",
            navigationOrPageGeneration: "1"
        )
    }

    private func dependencies(
        coordinator: CurrentSiteFakePermissionCoordinator? = nil,
        system: (any SumiSystemPermissionService)? = nil,
        runtimeController: (any SumiRuntimePermissionControlling)? = nil,
        autoplayStore: CurrentSiteFakeAutoplayStore? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        indicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
        siteActivityStore: SumiPermissionSiteActivityStore? = nil
    ) -> SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: coordinator ?? CurrentSiteFakePermissionCoordinator(),
            systemPermissionService: system ?? FakeSumiSystemPermissionService(states: [
                .camera: .authorized,
                .microphone: .authorized,
                .geolocation: .authorized,
                .notifications: .authorized,
                .screenCapture: .authorized,
            ]),
            runtimeController: runtimeController,
            autoplayStore: autoplayStore ?? CurrentSiteFakeAutoplayStore(),
            blockedPopupStore: blockedPopupStore ?? SumiBlockedPopupStore(),
            externalSchemeSessionStore: externalSchemeSessionStore ?? SumiExternalSchemeSessionStore(),
            indicatorEventStore: indicatorEventStore ?? SumiPermissionIndicatorEventStore(),
            siteActivityStore: siteActivityStore ?? makeSiteActivityStore()
        )
    }

    private func makeSiteActivityStore() -> SumiPermissionSiteActivityStore {
        SumiPermissionSiteActivityStore(
            userDefaults: UserDefaults(suiteName: "SumiCurrentSiteActivity-\(UUID().uuidString)")!
        )
    }

    private func blockedPopup(
        context: SumiCurrentSitePermissionsViewModel.Context
    ) -> SumiBlockedPopupRecord {
        SumiBlockedPopupRecord(
            id: "popup-1",
            tabId: context.tabId!,
            pageId: context.pageId!,
            requestingOrigin: context.origin,
            topOrigin: context.origin,
            targetURL: URL(string: "https://example.com/popup"),
            sourceURL: context.mainFrameURL,
            lastBlockedAt: Date(),
            reason: .blockedByDefault,
            attemptCount: 1
        )
    }

    private func indicatorEvent(
        context: SumiCurrentSitePermissionsViewModel.Context,
        permissionType: SumiPermissionType
    ) -> SumiPermissionIndicatorEventRecord {
        SumiPermissionIndicatorEventRecord(
            tabId: context.tabId!,
            pageId: context.pageId!,
            displayDomain: context.displayDomain,
            permissionTypes: [permissionType],
            category: .blockedEvent,
            visualStyle: .blocked,
            priority: .blockedNotification
        )
    }
}

private actor CurrentSiteFakePermissionCoordinator: SumiPermissionCoordinating {
    private var recordsByIdentity: [String: SumiPermissionStoreRecord] = [:]
    private var transientRecordsByIdentity: [String: SumiPermissionStoreRecord] = [:]

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .defaultSetting,
            reason: "fake",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery? {
        _ = pageId
        return nil
    }

    func stateSnapshot() async -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        recordsByIdentity.values
            .filter {
                $0.key.profilePartitionId == SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
                    && $0.key.isEphemeralProfile == isEphemeralProfile
            }
            .sorted { $0.key.permissionType.identity < $1.key.permissionType.identity }
    }

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        transientRecordsByIdentity.values
            .filter {
                $0.key.profilePartitionId == SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
                    && $0.key.transientPageId == pageId
                    && $0.decision.persistence == .oneTime
            }
            .sorted { $0.key.permissionType.identity < $1.key.permissionType.identity }
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        let decision = SumiPermissionDecision(
            state: state,
            persistence: key.isEphemeralProfile ? .session : .persistent,
            source: source,
            reason: reason
        )
        recordsByIdentity[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: key,
            decision: decision
        )
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        recordsByIdentity.removeValue(forKey: key.persistentIdentity)
    }

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws {
        for key in keys {
            recordsByIdentity.removeValue(forKey: key.persistentIdentity)
        }
    }

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    ) async -> Int {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let beforeCount = transientRecordsByIdentity.count
        transientRecordsByIdentity = transientRecordsByIdentity.filter { _, record in
            record.key.profilePartitionId != profileId
                || record.key.transientPageId != pageId
                || record.key.requestingOrigin.identity != requestingOrigin.identity
                || record.key.topOrigin.identity != topOrigin.identity
        }
        return beforeCount - transientRecordsByIdentity.count
    }

    func seed(
        key: SumiPermissionKey,
        state: SumiPermissionState
    ) {
        let decision = SumiPermissionDecision(
            state: state,
            persistence: key.isEphemeralProfile ? .session : .persistent,
            source: .user
        )
        recordsByIdentity[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: key,
            decision: decision
        )
    }

    func seedTransient(
        key: SumiPermissionKey,
        state: SumiPermissionState
    ) {
        let decision = SumiPermissionDecision(
            state: state,
            persistence: .oneTime,
            source: .user
        )
        transientRecordsByIdentity[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: key,
            decision: decision
        )
    }

    func record(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
        recordsByIdentity[key.persistentIdentity]
    }

    func cancel(
        queryId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancel(
        requestId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancel(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancelNavigation(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancelTab(
        tabId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    private func cancellationDecision(reason: String) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}

@MainActor
private final class CurrentSiteFakeAutoplayStore: SumiCurrentSiteAutoplayPolicyManaging {
    private var policiesByURL: [String: SumiAutoplayPolicy] = [:]

    func effectivePolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy {
        explicitPolicy(for: url, profile: profile) ?? .default
    }

    func explicitPolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy? {
        guard let url else { return nil }
        return policiesByURL[url.absoluteString]
    }

    func setPolicy(
        _ policy: SumiAutoplayPolicy,
        for url: URL?,
        profile: Profile?,
        source: SumiPermissionDecisionSource,
        now: Date
    ) async throws {
        _ = profile
        _ = source
        _ = now
        guard let url else { return }
        policiesByURL[url.absoluteString] = policy
    }

    func resetPolicy(for url: URL?, profile: Profile?) async throws {
        _ = profile
        guard let url else { return }
        policiesByURL.removeValue(forKey: url.absoluteString)
    }
}
