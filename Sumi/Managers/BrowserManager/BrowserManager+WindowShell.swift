import AppKit
import SwiftUI

@MainActor
extension BrowserManager {
    func createNewWindow() {
        windowShellService.createNewWindow(using: makeWindowShellContext())
    }

    func createIncognitoWindow() {
        windowShellService.createIncognitoWindow(using: makeWindowShellContext())
    }

    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        await windowShellService.closeIncognitoWindow(
            windowState,
            using: makeWindowShellContext()
        )
    }

    func closeActiveWindow() {
        windowShellService.closeActiveWindow(in: windowRegistry)
    }

    func toggleFullScreenForActiveWindow() {
        windowShellService.toggleFullScreenForActiveWindow(in: windowRegistry)
    }

    func showDownloads() {
        guard let windowState = windowRegistry?.activeWindow else { return }

        downloadsPopoverPresenter.toggle(in: windowState, browserManager: self)
    }

    func showHistory() {
        openHistoryTab()
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.toggle(in: windowState, browserManager: self)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserManager: self
        )
    }

    func presentURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.present(
            in: windowState,
            browserManager: self
        )
    }

    func closeURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.close(in: windowState)
    }

    private func makeWindowShellContext() -> BrowserWindowShellService.Context {
        BrowserWindowShellService.Context(
            windowRegistry: windowRegistry,
            webViewCoordinator: webViewCoordinator,
            permissionLifecycleController: permissionLifecycleController,
            profileManager: profileManager,
            tabManager: tabManager,
            makeContentView: { [weak self] windowRegistry, webViewCoordinator, windowState in
                guard let self else { return NSView() }

                let contentView = ContentView(
                    windowState: windowState,
                    initialWorkspaceTheme: self.tabManager.currentSpace?.workspaceTheme
                )
                    .ignoresSafeArea(.all)
                    .environmentObject(self)
                    .environmentObject(self.glanceManager)
                    .environmentObject(self.extensionSurfaceStore)
                    .environment(windowRegistry)
                    .environment(webViewCoordinator)
                    .environment(\.sumiSettings, self.sumiSettings ?? SumiSettingsService())
                    .environment(\.sumiModuleRegistry, self.moduleRegistry)
                    .environment(\.sumiAdBlockingModule, self.adBlockingModule)
                    .environment(\.sumiProtectionCoordinator, self.protectionCoordinator)
                    .environment(\.sumiExtensionsModule, self.extensionsModule)
                    .environment(\.sumiUserscriptsModule, self.userscriptsModule)
                    .environment(
                        self.keyboardShortcutManager ?? KeyboardShortcutManager(installEventMonitor: false)
                    )

                return NSHostingView(rootView: contentView)
            },
            showEmptyState: { [weak self] windowState in
                self?.showEmptyState(in: windowState)
            }
        )
    }
}
