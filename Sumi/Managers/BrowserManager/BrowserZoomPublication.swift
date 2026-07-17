@MainActor
final class BrowserZoomPublication {
    private let revision: BrowserZoomRevisionState
    private let notifications: any BrowserNotificationPresenting

    init(
        revision: BrowserZoomRevisionState,
        notifications: any BrowserNotificationPresenting
    ) {
        self.revision = revision
        self.notifications = notifications
    }

    func publishChange() {
        revision.publishChange()
    }

    func publish(
        tabID: UUID,
        in window: BrowserWindowState,
        manager: ZoomManager,
        showNotification: Bool,
        commands: BrowserZoomCommandOwner
    ) {
        revision.publishChange()
        guard showNotification else { return }
        notifications.presentNotification(
            .zoom(
                percentage: manager.getZoomPercentageDisplay(for: tabID),
                isAtMinimum: manager.isAtMinimumZoom(for: tabID),
                isAtMaximum: manager.isAtMaximumZoom(for: tabID),
                zoomOut: { [weak commands, weak window] in
                    guard let window else { return }
                    commands?.zoomOutCurrentTab(in: window)
                },
                resetZoom: { [weak commands, weak window] in
                    guard let window else { return }
                    commands?.resetZoomCurrentTab(in: window)
                },
                zoomIn: { [weak commands, weak window] in
                    guard let window else { return }
                    commands?.zoomInCurrentTab(in: window)
                }
            ),
            in: window
        )
    }
}
