import SwiftUI

@MainActor
struct SidebarHostEnvironmentContext {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let commandPalette: CommandPalette
    let sumiSettings: SumiSettingsService
    let resolvedThemeContext: ResolvedThemeContext
}

enum SidebarPresentationMode: Equatable {
    case docked
    case collapsedHidden
    case collapsedVisible
}

enum SidebarInputMode: Equatable {
    case dockedLayout
    case collapsedOverlay
}

struct SidebarPresentationContext: Equatable {
    let mode: SidebarPresentationMode
    let sidebarWidth: CGFloat
    let sidebarPosition: SidebarPosition

    var shellEdge: SidebarShellEdge {
        sidebarPosition.shellEdge
    }

    var isCollapsedOverlay: Bool {
        mode != .docked
    }

    var inputMode: SidebarInputMode {
        isCollapsedOverlay ? .collapsedOverlay : .dockedLayout
    }

    var showsResizeHandle: Bool {
        mode == .docked
    }

    var capturesPanelBackgroundPointerEvents: Bool {
        mode == .collapsedVisible
    }

    var allowsInteractiveWork: Bool {
        mode != .collapsedHidden
    }

    static func collapsedSidebarWidth(
        sidebarWidth: CGFloat,
        savedSidebarWidth: CGFloat
    ) -> CGFloat {
        BrowserWindowState.clampedSidebarWidth(
            max(sidebarWidth, savedSidebarWidth)
        )
    }

    static func docked(
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition = .left
    ) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .docked,
            sidebarWidth: clampedWidth,
            sidebarPosition: sidebarPosition
        )
    }

    static func collapsedHidden(
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition = .left
    ) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .collapsedHidden,
            sidebarWidth: clampedWidth,
            sidebarPosition: sidebarPosition
        )
    }

    static func collapsedVisible(
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition = .left
    ) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .collapsedVisible,
            sidebarWidth: clampedWidth,
            sidebarPosition: sidebarPosition
        )
    }
}

private struct SidebarPresentationContextKey: EnvironmentKey {
    static let defaultValue = SidebarPresentationContext.docked(
        sidebarWidth: BrowserWindowState.sidebarDefaultWidth
    )
}

extension EnvironmentValues {
    var sidebarPresentationContext: SidebarPresentationContext {
        get { self[SidebarPresentationContextKey.self] }
        set { self[SidebarPresentationContextKey.self] = newValue }
    }
}

@MainActor
extension View {
    func sidebarHostEnvironment(_ context: SidebarHostEnvironmentContext) -> some View {
        self
            .environmentObject(context.browserManager)
            .environmentObject(context.browserManager.extensionSurfaceStore)
            .environment(context.windowState)
            .environment(context.windowRegistry)
            .environment(context.commandPalette)
            .environment(\.sumiSettings, context.sumiSettings)
            .environment(\.resolvedThemeContext, context.resolvedThemeContext)
    }
}
