import AppKit
import SwiftUI

@MainActor
final class BrowserWindowShellService {
    typealias ContentViewFactory = @MainActor (WindowRegistry, WebViewCoordinator, BrowserWindowState?) -> NSView
    typealias NewTabCreator = @MainActor (BrowserWindowState, String) -> Void

    struct Context {
        let windowRegistry: WindowRegistry?
        let webViewCoordinator: WebViewCoordinator?
        let permissionLifecycleController: SumiPermissionGrantLifecycleController?
        let profileManager: ProfileManager
        let tabManager: TabManager
        let makeContentView: ContentViewFactory
        let createNewTab: NewTabCreator
    }

    private var incognitoWindowIds: Set<UUID> = []

    func createNewWindow(using context: Context) {
        guard let windowRegistry = context.windowRegistry,
              let webViewCoordinator = context.webViewCoordinator
        else {
            RuntimeDiagnostics.emit(
                "⚠️ [WindowShellService] Cannot create window - missing WindowRegistry or WebViewCoordinator"
            )
            return
        }

        let newWindow = makeWindow(
            title: "Sumi",
            contentView: context.makeContentView(windowRegistry, webViewCoordinator, nil)
        )
        newWindow.makeKeyAndOrderFront(nil)
    }

    func createIncognitoWindow(using context: Context) {
        guard let windowRegistry = context.windowRegistry,
              let webViewCoordinator = context.webViewCoordinator
        else {
            RuntimeDiagnostics.emit(
                "⚠️ [WindowShellService] Cannot create incognito window - missing WindowRegistry or WebViewCoordinator"
            )
            return
        }

        let windowState = BrowserWindowState()
        windowState.isIncognito = true

        let ephemeralProfile = context.profileManager.createEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id

        let ephemeralSpace = Space(
            id: UUID(),
            name: "Incognito",
            icon: "eye.slash",
            profileId: ephemeralProfile.id
        )
        ephemeralSpace.isEphemeral = true
        windowState.ephemeralSpaces.append(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id
        windowState.tabManager = context.tabManager

        incognitoWindowIds.insert(windowState.id)

        let newWindow = makeWindow(
            title: "Incognito - Sumi",
            contentView: context.makeContentView(windowRegistry, webViewCoordinator, windowState)
        )
        windowState.window = newWindow

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        context.createNewTab(windowState, SumiSurface.emptyTabURL.absoluteString)

        newWindow.makeKeyAndOrderFront(nil)

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Created incognito window: \(windowState.id)"
        )
    }

    func closeIncognitoWindow(
        _ windowState: BrowserWindowState,
        using context: Context
    ) async {
        guard windowState.isIncognito else { return }

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Closing incognito window: \(windowState.id)"
        )

        if let coordinator = context.webViewCoordinator {
            for tab in windowState.ephemeralTabs {
                coordinator.removeAllWebViews(for: tab)
            }
        }

        for tab in windowState.ephemeralTabs {
            tab.performComprehensiveWebViewCleanup()
        }

        incognitoWindowIds.remove(windowState.id)

        let ephemeralTabs = windowState.ephemeralTabs
        let ephemeralSpaces = windowState.ephemeralSpaces
        let ephemeralProfileId = windowState.ephemeralProfile?.id.uuidString
        windowState.ephemeralTabs.removeAll()
        windowState.ephemeralSpaces.removeAll()
        windowState.currentTabId = nil

        if let ephemeralProfileId {
            context.permissionLifecycleController?.handle(
                .profileClosed(
                    profilePartitionId: ephemeralProfileId,
                    reason: "incognito-profile-close"
                )
            )
        }
        await context.profileManager.removeEphemeralProfile(for: windowState.id)

        windowState.ephemeralProfile = nil
        windowState.currentSpaceId = nil

        #if DEBUG
        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Incognito window closed. Ephemeral tabs: \(ephemeralTabs.count), spaces: \(ephemeralSpaces.count)"
        )
        #endif

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Incognito window fully closed and cleaned up: \(windowState.id)"
        )
    }

    func closeActiveWindow(in windowRegistry: WindowRegistry?) {
        windowRegistry?.activeWindow?.window?.close()
    }

    func toggleFullScreenForActiveWindow(in windowRegistry: WindowRegistry?) {
        windowRegistry?.activeWindow?.window?.toggleFullScreen(nil)
    }

    private func makeWindow(title: String, contentView: NSView) -> NSWindow {
        let window = SumiBrowserWindow(
            contentRect: NSRect(origin: .zero, size: SumiBrowserWindowShellConfiguration.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = contentView
        window.title = title
        window.applyBrowserWindowShellConfiguration(shouldApplyInitialSize: false)
        window.center()
        return window
    }
}
