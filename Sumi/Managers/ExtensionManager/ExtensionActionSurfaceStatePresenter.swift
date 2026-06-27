import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionActionSurfaceStatePresenter {
    struct Update {
        let extensionID: String
        let state: BrowserExtensionActionSurfaceState
    }

    static func makeUpdate(
        for action: WKWebExtension.Action,
        extensionID: String?
    ) -> Update? {
        guard let extensionID else { return nil }

        return Update(
            extensionID: extensionID,
            state: BrowserExtensionActionSurfaceState(
                extensionID: extensionID,
                label: action.label,
                badgeText: action.badgeText,
                hasUnreadBadgeText: action.hasUnreadBadgeText,
                isEnabled: action.isEnabled,
                presentsPopup: action.presentsPopup,
                icon: action.icon(for: CGSize(width: 18, height: 18))
            )
        )
    }

    static func actionForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab?,
        currentTab: () -> Tab?,
        stableAdapter: (Tab) -> ExtensionTabAdapter?
    ) -> WKWebExtension.Action? {
        let tab = preferredTab ?? currentTab()
        let adapter = tab.flatMap { stableAdapter($0) }
        return extensionContext.action(for: adapter)
    }
}
