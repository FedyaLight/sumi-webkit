import Foundation

@testable import Sumi

@MainActor
final class NotificationPresentingSpy: BrowserNotificationPresenting {
    private(set) var presentNotificationCalls: [(BrowserNotification, BrowserWindowState?)] = []
    private(set) var presentProfileSwitchNotificationCalls: [(Profile, BrowserWindowState?)] = []
    private(set) var presentTabClosureNotificationCalls: [Int] = []
    private(set) var presentTabUnloadedNotificationCalls: [(count: Int, windowState: BrowserWindowState?)] = []
    private(set) var presentSpaceRenamedNotificationCalls: [(name: String, windowState: BrowserWindowState?)] = []
    private(set) var presentBackgroundTabOpenedNotificationCalls: [(tabId: UUID, windowState: BrowserWindowState)] = []
    private(set) var presentSplitViewLimitNotificationCalls: [BrowserWindowState] = []

    func presentNotification(_ notification: BrowserNotification, in windowState: BrowserWindowState?) {
        presentNotificationCalls.append((notification, windowState))
    }

    func presentProfileSwitchNotification(to profile: Profile, in windowState: BrowserWindowState?) {
        presentProfileSwitchNotificationCalls.append((profile, windowState))
    }

    func presentTabClosureNotification(tabCount: Int) {
        presentTabClosureNotificationCalls.append(tabCount)
    }

    func presentTabUnloadedNotification(count: Int, in windowState: BrowserWindowState?) {
        presentTabUnloadedNotificationCalls.append((count, windowState))
    }

    func presentSpaceRenamedNotification(name: String, in windowState: BrowserWindowState?) {
        presentSpaceRenamedNotificationCalls.append((name, windowState))
    }

    func presentBackgroundTabOpenedNotification(tabId: UUID, in windowState: BrowserWindowState) {
        presentBackgroundTabOpenedNotificationCalls.append((tabId, windowState))
    }

    func presentSplitViewLimitNotification(in windowState: BrowserWindowState) {
        presentSplitViewLimitNotificationCalls.append(windowState)
    }
}
