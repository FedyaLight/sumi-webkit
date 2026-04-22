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
        revealSidebarMenu(.downloads)
    }

    func showHistory() {
        revealSidebarMenu(.history)
    }

    private func revealSidebarMenu(_ section: WindowSidebarMenuSection) {
        guard let windowState = windowRegistry?.activeWindow else { return }

        windowShellService.revealSidebarMenu(
            section,
            in: windowState
        ) { [weak self] state in
            guard let self else { return }
            if self.windowRegistry?.activeWindow?.id == state.id {
                self.syncBrowserManagerSidebarCachesFromWindow(state)
            }
            self.persistWindowSession(for: state)
        }
    }

    private func makeWindowShellContext() -> BrowserWindowShellService.Context {
        BrowserWindowShellService.Context(
            windowRegistry: windowRegistry,
            webViewCoordinator: webViewCoordinator,
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
                    .environment(windowRegistry)
                    .environment(webViewCoordinator)
                    .environment(\.sumiSettings, self.sumiSettings ?? SumiSettingsService())

                return NSHostingView(rootView: contentView)
            },
            createNewTab: { [weak self] windowState, url in
                self?.createNewTab(in: windowState, url: url)
            }
        )
    }
}
