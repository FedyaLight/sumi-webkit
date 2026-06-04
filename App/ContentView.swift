//
//  ContentView.swift
//  Sumi
//
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @State private var defaultWindowState: BrowserWindowState
    
    private let providedWindowState: BrowserWindowState?
    
    init(
        windowState: BrowserWindowState? = nil,
        initialWorkspaceTheme: WorkspaceTheme? = nil
    ) {
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
        WindowView()
            .environment(windowState)
            .background(BrowserWindowBridge(windowState: windowState, windowRegistry: windowRegistry))
            .frame(
                minWidth: SumiBrowserWindowShellConfiguration.minimumContentSize.width,
                minHeight: SumiBrowserWindowShellConfiguration.minimumContentSize.height
            )
            .onAppear {
                StartupPerformanceTrace.firstWindowVisible()
                // Set TabManager reference for computed properties
                windowState.tabManager = browserManager.tabManager
                // Register this window state with the registry
                windowRegistry.register(windowState)
            }
            .onDisappear {
                guard windowRegistry.windows[windowState.id] != nil else {
                    return
                }
                browserManager.persistWindowSession(for: windowState)
                // Fallback for lifecycle paths that disappear without a close notification.
                windowRegistry.unregister(windowState.id)
            }
    }
}
