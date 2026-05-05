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

    func testScreenCapturePendingMapsCorrectlyAndSystemBlockedDecisionHidesInModel() {
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
        XCTAssertFalse(systemBlocked.isVisible)
    }

    func testSettledPermissionDecisionHidesURLBarIndicatorUnlessRuntimeIsActive() {
        let deniedDecision = coordinatorDecision(
            outcome: .denied,
            permissionTypes: [.notifications],
            reason: "denied-by-user"
        )
        let denied = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    latestEvent: .querySettled(queryId: "query-notifications", decision: deniedDecision)
                ),
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        let grantedCameraDecision = coordinatorDecision(
            outcome: .granted,
            permissionTypes: [.camera],
            reason: "approved-camera"
        )
        let inactiveCamera = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    latestEvent: .querySettled(queryId: "query-camera", decision: grantedCameraDecision)
                ),
                runtimeState: .init(camera: .none, microphone: .none),
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let activeCamera = SumiPermissionIndicatorViewModel.state(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    latestEvent: .querySettled(queryId: "query-camera", decision: grantedCameraDecision)
                ),
                runtimeState: .init(camera: .active, microphone: .none),
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertFalse(denied.isVisible)
        XCTAssertFalse(inactiveCamera.isVisible)
        XCTAssertEqual(activeCamera.category, .activeRuntime)
        XCTAssertEqual(activeCamera.primaryPermissionType, .camera)
    }

    func testBlockedPopupExternalAndLiveFilePickerEventsShowButSettledPermissionEventsHide() {
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
                externalSchemeRecords: [externalSchemeRecord(result: .blockedPromptPresenterUnavailable)],
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
        XCTAssertFalse(notification.isVisible)
        XCTAssertFalse(storage.isVisible)
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

    func testOnlyActiveRuntimeAndReloadRequiredPreferRuntimeControlsSurface() {
        let activeRuntime = indicatorState(
            runtimeState: SumiRuntimePermissionState(camera: .none, microphone: .active)
        )
        let reloadRequired = SumiPermissionIndicatorViewModel.state(
            from: .init(
                autoplayReloadRequired: true,
                displayDomain: "video.example",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )
        let blockedPopup = SumiPermissionIndicatorViewModel.state(
            from: .init(
                popupRecords: [blockedPopup()],
                displayDomain: "example.com",
                tabId: "tab-a",
                pageId: "tab-a:1"
            )
        )

        XCTAssertTrue(activeRuntime.prefersRuntimeControlsSurface)
        XCTAssertTrue(reloadRequired.prefersRuntimeControlsSurface)
        XCTAssertFalse(blockedPopup.prefersRuntimeControlsSurface)
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
        XCTAssertEqual(Set(state.relatedPermissionTypes.map(\.identity)), Set(["camera", "popups"]))
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

        XCTAssertEqual(store.recordsSnapshot(forPageId: "tab-a:1").count, 1)
        XCTAssertEqual(store.clear(pageId: "tab-a:1"), 1)
        XCTAssertTrue(store.recordsSnapshot(forPageId: "tab-a:1").isEmpty)

        store.record(indicatorEvent(pageId: "tab-a:2"))
        XCTAssertEqual(store.clear(tabId: "tab-a"), 1)
        XCTAssertTrue(store.recordsSnapshot(forPageId: "tab-a:2").isEmpty)
    }

    func testURLBarContainsExactlyOneDynamicPermissionIndicatorAnchor() throws {
        let trailingSource = try sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift")
        let permissionSource = try sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift")
        let source = trailingSource + "\n" + permissionSource
        let trailingActions = try sourceSection(
            trailingSource,
            from: "func trailingActions(for currentTab: Tab) -> some View",
            to: "func copyLinkButton(for currentTab: Tab) -> some View"
        )

        XCTAssertEqual(source.components(separatedBy: "SumiPermissionIndicatorButton(").count - 1, 1)
        XCTAssertTrue(source.contains("urlbar-permission-indicator"))
        XCTAssertTrue(trailingActions.contains("let permissionIndicatorState = permissionIndicatorDisplayState(for: currentTab)"))
        XCTAssertTrue(trailingActions.contains("if permissionIndicatorState.isVisible {"))
        XCTAssertTrue(trailingActions.contains("permissionIndicatorButton(for: currentTab, state: permissionIndicatorState)"))
        XCTAssertTrue(source.contains("permissionPromptPresenter.presentFromIndicatorClick()"))
        XCTAssertTrue(source.contains("permissionPromptPresenter.viewModel"))
        XCTAssertTrue(source.contains("prefersRuntimeControlsSurface"))
        XCTAssertTrue(source.contains("hubInitialMode = .permissions"))
        XCTAssertTrue(source.contains("isHubPresented = true"))
        XCTAssertTrue(source.contains("SumiPermissionPromptView"))
        XCTAssertFalse(source.contains(".opacity(state.isVisible ?"))
        XCTAssertFalse(source.contains(".allowsHitTesting(state.isVisible)"))
        XCTAssertFalse(source.contains(".disabled(!state.isVisible)"))
        XCTAssertFalse(source.contains("isVisible: state.isVisible"))
        XCTAssertFalse(source.contains("approveOnce("))

        let copyRange = try XCTUnwrap(trailingActions.range(of: "copyLinkButton(for: currentTab)"))
        let hubRange = try XCTUnwrap(trailingActions.range(of: "hubButton"))
        let permissionRange = try XCTUnwrap(
            trailingActions.range(of: "permissionIndicatorButton(for: currentTab, state: permissionIndicatorState)")
        )
        let zoomRange = try XCTUnwrap(trailingActions.range(of: "if showsZoomButton"))
        XCTAssertLessThan(copyRange.lowerBound, hubRange.lowerBound)
        XCTAssertLessThan(hubRange.lowerBound, permissionRange.lowerBound)
        XCTAssertLessThan(permissionRange.lowerBound, zoomRange.lowerBound)
    }

    func testPermissionChromeUsesNeutralNonAccentColors() throws {
        let permissionIndicatorSource = try sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift")
        let promptSource = try sourceFile("Sumi/Permissions/UI/SumiPermissionPromptView.swift")
        let systemStateSource = try sourceFile("Sumi/Permissions/UI/SumiPermissionPromptSystemStateView.swift")

        XCTAssertFalse(permissionIndicatorSource.contains("tokens.accent"))
        XCTAssertFalse(permissionIndicatorSource.contains("Color.orange"))
        XCTAssertFalse(promptSource.contains("tokens.accent"))
        XCTAssertFalse(promptSource.contains("Color.orange"))
        XCTAssertFalse(promptSource.contains("tokens.buttonPrimaryText"))
        XCTAssertFalse(systemStateSource.contains("Color.orange"))
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
            systemAuthorizationSnapshots: [],
            policyReasons: ["test-policy"],
            createdAt: fixedDate,
            isEphemeralProfile: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: false,
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
            lastBlockedAt: fixedDate,
            reason: .blockedByDefault,
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
            lastAttemptAt: fixedDate,
            result: result,
            reason: result.rawValue,
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

    private func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let searchRange = start.upperBound..<source.endIndex
        let end = try XCTUnwrap(source.range(of: endMarker, range: searchRange))
        return source[start.lowerBound..<end.lowerBound]
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
