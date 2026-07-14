//
//  ContentView.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

struct ContentView: View {
    @Environment(WindowRegistry.self) private var windowRegistry

    private let windowLifecycleHandler: any BrowserWindowLifecycleHandling
    private let browserContext: WindowViewBrowserContext
    private let updaterService: SumiUpdaterService
    private let providedWindowState: BrowserWindowState?

    @State private var defaultWindowState: BrowserWindowState
    @StateObject private var sidebarDragState = SidebarDragState()

    init(
        windowLifecycleHandler: any BrowserWindowLifecycleHandling,
        browserContext: WindowViewBrowserContext,
        updaterService: SumiUpdaterService,
        windowState: BrowserWindowState? = nil,
        initialWorkspaceTheme: WorkspaceTheme? = nil
    ) {
        self.windowLifecycleHandler = windowLifecycleHandler
        self.browserContext = browserContext
        self.updaterService = updaterService
        self.providedWindowState = windowState
        _defaultWindowState = State(
            initialValue: BrowserWindowState(
                initialWorkspaceTheme: initialWorkspaceTheme,
                awaitsInitialSessionResolution: true,
                sidebarRecoveryCoordinator: browserContext.sidebarHostRecoveryCoordinator
            )
        )
    }

    private var windowState: BrowserWindowState {
        providedWindowState ?? defaultWindowState
    }

    var body: some View {
        WindowView(
            browserContext: browserContext,
            updaterService: updaterService,
            sidebarDragState: sidebarDragState
        )
            .environment(windowState)
            .background(BrowserWindowBridge(windowState: windowState, windowRegistry: windowRegistry))
            .frame(
                minWidth: SumiBrowserWindowShellConfiguration.minimumContentSize.width,
                minHeight: SumiBrowserWindowShellConfiguration.minimumContentSize.height
            )
            .onAppear {
                StartupPerformanceTrace.firstWindowVisible()
                windowState.tabManager = windowLifecycleHandler.tabManager
                guard providedWindowState == nil else { return }
                windowRegistry.register(windowState)
            }
            .onDisappear {
                guard providedWindowState == nil else { return }
                guard windowRegistry.windows[windowState.id] != nil else {
                    return
                }
                windowLifecycleHandler.persistWindowSession(for: windowState)
                // Fallback for lifecycle paths that disappear without a close notification.
                windowRegistry.unregister(windowState.id)
            }
    }
}
