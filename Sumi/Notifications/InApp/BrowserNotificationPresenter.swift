import Foundation
import SumiDomain

/// Presents transient in-app notifications in the target (or active) window,
/// honoring the user's browser notification visibility setting.
@MainActor
final class BrowserNotificationPresenter {
    private let showInAppNotifications: @MainActor () -> Bool
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let undoCloseTabShortcut: @MainActor () -> String?
    private let undoCloseTab: @MainActor () -> Void
    private let tabForId: @MainActor (UUID) -> Tab?
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        showInAppNotifications: @escaping @MainActor () -> Bool,
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        undoCloseTabShortcut: @escaping @MainActor () -> String?,
        undoCloseTab: @escaping @MainActor () -> Void,
        tabForId: @escaping @MainActor (UUID) -> Tab?,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.showInAppNotifications = showInAppNotifications
        self.activeWindow = activeWindow
        self.undoCloseTabShortcut = undoCloseTabShortcut
        self.undoCloseTab = undoCloseTab
        self.tabForId = tabForId
        self.selectTab = selectTab
    }

    convenience init(browserManager: BrowserManager) {
        let membership = browserManager
            .tabCollectionMembershipOwner
        self.init(
            showInAppNotifications: { [weak browserManager] in
                browserManager?.sumiSettings?.showInAppNotifications != false
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry.activeWindow
            },
            undoCloseTabShortcut: { [weak browserManager] in
                browserManager?.keyboardShortcutManager?.shortcutDisplayString(for: .undoCloseTab)
            },
            undoCloseTab: { [weak browserManager] in
                browserManager?.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()
            },
            tabForId: { [membership] tabId in
                membership.tab(for: tabId)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }

    func presentNotification(
        _ notification: BrowserNotification,
        in windowState: BrowserWindowState? = nil
    ) {
        guard showInAppNotifications() else { return }
        guard let targetWindow = windowState ?? activeWindow() else { return }
        targetWindow.inAppNotifications.present(notification)
    }

    func presentProfileSwitchNotification(to profile: Profile, in windowState: BrowserWindowState?) {
        presentNotification(.profileSwitch(profileName: profile.name), in: windowState)
    }

    func presentTabClosureNotification(tabCount: Int) {
        let undoCloseTabAction = undoCloseTab
        let undoAction = BrowserNotificationAction(label: "Undo") {
            undoCloseTabAction()
        }
        let shortcut = undoCloseTabShortcut()
        presentNotification(
            .tabClosure(
                count: tabCount,
                undoShortcut: shortcut,
                action: undoAction
            )
        )
    }

    func presentTabUnloadedNotification(count: Int, in windowState: BrowserWindowState? = nil) {
        presentNotification(.tabUnloaded(count: count), in: windowState)
    }

    func presentSplitViewClosureNotification(
        tabCount: Int,
        in windowState: BrowserWindowState? = nil
    ) {
        let undoCloseTabAction = undoCloseTab
        let undoAction = BrowserNotificationAction(label: "Undo") {
            undoCloseTabAction()
        }
        presentNotification(
            .splitViewClosure(
                tabCount: tabCount,
                undoShortcut: undoCloseTabShortcut(),
                action: undoAction
            ),
            in: windowState
        )
    }

    func presentSplitViewUnloadedNotification(
        tabCount: Int,
        in windowState: BrowserWindowState? = nil
    ) {
        presentNotification(
            .splitViewUnloaded(tabCount: tabCount),
            in: windowState
        )
    }

    func presentSavedTabDeletionNotification(
        tabCount: Int,
        in windowState: BrowserWindowState? = nil
    ) {
        presentNotification(
            .savedTabDeletion(
                count: tabCount,
                undoShortcut: undoCloseTabShortcut(),
                action: deletionUndoAction(itemCount: tabCount)
            ),
            in: windowState
        )
    }

    func presentSavedSplitViewDeletionNotification(
        tabCount: Int,
        in windowState: BrowserWindowState? = nil
    ) {
        presentNotification(
            .savedSplitViewDeletion(
                tabCount: tabCount,
                undoShortcut: undoCloseTabShortcut(),
                action: deletionUndoAction(itemCount: tabCount)
            ),
            in: windowState
        )
    }

    func presentSpaceRenamedNotification(name: String, in windowState: BrowserWindowState? = nil) {
        presentNotification(.spaceRenamed(name: name), in: windowState)
    }

    func presentBackgroundTabOpenedNotification(
        tabId: UUID,
        in windowState: BrowserWindowState
    ) {
        let tabForIdAction = tabForId
        let selectTabAction = selectTab
        let openAction = BrowserNotificationAction(label: "Open") {
            guard let tab = tabForIdAction(tabId) else { return }
            selectTabAction(tab, windowState)
        }
        presentNotification(.backgroundTabOpened(openAction: openAction), in: windowState)
    }

    func presentSplitViewLimitNotification(in windowState: BrowserWindowState) {
        presentNotification(.splitViewLimit(maximumPanes: SplitGroup.maximumMembers), in: windowState)
    }

    private func deletionUndoAction(
        itemCount: Int
    ) -> BrowserNotificationAction {
        let undoCloseTabAction = undoCloseTab
        return BrowserNotificationAction(label: "Undo") {
            for _ in 0..<itemCount {
                undoCloseTabAction()
            }
        }
    }
}
