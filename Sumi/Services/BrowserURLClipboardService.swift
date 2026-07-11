import AppKit

@MainActor
final class BrowserURLClipboardService {
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.notifications = notifications
    }

    @discardableResult
    func copy(_ urlString: String, in windowState: BrowserWindowState?) -> Bool {
        let previousClipboard = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        let didCopy = NSPasteboard.general.setString(urlString, forType: .string)
        guard didCopy else { return false }

        let undoAction = BrowserNotificationAction(label: "Undo") {
            NSPasteboard.general.clearContents()
            if let previousClipboard {
                NSPasteboard.general.setString(previousClipboard, forType: .string)
            }
        }
        notifications()?.presentNotification(.copyURL(undo: undoAction), in: windowState)
        return true
    }
}
