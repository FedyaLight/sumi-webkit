import Foundation

/// Presents transient in-app notifications in the target (or active) window,
/// honoring the user's browser notification visibility setting.
@MainActor
final class BrowserNotificationPresenter {
    struct Dependencies {
        let showInAppNotifications: @MainActor () -> Bool
        let activeWindow: @MainActor () -> BrowserWindowState?
        let undoCloseTabShortcut: @MainActor () -> String?
        let undoCloseTab: @MainActor () -> Void
        let tabForId: @MainActor (UUID) -> Tab?
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func presentNotification(
        _ notification: BrowserNotification,
        in windowState: BrowserWindowState? = nil
    ) {
        guard dependencies.showInAppNotifications() else { return }
        guard let targetWindow = windowState ?? dependencies.activeWindow() else { return }
        targetWindow.inAppNotifications.present(notification)
    }

    func presentProfileSwitchNotification(to profile: Profile, in windowState: BrowserWindowState?) {
        presentNotification(.profileSwitch(profileName: profile.name), in: windowState)
    }

    func presentTabClosureNotification(tabCount: Int) {
        let undoAction = BrowserNotificationAction(label: "Undo") { [dependencies] in
            dependencies.undoCloseTab()
        }
        let shortcut = dependencies.undoCloseTabShortcut()
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

    func presentSpaceRenamedNotification(name: String, in windowState: BrowserWindowState? = nil) {
        presentNotification(.spaceRenamed(name: name), in: windowState)
    }

    func presentBackgroundTabOpenedNotification(
        tabId: UUID,
        in windowState: BrowserWindowState
    ) {
        let openAction = BrowserNotificationAction(label: "Open") { [dependencies] in
            guard let tab = dependencies.tabForId(tabId) else { return }
            dependencies.selectTab(tab, windowState)
        }
        presentNotification(.backgroundTabOpened(openAction: openAction), in: windowState)
    }

    func presentSplitViewLimitNotification(in windowState: BrowserWindowState) {
        presentNotification(.splitViewLimit(maximumPanes: SplitGroup.maximumTabs), in: windowState)
    }
}

extension BrowserNotificationPresenter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            showInAppNotifications: { [weak browserManager] in
                browserManager?.sumiSettings?.showInAppNotifications != false
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            undoCloseTabShortcut: { [weak browserManager] in
                browserManager?.keyboardShortcutManager?.shortcutDisplayString(for: .undoCloseTab)
            },
            undoCloseTab: { [weak browserManager] in
                browserManager?.recentlyClosedRestoreOwner.reopenMostRecentClosedItem()
            },
            tabForId: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }
}
