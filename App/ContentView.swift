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
    private let webContentContext: WindowWebContentContext
    private let sidebarContext: WindowSidebarContext
    private let floatingBarContext: FloatingBarBrowserContext
    private let nativeModalContext: WindowNativeModalContext
    private let findContext: WindowFindContext
    private let splitContext: WindowSplitContext
    private let themeChromeContext: WindowThemeChromeContext
    private let providedWindowState: BrowserWindowState?

    @State private var defaultWindowState: BrowserWindowState
    @StateObject private var sidebarDragState: SidebarDragState

    init(
        windowLifecycleHandler: any BrowserWindowLifecycleHandling,
        webContentContext: WindowWebContentContext,
        sidebarContext: WindowSidebarContext,
        floatingBarContext: FloatingBarBrowserContext,
        nativeModalContext: WindowNativeModalContext,
        findContext: WindowFindContext,
        splitContext: WindowSplitContext,
        themeChromeContext: WindowThemeChromeContext,
        windowState: BrowserWindowState? = nil,
        initialWorkspaceTheme: WorkspaceTheme? = nil
    ) {
        self.windowLifecycleHandler = windowLifecycleHandler
        self.webContentContext = webContentContext
        self.sidebarContext = sidebarContext
        self.floatingBarContext = floatingBarContext
        self.nativeModalContext = nativeModalContext
        self.findContext = findContext
        self.splitContext = splitContext
        self.themeChromeContext = themeChromeContext
        self.providedWindowState = windowState
        let defaultWindowState = BrowserWindowState(
            initialWorkspaceTheme: initialWorkspaceTheme,
            awaitsInitialSessionResolution: true,
            sidebarRecoveryCoordinator: sidebarContext.hostRecoveryCoordinator
        )
        _defaultWindowState = State(initialValue: defaultWindowState)
        _sidebarDragState = StateObject(
            wrappedValue: SidebarDragState(
                interactionState: (windowState ?? defaultWindowState).sidebarInteractionState
            )
        )
    }

    private var windowState: BrowserWindowState {
        providedWindowState ?? defaultWindowState
    }

    var body: some View {
        WindowView(
            webContentContext: webContentContext,
            sidebarContext: sidebarContext,
            floatingBarContext: floatingBarContext,
            nativeModalContext: nativeModalContext,
            findContext: findContext,
            splitContext: splitContext,
            themeChromeContext: themeChromeContext,
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
