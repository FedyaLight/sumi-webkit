import Combine
import SwiftUI

@MainActor
struct SidebarHostActions {
    let updateSidebarWidth: (CGFloat, BrowserWindowState, Bool) -> Void
    let persistWindowSession: (BrowserWindowState) -> Void
    let dismissWorkspaceThemePickerIfNeededCommitting: () -> Void
}

@MainActor
struct SidebarHostEnvironmentContext {
    let browserContext: SidebarBrowserContext
    let hostActions: SidebarHostActions
    let structuralInvalidation: AnyPublisher<Void, Never>
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let sumiSettings: SumiSettingsService
    let nowPlayingController: SumiNativeNowPlayingController
    let resolvedThemeContext: ResolvedThemeContext
    let chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    let windowChromeSize: CGSize
    let sidebarDragState: SidebarDragState
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

    var capturesOverlayBackgroundPointerEvents: Bool {
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
            .environmentObject(context.browserContext.extensionSurfaceStore)
            .environmentObject(context.nowPlayingController)
            .environment(context.windowState)
            .environment(context.windowRegistry)
            .environmentObject(context.sidebarDragState)
            .environmentObject(context.sidebarDragState.locationTracker)
            .environment(\.sumiSettings, context.sumiSettings)
            .environment(\.resolvedThemeContext, context.resolvedThemeContext)
    }
}
