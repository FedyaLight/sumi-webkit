//
//  ContentView.swift
//  Sumi
//
//

import SwiftUI

struct ContentView: View {
    @Environment(WindowRegistry.self) private var windowRegistry
    @EnvironmentObject private var browserManager: BrowserManager

    private let windowLifecycleHandler: any BrowserWindowLifecycleHandling
    private let providedWindowState: BrowserWindowState?

    @State private var defaultWindowState: BrowserWindowState
    @StateObject private var sidebarDragState = SidebarDragState()

    init(
        windowLifecycleHandler: any BrowserWindowLifecycleHandling,
        windowState: BrowserWindowState? = nil,
        initialWorkspaceTheme: WorkspaceTheme? = nil
    ) {
        self.windowLifecycleHandler = windowLifecycleHandler
        self.providedWindowState = windowState
        _defaultWindowState = State(
            initialValue: BrowserWindowState(
                initialWorkspaceTheme: initialWorkspaceTheme,
                awaitsInitialSessionResolution: true
            )
        )
    }

    private var windowState: BrowserWindowState {
        providedWindowState ?? defaultWindowState
    }

    var body: some View {
        WindowView(
            browserContext: WindowViewBrowserContext(browserManager: browserManager),
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
                // Register this window state with the registry
                windowRegistry.register(windowState)
            }
            .onDisappear {
                guard windowRegistry.windows[windowState.id] != nil else {
                    return
                }
                windowLifecycleHandler.persistWindowSession(for: windowState)
                // Fallback for lifecycle paths that disappear without a close notification.
                windowRegistry.unregister(windowState.id)
            }
    }
}
