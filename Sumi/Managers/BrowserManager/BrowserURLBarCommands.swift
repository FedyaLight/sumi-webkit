import AppKit
import Foundation

/// URL-bar command façade: clipboard copy and settings-surface routing.
/// Absorbs the former `BrowserURLCopyOwner` and
/// `BrowserSettingsSurfaceRoutingOwner` so BrowserManager no longer holds two
/// separate Owners for thin URL-bar-adjacent routing.
@MainActor
final class BrowserURLBarCommands {
    /// Injectable settings-surface routing for unit tests; production uses `browserManager`.
    struct SettingsSurfaceHooks {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let settingsSurfaceURL: @MainActor (SettingsTabs) -> URL
        let privacySiteSettingsSurfaceURL: @MainActor (Tab?) -> URL
        let openNativeBrowserSurface: @MainActor (SumiNativeBrowserSurfaceKind, URL, BrowserWindowState) -> Void
    }

    private weak var browserManager: BrowserManager?
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
    private let settingsSurfaceHooks: SettingsSurfaceHooks?

    init(
        browserManager: BrowserManager?,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.browserManager = browserManager
        self.notifications = notifications
        self.settingsSurfaceHooks = nil
    }

    /// Test-only entry that supplies settings-surface hooks without a BrowserManager.
    init(
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?,
        settingsSurface: SettingsSurfaceHooks
    ) {
        self.browserManager = nil
        self.notifications = notifications
        self.settingsSurfaceHooks = settingsSurface
    }

    // MARK: - URL copy

    @discardableResult
    func copyURLToPasteboard(_ urlString: String, in windowState: BrowserWindowState? = nil) -> Bool {
        let previousClipboard = Self.capturePasteboardString()
        NSPasteboard.general.clearContents()
        let didCopy = NSPasteboard.general.setString(urlString, forType: .string)
        guard didCopy else { return false }

        let undoAction = BrowserNotificationAction(label: "Undo") {
            Self.restorePasteboard(previousString: previousClipboard)
        }
        notifications()?.presentNotification(.copyURL(undo: undoAction), in: windowState)
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

    // MARK: - Settings surface

    func openSettingsTab(
        selecting pane: SettingsTabs,
        in windowState: BrowserWindowState? = nil
    ) {
        let hooks = resolvedSettingsSurfaceHooks()
        guard let windowState = windowState ?? hooks.activeWindow() else { return }
        hooks.openNativeBrowserSurface(
            .settings,
            hooks.settingsSurfaceURL(pane),
            windowState
        )
    }

    func openSiteSettingsTab(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        let hooks = resolvedSettingsSurfaceHooks()
        guard let windowState = windowState ?? hooks.activeWindow() else { return }
        let targetTab = tab ?? hooks.currentTab(windowState)

        hooks.openNativeBrowserSurface(
            .settings,
            hooks.privacySiteSettingsSurfaceURL(targetTab),
            windowState
        )
    }

    private func resolvedSettingsSurfaceHooks() -> SettingsSurfaceHooks {
        if let settingsSurfaceHooks {
            return settingsSurfaceHooks
        }
        return SettingsSurfaceHooks(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            settingsSurfaceURL: { [weak browserManager] pane in
                browserManager?.permissionSiteSettingsRoutingOwner.settingsSurfaceURL(for: pane)
                    ?? pane.settingsSurfaceURL
            },
            privacySiteSettingsSurfaceURL: { [weak browserManager] tab in
                browserManager?.permissionSiteSettingsRoutingOwner.privacySiteSettingsSurfaceURL(focusing: tab)
                    ?? SettingsTabs.privacy.settingsSurfaceURL
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState in
                browserManager?.nativeSurfaceRoutingOwner.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: windowState
                )
            }
        )
    }
}
