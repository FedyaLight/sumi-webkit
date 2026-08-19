//
//  GlanceOverlayView.swift
//  Sumi
//
//  Native AppKit host for Zen-like Glance previews.
//

import AppKit
import SwiftUI

struct GlanceOverlayView: NSViewRepresentable {
    @EnvironmentObject private var glanceManager: GlanceManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GlanceOverlayRootView {
        let rootView = GlanceOverlayRootView(frame: .zero)
        context.coordinator.controller = GlanceOverlayController(rootView: rootView)
        return rootView
    }

    func updateNSView(_ nsView: GlanceOverlayRootView, context: Context) {
        let tokens = scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
        let configuration = GlanceOverlayConfiguration(
            isVisible: glanceManager.presentedSession(for: windowState) != nil,
            isSidebarVisible: windowState.isSidebarVisible,
            sidebarWidth: windowState.sidebarWidth,
            sidebarPosition: sumiSettings.sidebarPosition,
            cornerRadius: max(14, sumiSettings.resolvedCornerRadius(14)),
            browserContentSurfaceStyle: BrowserContentSurfaceStyle(
                themeContext: themeContext,
                settings: sumiSettings
            ),
            accentColor: Self.nsColor(tokens.accent),
            surfaceColor: Self.nsColor(tokens.floatingSurfaceBackground),
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        context.coordinator.controller?.update(
            manager: glanceManager,
            session: glanceManager.currentSession,
            phase: glanceManager.phase,
            configuration: configuration
        )
    }

    static func dismantleNSView(_ nsView: GlanceOverlayRootView, coordinator: Coordinator) {
        coordinator.controller?.tearDown()
        coordinator.controller = nil
    }

    private static func nsColor(_ color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.displayP3)
            ?? NSColor(color).usingColorSpace(.sRGB)
            ?? .controlBackgroundColor
    }

    final class Coordinator {
        var controller: GlanceOverlayController?
    }
}
