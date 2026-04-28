import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionIndicatorViewModelTests: XCTestCase {
    func testDefaultSnapshotIsHidden() {
        let state = SumiPermissionIndicatorViewModel.state(from: .init())

        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.category, .hidden)
    }

    func testCoordinatorActiveQueryDrivesPendingRequestState() {
        let query = authorizationQuery(permissionTypes: [.microphone])
        let snapshot = SumiPermissionIndicatorViewModel.SourceSnapshot(
            coordinatorState: SumiPermissionCoordinatorState(
                activeQueriesByPageId: ["tab-a:1": query],
                queueCountByPageId: ["tab-a:1": 1]
            ),
            displayDomain: "fallback.example",
            tabId: "tab-a",
            pageId: "tab-a:1"
        )

        let state = SumiPermissionIndicatorViewModel.state(from: snapshot)

        XCTAssertEqual(state.category, .pendingRequest)
        XCTAssertEqual(state.primaryPermissionType, .microphone)
        XCTAssertEqual(state.priority, .pendingSensitiveRequest)
        XCTAssertEqual(state.badgeCount, 2)
        XCTAssertEqual(state.accessibilityLabel, "Microphone access requested by example.com")
    }

    func testActiveCameraMicrophoneAndGeolocationRuntimeStates() {
        let camera = indicatorState(runtimeState: .init(camera: .active, microphone: .none))
        let microphone = indicatorState(runtimeState: .init(camera: .none, microphone: .muted))
        let grouped = indicatorState(runtimeState: .init(camera: .active, microphone: .muted))
        let geolocation = indicatorState(
            runtimeState: .init(
                camera: .none,
                microphone: .none,
                geolocation: .paused
            )
        )

        XCTAssertEqual(camera.primaryPermissionType, .camera)
        XCTAssertEqual(camera.priority, .activeCamera)
        XCTAssertEqual(microphone.primaryPermissionType, .microphone)
        XCTAssertEqual(microphone.priority, .activeMicrophone)
        XCTAssertEqual(grouped.primaryPermissionType, .cameraAndMicrophone)
        XCTAssertEqual(grouped.priority, .activeCameraAndMicrophone)
        XCTAssertEqual(grouped.badgeCount, 2)
        XCTAssertEqual(geolocation.primaryPermissionType, .geolocation)
        XCTAssertEqual(geolocation.priority, .activeGeolocation)
    }

    func testScreenCapturePendingAndSystemBlockedMapCorrectly() {
        let pending = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    activeQueriesByPageId: [
                        "tab-a:1": authorizationQuery(permissionTypes: [.screenCapture]),
                    ]
                ),
                displayDomain: "share.example",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let systemBlockedDecision = coordinatorDecision(
            outcome: .systemBlocked,
            permissionTypes: [.screenCapture],
            reason: "screen-capture-system-denied"
        )
        let systemBlocked = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    latestSystemBlockedEvent: .systemBlocked(systemBlockedDecision)
                ),
                displayDomain: "share.example",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertEqual(pending.category, .pendingRequest)
        XCTAssertEqual(pending.primaryPermissionType, .screenCapture)
        XCTAssertEqual(systemBlocked.category, .systemBlocked)
        XCTAssertEqual(systemBlocked.visualStyle, .systemWarning)
        XCTAssertEqual(systemBlocked.priority, .systemBlockedSensitive)
    }

    func testBlockedPopupExternalNotificationStorageAndFileEvents() {
        let popup = SumiPermissionIndicatorViewModel.state(
            from: .init(
                popupRecords: [blockedPopup()],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let external = SumiPermissionIndicatorViewModel.state(
            from: .init(
                externalSchemeRecords: [externalSchemeRecord(result: .blockedPendingUI)],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let notification = SumiPermissionIndicatorViewModel.state(
            from: .init(
                indicatorEvents: [
                    indicatorEvent(
                        permissionTypes: [.notifications],
                        category: .blockedEvent,
                        visualStyle: .blocked,
                        priority: .blockedNotification
                    ),
                ],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let storage = SumiPermissionIndicatorViewModel.state(
            from: .init(
                indicatorEvents: [
                    indicatorEvent(
                        permissionTypes: [.storageAccess],
                        category: .pendingRequest,
                        visualStyle: .attention,
                        priority: .storageAccessBlockedOrPending
                    ),
                ],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let filePicker = SumiPermissionIndicatorViewModel.state(
            from: .init(
                indicatorEvents: [
                    indicatorEvent(
                        permissionTypes: [.filePicker],
                        category: .pendingRequest,
                        visualStyle: .attention,
                        priority: .filePickerCurrentEvent
                    ),
                ],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertEqual(popup.primaryPermissionType, .popups)
        XCTAssertEqual(popup.priority, .blockedPopup)
        XCTAssertEqual(external.primaryPermissionType, .externalScheme("zoommtg"))
        XCTAssertEqual(external.priority, .blockedExternalScheme)
        XCTAssertEqual(notification.primaryPermissionType, .notifications)
        XCTAssertEqual(notification.priority, .blockedNotification)
        XCTAssertEqual(storage.primaryPermissionType, .storageAccess)
        XCTAssertEqual(storage.priority, .storageAccessBlockedOrPending)
        XCTAssertEqual(filePicker.primaryPermissionType, .filePicker)
        XCTAssertEqual(filePicker.priority, .filePickerCurrentEvent)
    }

    func testAutoplayReloadRequiredMapsToReloadState() {
        let state = SumiPermissionIndicatorViewModel.state(
            from: .init(
                autoplayReloadRequired: true,
                displayDomain: "video.example",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertEqual(state.category, .reloadRequired)
        XCTAssertEqual(state.primaryPermissionType, .autoplay)
        XCTAssertEqual(state.priority, .autoplayReloadRequired)
        XCTAssertEqual(state.visualStyle, .reloadRequired)
    }

    func testMultipleSourcesChoosePriorityDeterministically() {
        let state = SumiPermissionIndicatorViewModel.state(
            from: .init(
                runtimeState: .init(camera: .active, microphone: .none),
                popupRecords: [blockedPopup()],
                indicatorEvents: [
                    indicatorEvent(
                        permissionTypes: [.notifications],
                        category: .blockedEvent,
                        visualStyle: .blocked,
                        priority: .blockedNotification
                    ),
                ],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertEqual(state.category, .mixed)
        XCTAssertEqual(state.primaryPermissionType, .camera)
        XCTAssertEqual(state.priority, .activeCamera)
        XCTAssertEqual(Set(state.relatedPermissionTypes.map(\.identity)), Set(["camera", "popups", "notifications"]))
    }

    func testCoordinatorEventsFromOtherPagesAreIgnored() {
        let query = authorizationQuery(pageId: "tab-a:2", permissionTypes: [.camera])
        let decision = coordinatorDecision(
            outcome: .systemBlocked,
            pageId: "tab-a:2",
            permissionTypes: [.camera],
            reason: "other-page"
        )

        let state = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    activeQueriesByPageId: ["tab-a:2": query],
                    latestSystemBlockedEvent: .systemBlocked(decision)
                ),
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertFalse(state.isVisible)
    }

    func testIndicatorEventStoreClearsNavigationScopedRecords() {
        let store = SumiPermissionIndicatorEventStore()
        store.record(indicatorEvent())

        XCTAssertEqual(store.records(forPageId: "tab-a:1").count, 1)
        XCTAssertEqual(store.clear(pageId: "tab-a:1"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:1").isEmpty)

        store.record(indicatorEvent(pageId: "tab-a:2"))
        XCTAssertEqual(store.clear(tabId: "tab-a"), 1)
        XCTAssertTrue(store.records(forPageId: "tab-a:2").isEmpty)
    }

    func testURLBarContainsExactlyOneDynamicPermissionIndicatorAnchor() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertEqual(source.components(separatedBy: "SumiPermissionIndicatorButton(").count - 1, 1)
        XCTAssertTrue(source.contains("urlbar-permission-indicator"))
        XCTAssertTrue(source.contains("isHubPresented = true"))
        XCTAssertFalse(source.contains("SumiPermissionPromptView"))
        XCTAssertFalse(source.contains("approveOnce("))
        XCTAssertFalse(source.contains("denyOnce("))
    }

    private func indicatorState(
        runtimeState: SumiRuntimePermissionState
    ) -> SumiPermissionIndicatorState {
        SumiPermissionIndicatorViewModel.state(
            from: .init(
                runtimeState: runtimeState,
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
    }

    private func authorizationQuery(
        pageId: String = "tab-a:1",
        permissionTypes: [SumiPermissionType],
        presentationPermissionType: SumiPermissionType? = nil
    ) -> SumiPermissionAuthorizationQuery {
        SumiPermissionAuthorizationQuery(
            id: "query-\(permissionTypes.map(\.identity).joined(separator: "-"))",
            pageId: pageId,
            profilePartitionId: "profile-a",
            displayDomain: "example.com",
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: permissionTypes,
            presentationPermissionType: presentationPermissionType,
            availablePersistences: [.oneTime, .session, .persistent],
            defaultPersistence: .oneTime,
            systemAuthorizationSnapshots: [],
            policySources: [.defaultSetting],
            policyReasons: ["test-policy"],
            createdAt: fixedDate,
            isEphemeralProfile: false,
            hasUserGesture: true,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: false,
            requiresSystemAuthorizationPrompt: false
        )
    }

    private func coordinatorDecision(
        outcome: SumiPermissionCoordinatorOutcome,
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        permissionTypes: [SumiPermissionType],
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        let request = SumiPermissionRequest(
            id: "request-\(reason)",
            tabId: tabId,
            pageId: pageId,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            displayDomain: "example.com",
            permissionTypes: permissionTypes,
            profilePartitionId: "profile-a"
        )
        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: outcome == .granted ? .allow : .deny,
            persistence: nil,
            source: outcome == .systemBlocked ? .system : .runtime,
            reason: reason,
            permissionTypes: permissionTypes,
            keys: permissionTypes.map { request.key(for: $0) },
            shouldOfferSystemSettings: outcome == .systemBlocked
        )
    }

    private func blockedPopup(
        pageId: String = "tab-a:1"
    ) -> SumiBlockedPopupRecord {
        SumiBlockedPopupRecord(
            id: "popup-a",
            tabId: "tab-a",
            pageId: pageId,
            requestingOrigin: SumiPermissionOrigin(string: "https://popup.example"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            targetURL: URL(string: "https://popup.example/window"),
            sourceURL: URL(string: "https://example.com/source"),
            createdAt: fixedDate,
            lastBlockedAt: fixedDate,
            userActivation: .none,
            reason: .blockedByDefault,
            canOpenLater: true,
            navigationActionMetadata: [:],
            attemptCount: 1
        )
    }

    private func externalSchemeRecord(
        result: SumiExternalSchemeAttemptResult,
        pageId: String = "tab-a:1"
    ) -> SumiExternalSchemeAttemptRecord {
        SumiExternalSchemeAttemptRecord(
            id: "external-a",
            tabId: "tab-a",
            pageId: pageId,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            scheme: "zoommtg",
            redactedTargetURLString: "zoommtg://open",
            appDisplayName: "Zoom",
            createdAt: fixedDate,
            lastAttemptAt: fixedDate,
            userActivation: .none,
            result: result,
            reason: result.rawValue,
            navigationActionMetadata: [:],
            attemptCount: 1
        )
    }

    private func indicatorEvent(
        pageId: String = "tab-a:1",
        permissionTypes: [SumiPermissionType] = [.notifications],
        category: SumiPermissionIndicatorCategory = .blockedEvent,
        visualStyle: SumiPermissionIndicatorVisualStyle = .blocked,
        priority: SumiPermissionIndicatorPriority = .blockedNotification
    ) -> SumiPermissionIndicatorEventRecord {
        SumiPermissionIndicatorEventRecord(
            id: "event-\(permissionTypes.map(\.identity).joined(separator: "-"))",
            tabId: "tab-a",
            pageId: pageId,
            displayDomain: "example.com",
            permissionTypes: permissionTypes,
            category: category,
            visualStyle: visualStyle,
            priority: priority,
            reason: "test",
            createdAt: fixedDate
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let testsURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
