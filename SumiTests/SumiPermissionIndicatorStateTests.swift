import XCTest

@testable import Sumi

final class SumiPermissionIndicatorStateTests: XCTestCase {
    func testHiddenStateIsNotVisible() {
        XCTAssertFalse(SumiPermissionIndicatorState.hidden.isVisible)
        XCTAssertEqual(SumiPermissionIndicatorState.hidden.category, .hidden)
        XCTAssertNil(SumiPermissionIndicatorState.hidden.priority)
    }

    func testPendingQueryStateUsesRequestedPermissionIconAndLabels() {
        let state = SumiPermissionIndicatorState.visible(
            category: .pendingRequest,
            primaryPermissionType: .microphone,
            displayDomain: "web.telegram.org",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .pendingSensitiveRequest,
            visualStyle: .attention
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.icon.id, "microphone")
        XCTAssertEqual(state.accessibilityLabel, "Microphone access requested by web.telegram.org")
        XCTAssertEqual(state.title, "Microphone requested by web.telegram.org")
    }

    func testActiveRuntimeStatesHaveActiveStyle() {
        let camera = activeState(.camera, priority: .activeCamera)
        let microphone = activeState(.microphone, priority: .activeMicrophone)
        let geolocation = activeState(.geolocation, priority: .activeGeolocation)

        XCTAssertEqual(camera.visualStyle, .active)
        XCTAssertEqual(microphone.visualStyle, .active)
        XCTAssertEqual(geolocation.visualStyle, .active)
        XCTAssertEqual(camera.accessibilityLabel, "Camera is active on example.com")
        XCTAssertEqual(microphone.accessibilityLabel, "Microphone is active on example.com")
        XCTAssertEqual(geolocation.accessibilityLabel, "Location is active on example.com")
    }

    func testActiveCameraAndMicrophoneUsesGroupedPriorityAndBadge() {
        let state = SumiPermissionIndicatorState.visible(
            category: .activeRuntime,
            primaryPermissionType: .cameraAndMicrophone,
            relatedPermissionTypes: [.camera, .microphone],
            displayDomain: "meet.example",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .activeCameraAndMicrophone,
            visualStyle: .active,
            badgeCount: 2
        )

        XCTAssertEqual(state.icon.id, "camera-microphone.active")
        XCTAssertEqual(state.priority, .activeCameraAndMicrophone)
        XCTAssertEqual(state.badgeCount, 2)
        XCTAssertEqual(state.accessibilityLabel, "Camera and microphone are active on meet.example")
    }

    func testBlockedAndSystemBlockedStylesAreDistinct() {
        let blocked = SumiPermissionIndicatorState.visible(
            category: .blockedEvent,
            primaryPermissionType: .popups,
            displayDomain: "example.com",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .blockedPopup,
            visualStyle: .blocked
        )
        let systemBlocked = SumiPermissionIndicatorState.visible(
            category: .systemBlocked,
            primaryPermissionType: .camera,
            displayDomain: "example.com",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .systemBlockedSensitive,
            visualStyle: .systemWarning
        )

        XCTAssertEqual(blocked.visualStyle, .blocked)
        XCTAssertEqual(systemBlocked.visualStyle, .systemWarning)
        XCTAssertEqual(blocked.accessibilityLabel, "Pop-up blocked on example.com")
        XCTAssertEqual(systemBlocked.accessibilityLabel, "Camera blocked by macOS system settings for example.com")
    }

    func testReloadRequiredStateUsesAutoplayStyle() {
        let state = SumiPermissionIndicatorState.visible(
            category: .reloadRequired,
            primaryPermissionType: .autoplay,
            displayDomain: "video.example",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .autoplayReloadRequired,
            visualStyle: .reloadRequired
        )

        XCTAssertEqual(state.icon.id, "autoplay.reload-required")
        XCTAssertEqual(state.visualStyle, .reloadRequired)
        XCTAssertEqual(state.accessibilityLabel, "Autoplay change requires reload on video.example")
    }

    func testMultipleStatesChoosePriorityDeterministicallyAndBecomeMixed() {
        let popup = SumiPermissionIndicatorState.visible(
            category: .blockedEvent,
            primaryPermissionType: .popups,
            displayDomain: "example.com",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .blockedPopup,
            visualStyle: .blocked
        )
        let camera = activeState(.camera, priority: .activeCamera)

        let resolved = SumiPermissionIndicatorState.resolved(from: [popup, camera])

        XCTAssertEqual(resolved.category, .mixed)
        XCTAssertEqual(resolved.primaryPermissionType, .camera)
        XCTAssertEqual(resolved.primaryCategory, .activeRuntime)
        XCTAssertEqual(resolved.priority, .activeCamera)
        XCTAssertEqual(resolved.relatedPermissionTypes.map(\.identity), ["camera", "popups"])
        XCTAssertEqual(resolved.badgeCount, 2)
        XCTAssertEqual(resolved.accessibilityLabel, "Multiple permission states on example.com: Camera, Pop-ups")
    }

    private func activeState(
        _ permissionType: SumiPermissionType,
        priority: SumiPermissionIndicatorPriority
    ) -> SumiPermissionIndicatorState {
        SumiPermissionIndicatorState.visible(
            category: .activeRuntime,
            primaryPermissionType: permissionType,
            displayDomain: "example.com",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: priority,
            visualStyle: .active
        )
    }
}
