import AppKit
import Foundation

@MainActor
final class BrowserURLCopyOwner {
    struct Dependencies {
        let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func copyURLToPasteboard(_ urlString: String, in windowState: BrowserWindowState? = nil) -> Bool {
        let previousClipboard = Self.capturePasteboardString()
        NSPasteboard.general.clearContents()
        let didCopy = NSPasteboard.general.setString(urlString, forType: .string)
        guard didCopy else { return false }

        let undoAction = BrowserNotificationAction(label: "Undo") {
            Self.restorePasteboard(previousString: previousClipboard)
        }
        dependencies.notifications()?.presentNotification(.copyURL(undo: undoAction), in: windowState)
        return true
    }

    static func capturePasteboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func restorePasteboard(previousString: String?) {
        NSPasteboard.general.clearContents()
        if let previousString {
            NSPasteboard.general.setString(previousString, forType: .string)
        }
    }
}

extension BrowserURLCopyOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
    }
}
