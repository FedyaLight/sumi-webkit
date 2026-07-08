import Foundation

@MainActor
protocol BrowserNotificationPresenting: AnyObject {
    func presentNotification(_ notification: BrowserNotification, in windowState: BrowserWindowState?)
    func presentProfileSwitchNotification(to profile: Profile, in windowState: BrowserWindowState?)
    func presentTabClosureNotification(tabCount: Int)
    func presentTabUnloadedNotification(count: Int, in windowState: BrowserWindowState?)
    func presentSpaceRenamedNotification(name: String, in windowState: BrowserWindowState?)
    func presentBackgroundTabOpenedNotification(tabId: UUID, in windowState: BrowserWindowState)
    func presentSplitViewLimitNotification(in windowState: BrowserWindowState)
}

extension BrowserNotificationPresenting {
    func presentNotification(_ notification: BrowserNotification) {
        presentNotification(notification, in: nil)
    }

    func presentTabUnloadedNotification(count: Int) {
        presentTabUnloadedNotification(count: count, in: nil)
    }

    func presentSpaceRenamedNotification(name: String) {
        presentSpaceRenamedNotification(name: name, in: nil)
    }
}

extension BrowserNotificationPresenter: BrowserNotificationPresenting {}
