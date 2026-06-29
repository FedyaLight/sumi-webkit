import Combine
import Foundation

extension Notification.Name {
    static let sumiTabLifecycleDidChange = Notification.Name("SumiTabLifecycleDidChange")
    static let sumiTabNavigationStateDidChange = Notification.Name("SumiTabNavigationStateDidChange")
    static let sumiTabLoadingStateDidChange = Notification.Name("SumiTabLoadingStateDidChange")
}

@MainActor
final class TabStateChangeEmitter {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func postLoadingStateDidChange(for tab: Tab) {
        postTabIDNotification(
            name: .sumiTabLoadingStateDidChange,
            tab: tab
        )
    }

    func postNavigationStateDidChange(for tab: Tab) {
        postTabIDNotification(
            name: .sumiTabNavigationStateDidChange,
            tab: tab
        )
    }

    func publishNavigationStateDidChange(for tab: Tab) {
        tab.objectWillChange.send()
        postNavigationStateDidChange(for: tab)
    }

    func postLifecycleDidChange(for tab: Tab) {
        notificationCenter.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
    }

    private func postTabIDNotification(
        name: Notification.Name,
        tab: Tab
    ) {
        notificationCenter.post(
            name: name,
            object: tab,
            userInfo: ["tabId": tab.id]
        )
    }
}
