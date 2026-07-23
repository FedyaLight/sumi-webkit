//
//  ChromeLayoutTokens.swift
//  Sumi
//
//  Non-SwiftUI chrome spacing / metrics shared by Sidebar and CommandPalette.
//  Foundation + CoreGraphics only — color recipes stay in the app target.
//

import CoreGraphics
import Foundation

/// Layout metrics shared by app-owned sidebar and command-palette chrome.
enum ChromeLayoutTokens: Sendable {
    // MARK: - Sidebar

    /// Horizontal inset for sidebar content (`SidebarChromeMetrics` / `SpaceViewLayout`).
    static let sidebarContentHorizontalPadding: CGFloat = 8

    // MARK: - Command palette

    /// Window-edge inset for the command palette card (`CommandPaletteLayoutPolicy`).
    static let commandPaletteHorizontalPadding: CGFloat = 10
    /// Continuous corner radius for the command palette shell.
    static let commandPaletteCornerRadius: CGFloat = 26

    // MARK: - Control alphas (CGFloat; resolved colors stay in the app)

    static let chromeNavigationControlDisabledAlpha: CGFloat = 0.34
    static let popoverActionDisabledAlpha: CGFloat = 0.45
}
