import Foundation

enum BrowserApplicationReopenPolicy {
    static func shouldCreateNewWindow(
        hasVisibleWindows: Bool,
        hasOpenBrowserWindows: Bool
    ) -> Bool {
        hasVisibleWindows == false && hasOpenBrowserWindows == false
    }
}
