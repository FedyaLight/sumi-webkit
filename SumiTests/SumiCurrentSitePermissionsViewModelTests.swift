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
        XCTAssertEqual(viewModel.summary.subtitle, "Default")
        XCTAssertFalse(viewModel.context?.isSupportedWebOrigin ?? true)
    }

    func testBuildsImplementedRowsWithoutUnsupportedContentSettings() async {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(coordinator: coordinator)
        )

        let ids = viewModel.rows.map(\.id)
        XCTAssertTrue(ids.contains("camera"))
        XCTAssertTrue(ids.contains("microphone"))
        XCTAssertTrue(ids.contains("screen-capture"))
        XCTAssertTrue(ids.contains("geolocation"))
        XCTAssertTrue(ids.contains("notifications"))
        XCTAssertTrue(ids.contains("popups"))
        XCTAssertTrue(ids.contains("external-apps"))
        XCTAssertTrue(ids.contains("autoplay"))
        XCTAssertTrue(ids.contains("storage-access"))
        XCTAssertTrue(ids.contains("file-picker"))
        XCTAssertFalse(ids.contains("javascript"))
        XCTAssertFalse(ids.contains("images"))
        XCTAssertFalse(ids.contains("downloads"))
        XCTAssertFalse(ids.contains("ads"))
        XCTAssertFalse(ids.contains("background-sync"))
        XCTAssertFalse(ids.contains("sound"))
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

        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })
        XCTAssertNil(camera.systemStatus)
        XCTAssertFalse(camera.showsSystemSettingsAction)
        let snapshotCallCount = await system.authorizationSnapshotCallCount()
        let stateCallCount = await system.authorizationStateCallCount()
        XCTAssertEqual(snapshotCallCount, 0)
        XCTAssertEqual(stateCallCount, 0)
    }

    func testCameraWriteSemanticsResetAllowAndBlock() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()
        let deps = dependencies(coordinator: coordinator)

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
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context(isEphemeralProfile: true)
        let deps = dependencies(coordinator: coordinator)

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
        let viewModel = SumiCurrentSitePermissionsViewModel()
        let context = context()

        await viewModel.load(
            context: context,
            webView: nil,
            profile: nil,
            reloadRequired: false,
            dependencies: dependencies(coordinator: coordinator, system: system),
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
        XCTAssertEqual(camera.subtitle, "Allowed this time")
    }

    func testResetClearsCurrentSitePermissionDecisionsAndPageEventsOnly() async throws {
        let coordinator = CurrentSiteFakePermissionCoordinator()
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalStore = SumiExternalSchemeSessionStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
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
            indicatorEventStore: indicatorStore
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
        XCTAssertEqual(indicatorStore.records(forPageId: context.pageId!).count, 0)
    }

    private func context(
        url: URL = URL(string: "https://example.com/path")!,
        isEphemeralProfile: Bool = false
    ) -> SumiCurrentSitePermissionsViewModel.Context {
        let origin = SumiPermissionOrigin(url: url)
        return SumiCurrentSitePermissionsViewModel.Context(
            tabId: "tab-a",
            pageId: "tab-a:1",
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
        indicatorEventStore: SumiPermissionIndicatorEventStore? = nil
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
            indicatorEventStore: indicatorEventStore ?? SumiPermissionIndicatorEventStore()
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
