import AppKit
import Foundation

/// Presents AppKit alerts against the active browser window and pins their
/// appearance to the current Space through the canonical SumiNative theme.
@MainActor
final class BrowserNativeAlertPresenter {
    private let windows: WindowRegistry
    private let settings: BrowserSettingsState

    init(
        windows: WindowRegistry,
        settings: BrowserSettingsState
    ) {
        self.windows = windows
        self.settings = settings
    }

    @discardableResult
    func presentDestructiveConfirmation(
        title: String,
        message: String,
        confirmButtonTitle: String,
        preferredWindow: NSWindow? = nil,
        onConfirm: @escaping @MainActor () -> Void
    ) -> Bool {
        let alert = Self.makeDestructiveConfirmationAlert(
            title: title,
            message: message,
            confirmButtonTitle: confirmButtonTitle
        )
        return present(alert, preferredWindow: preferredWindow) { response in
            guard response == .alertFirstButtonReturn else { return }
            onConfirm()
        }
    }

    @discardableResult
    func presentNotice(
        title: String,
        subtitle: String?,
        message: String,
        preferredWindow: NSWindow? = nil
    ) -> Bool {
        let alert = Self.makeNoticeAlert(
            title: title,
            subtitle: subtitle,
            message: message
        )
        return present(alert, preferredWindow: preferredWindow) { _ in }
    }

    static func makeDestructiveConfirmationAlert(
        title: String,
        message: String,
        confirmButtonTitle: String
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.icon = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: confirmButtonTitle
        )

        let confirmButton = alert.addButton(withTitle: confirmButtonTitle)
        confirmButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(
            withTitle: String(localized: "Cancel")
        )
        cancelButton.keyEquivalent = "\u{1b}"
        return alert
    }

    static func makeNoticeAlert(
        title: String,
        subtitle: String?,
        message: String
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = [subtitle, message]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "OK"))
        return alert
    }

    private func present(
        _ alert: NSAlert,
        preferredWindow: NSWindow?,
        completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) -> Bool {
        let windowState = windows.activeWindow
        let activeBrowserWindow = windowState.flatMap {
            windows.appKitWindow(for: $0)
        }
        let window = Self.resolvePresentationWindow(
            preferredWindow: preferredWindow,
            activeBrowserWindow: activeBrowserWindow,
            keyWindow: NSApp.keyWindow,
            mainWindow: NSApp.mainWindow
        )
        let appearanceWindowState = window.flatMap {
            windows.windowState(containing: $0)
        } ?? windowState
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: appearanceWindowState,
            settings: settings.settings
        )

        if let window {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    completion(response)
                }
            }
        } else {
            completion(alert.runModal())
        }
        return true
    }

    static func resolvePresentationWindow(
        preferredWindow: NSWindow?,
        activeBrowserWindow: NSWindow?,
        keyWindow: NSWindow?,
        mainWindow: NSWindow?
    ) -> NSWindow? {
        preferredWindow ?? activeBrowserWindow ?? keyWindow ?? mainWindow
    }
}
