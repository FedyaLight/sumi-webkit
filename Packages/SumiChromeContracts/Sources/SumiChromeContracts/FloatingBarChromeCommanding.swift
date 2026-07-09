//
//  FloatingBarChromeCommanding.swift
//  SumiChromeContracts
//
//  Chrome Views must depend on this protocol (or siblings) instead of
//  BrowserManager. App-target adapters will conform and forward commands.
//

import Foundation

/// Commands the floating bar chrome may issue without importing BrowserManager.
@MainActor
public protocol FloatingBarChromeCommanding: AnyObject {
    /// Submit a navigation or search query from the floating bar.
    func submitFloatingBarQuery(_ query: String)

    /// Dismiss the floating bar UI for the active window.
    func dismissFloatingBar()
}
