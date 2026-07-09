//
//  ChromeLayoutTokens.swift
//  SumiChromeTokens
//
//  Non-SwiftUI chrome spacing / metrics shared by Sidebar and FloatingBar.
//  Foundation + CoreGraphics only — color recipes stay in the app target.
//

import CoreGraphics
import Foundation

/// Shared chrome layout metrics. App SwiftUI `ChromeThemeTokens` (colors) remain
/// in the Sumi target; chrome packages and app layout helpers consume these.
public enum ChromeLayoutTokens: Sendable {
    // MARK: - Sidebar

    /// Horizontal inset for sidebar content (`SidebarChromeMetrics` / `SpaceViewLayout`).
    public static let sidebarContentHorizontalPadding: CGFloat = 8
    /// Default vertical stack spacing for empty-state chrome.
    public static let sidebarEmptyStateStackSpacing: CGFloat = 16
    /// Nested text stack spacing inside empty-state chrome.
    public static let sidebarEmptyStateTextSpacing: CGFloat = 8
    /// SF Symbol point size for the empty-spaces icon.
    public static let sidebarEmptyStateIconPointSize: CGFloat = 48

    // MARK: - Floating bar

    /// Window-edge inset for the floating bar card (`FloatingBarLayoutPolicy`).
    public static let floatingBarHorizontalPadding: CGFloat = 10
    /// Continuous corner radius for the floating bar shell.
    public static let floatingBarCornerRadius: CGFloat = 26

    // MARK: - Control alphas (CGFloat; resolved colors stay in the app)

    public static let chromeNavigationControlDisabledAlpha: CGFloat = 0.34
    public static let popoverActionDisabledAlpha: CGFloat = 0.45
}
