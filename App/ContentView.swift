//
//  ContentView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @State private var defaultWindowState: BrowserWindowState
    @State private var commandPalette = CommandPalette()
    
    private let providedWindowState: BrowserWindowState?
    
    init(
        windowState: BrowserWindowState? = nil,
        initialWorkspaceTheme: WorkspaceTheme? = nil
    ) {
        self.providedWindowState = windowState
        _defaultWindowState = State(
            initialValue: BrowserWindowState(initialWorkspaceTheme: initialWorkspaceTheme)
        )
    }
    
    private var windowState: BrowserWindowState {
        providedWindowState ?? defaultWindowState
    }

    var body: some View {
        WindowView()
            .environment(windowState)
            .environment(commandPalette)
            .background(BrowserWindowBridge(windowState: windowState, windowRegistry: windowRegistry))
            .frame(
                minWidth: SumiBrowserWindowShellConfiguration.minimumContentSize.width,
                minHeight: SumiBrowserWindowShellConfiguration.minimumContentSize.height
            )
            .onAppear {
                // Set TabManager reference for computed properties
                windowState.tabManager = browserManager.tabManager
                // Set CommandPalette reference for global shortcuts
                windowState.commandPalette = commandPalette
                commandPalette.restore(
                    draftText: windowState.commandPaletteDraftText,
                    navigateCurrentTab: windowState.commandPaletteDraftNavigatesCurrentTab
                )
                let palette = commandPalette
                commandPalette.onStateChange = { [weak palette] changeKind in
                    guard let palette else { return }
                    windowState.isCommandPaletteVisible = palette.isVisible
                    windowState.commandPaletteDraftText = palette.prefilledText
                    windowState.commandPaletteDraftNavigatesCurrentTab = palette.shouldNavigateCurrentTab
                    switch changeKind {
                    case .draft:
                        browserManager.schedulePersistWindowSession(for: windowState)
                    case .session:
                        if palette.isVisible {
                            browserManager.dismissWorkspaceThemePickerIfNeededDiscarding()
                        }
                        browserManager.persistWindowSession(for: windowState)
                    }
                }
                // Register this window state with the registry
                windowRegistry.register(windowState)
            }
            .onDisappear {
                commandPalette.onStateChange = nil
                browserManager.persistWindowSession(for: windowState)
                // Unregister this window state when the window closes
                windowRegistry.unregister(windowState.id)
            }
    }
}
