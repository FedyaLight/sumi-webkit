import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionPromptPresenterTests: XCTestCase {
    func testActivePromptableQueryCreatesPromptCandidate() {
        let query = promptQuery(permissionTypes: [.screenCapture])
        let candidate = SumiPermissionPromptPresenter.candidate(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    activeQueriesByPageId: ["tab-a:1": query]
                ),
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com"
            )
        )

        XCTAssertEqual(candidate, .query(query))
    }

    func testAutoplayFilePickerAndPopupQueriesDoNotCreatePromptCandidate() {
        for permissionType in [SumiPermissionType.autoplay, .filePicker, .popups] {
            let query = promptQuery(permissionTypes: [permissionType])
            let candidate = SumiPermissionPromptPresenter.candidate(
                from: .init(
                    coordinatorState: SumiPermissionCoordinatorState(
                        activeQueriesByPageId: ["tab-a:1": query]
                    ),
                    tabId: "tab-a",
                    pageId: "tab-a:1",
                    displayDomain: "example.com"
                )
            )

            XCTAssertNil(candidate, "\(permissionType.identity) should not be prompt-driven")
        }
    }

    func testSystemBlockedEventForCurrentPageCreatesPromptCandidate() {
        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: .geolocation,
            profilePartitionId: "profile-a",
            transientPageId: "tab-a:1"
        )
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .systemBlocked,
            state: .deny,
            persistence: .session,
            source: .system,
            reason: "system",
            permissionTypes: [.geolocation],
            keys: [key],
            systemAuthorizationSnapshot: SumiSystemPermissionSnapshot(kind: .geolocation, state: .denied),
            shouldOfferSystemSettings: true
        )

        let candidate = SumiPermissionPromptPresenter.candidate(
            from: .init(
                coordinatorState: SumiPermissionCoordinatorState(
                    latestSystemBlockedEvent: .systemBlocked(decision)
                ),
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com"
            )
        )

        XCTAssertEqual(candidate, .systemBlocked(decision))
    }
}

private func promptQuery(
    permissionTypes: [SumiPermissionType],
    presentationPermissionType: SumiPermissionType? = nil
) -> SumiPermissionAuthorizationQuery {
    SumiPermissionAuthorizationQuery(
        id: "query-a",
        pageId: "tab-a:1",
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
        policyReasons: [SumiPermissionPolicyReason.allowed],
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        isEphemeralProfile: false,
        hasUserGesture: true,
        shouldOfferSystemSettings: false,
        disablesPersistentAllow: false,
        requiresSystemAuthorizationPrompt: false
    )
}
