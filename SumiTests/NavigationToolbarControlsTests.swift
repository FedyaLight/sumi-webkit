import XCTest
import WebKit

@testable import Sumi

@MainActor
final class NavigationToolbarControlsTests: XCTestCase {
    func testObservableTabWrapperUsesWindowOwnedWebViewBackForwardState() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        tab.canGoBack = false
        tab.canGoForward = true
        let windowWebView = NavigationToolbarRecordingWebView(
            canGoBack: true,
            canGoForward: false
        )
        let wrapper = ObservableTabWrapper()
        wrapper.setWebViewProvider { requestedTab in
            requestedTab === tab ? windowWebView : nil
        }

        wrapper.updateTab(tab)

        XCTAssertTrue(wrapper.canGoBack)
        XCTAssertFalse(wrapper.canGoForward)
    }

    func testObservableTabWrapperIgnoresTabGlobalLoadingState() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        tab.loadingState = .didStartProvisionalNavigation
        let wrapper = ObservableTabWrapper()
        wrapper.setWebViewProvider { _ in nil }

        wrapper.updateTab(tab)

        XCTAssertFalse(wrapper.isLoading)
    }

    func testObservableTabWrapperUsesWindowOwnedWebViewLoadingState() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let windowWebView = NavigationToolbarRecordingWebView(isLoading: true)
        let wrapper = ObservableTabWrapper()
        wrapper.setWebViewProvider { requestedTab in
            requestedTab === tab ? windowWebView : nil
        }

        wrapper.updateTab(tab)

        XCTAssertTrue(wrapper.isLoading)
    }


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

private final class NavigationToolbarRecordingWebView: WKWebView {
    private let canGoBackValue: Bool
    private let canGoForwardValue: Bool
    private let isLoadingValue: Bool

    init(
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false
    ) {
        canGoBackValue = canGoBack
        canGoForwardValue = canGoForward
        isLoadingValue = isLoading
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canGoBack: Bool {
        canGoBackValue
    }

    override var canGoForward: Bool {
        canGoForwardValue
    }

    override var isLoading: Bool {
        isLoadingValue
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
