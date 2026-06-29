import XCTest

@testable import Sumi

@MainActor
final class NavigationToolbarControlsTests: XCTestCase {
    func testTabLoadingStateNotificationEmitsOnlyOnLoadingActivityChanges() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let notifications = NavigationToolbarNotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLoadingStateDidChange,
            object: tab,
            queue: nil
        ) { notification in
            notifications.append(notification)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        tab.loadingState = .idle
        tab.loadingState = .didStartProvisionalNavigation
        tab.loadingState = .didStartProvisionalNavigation
        tab.loadingState = .didCommit
        tab.loadingState = .didCommit
        tab.loadingState = .idle

        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(
            notifications.tabIds,
            [tab.id, tab.id]
        )
    }

    func testReloadButtonModelSwitchesBetweenRefreshAndStop() {
        let idle = SumiNavigationToolbarControlState(
            canGoBack: false,
            canGoForward: false,
            canReload: true,
            isLoading: false
        )
        XCTAssertEqual(idle.reloadAssetName, "Refresh")
        XCTAssertEqual(idle.reloadAccessibilityTitle, "Reload")
        XCTAssertEqual(idle.reloadTooltip, "Reload")

        let loading = SumiNavigationToolbarControlState(
            canGoBack: false,
            canGoForward: false,
            canReload: true,
            isLoading: true
        )
        XCTAssertEqual(loading.reloadAssetName, "Stop")
        XCTAssertEqual(loading.reloadAccessibilityTitle, "Stop")
        XCTAssertEqual(loading.reloadTooltip, "Stop loading")
    }

}

private final class NavigationToolbarNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Notification] = []

    func append(_ notification: Notification) {
        lock.withLock {
            values.append(notification)
        }
    }

    var count: Int {
        lock.withLock { values.count }
    }

    var tabIds: [UUID] {
        lock.withLock {
            values.compactMap { $0.userInfo?["tabId"] as? UUID }
        }
    }
}
