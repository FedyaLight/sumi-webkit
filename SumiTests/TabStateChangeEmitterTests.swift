@testable import Sumi
import Combine
import XCTest

@MainActor
final class TabStateChangeEmitterTests: XCTestCase {
    func testLoadingStateNotificationUsesTabObjectAndTabID() {
        let notificationCenter = NotificationCenter()
        let emitter = TabStateChangeEmitter(notificationCenter: notificationCenter)
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let recorder = TabStateChangeNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: .sumiTabLoadingStateDidChange,
            object: tab,
            queue: nil
        ) { notification in
            recorder.append(notification)
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        emitter.postLoadingStateDidChange(for: tab)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.firstObject === tab)
        XCTAssertEqual(recorder.firstTabID, tab.id)
    }

    func testPublishNavigationStateChangeSendsObjectWillChangeBeforeNotification() {
        let notificationCenter = NotificationCenter()
        let emitter = TabStateChangeEmitter(notificationCenter: notificationCenter)
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let events = TabStateChangeEventRecorder()
        let cancellable = tab.objectWillChange.sink {
            events.append("objectWillChange")
        }
        let observer = notificationCenter.addObserver(
            forName: .sumiTabNavigationStateDidChange,
            object: tab,
            queue: nil
        ) { _ in
            events.append("notification")
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        emitter.publishNavigationStateDidChange(for: tab)

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(events.values, ["objectWillChange", "notification"])
        }
    }

    func testLifecycleNotificationPreservesExistingPayloadShape() {
        let notificationCenter = NotificationCenter()
        let emitter = TabStateChangeEmitter(notificationCenter: notificationCenter)
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let recorder = TabStateChangeNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: tab,
            queue: nil
        ) { notification in
            recorder.append(notification)
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        emitter.postLifecycleDidChange(for: tab)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.firstObject === tab)
        XCTAssertNil(recorder.firstUserInfo)
    }
}

private final class TabStateChangeNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [Notification] = []

    func append(_ notification: Notification) {
        lock.withLock {
            notifications.append(notification)
        }
    }

    var count: Int {
        lock.withLock { notifications.count }
    }

    var firstObject: AnyObject? {
        lock.withLock { notifications.first?.object as? AnyObject }
    }

    var firstTabID: UUID? {
        lock.withLock { notifications.first?.userInfo?["tabId"] as? UUID }
    }

    var firstUserInfo: [AnyHashable: Any]? {
        lock.withLock { notifications.first?.userInfo }
    }
}

private final class TabStateChangeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock {
            events.append(event)
        }
    }

    var values: [String] {
        lock.withLock { events }
    }
}
