//
//  ChromeLayoutTokens.swift
//  Sumi
//
//  Non-SwiftUI chrome spacing / metrics shared by Sidebar and FloatingBar.
//  Foundation + CoreGraphics only — color recipes stay in the app target.
//

import CoreGraphics
import Foundation

/// Layout metrics shared by app-owned sidebar and floating-bar chrome.
enum ChromeLayoutTokens: Sendable {
    // MARK: - Sidebar

    /// Horizontal inset for sidebar content (`SidebarChromeMetrics` / `SpaceViewLayout`).
    static let sidebarContentHorizontalPadding: CGFloat = 8
    /// Default vertical stack spacing for empty-state chrome.
    static let sidebarEmptyStateStackSpacing: CGFloat = 16
    /// Nested text stack spacing inside empty-state chrome.
    static let sidebarEmptyStateTextSpacing: CGFloat = 8
    /// SF Symbol point size for the empty-spaces icon.
    static let sidebarEmptyStateIconPointSize: CGFloat = 48

    // MARK: - Floating bar

    /// Window-edge inset for the floating bar card (`FloatingBarLayoutPolicy`).
    static let floatingBarHorizontalPadding: CGFloat = 10
    /// Continuous corner radius for the floating bar shell.
    static let floatingBarCornerRadius: CGFloat = 26

    // MARK: - Control alphas (CGFloat; resolved colors stay in the app)

    static let chromeNavigationControlDisabledAlpha: CGFloat = 0.34
    static let popoverActionDisabledAlpha: CGFloat = 0.45
}
