//
//  SidebarChromeCommanding.swift
//  SumiChromeContracts
//
//  Chrome Views must depend on this protocol (or siblings) instead of
//  BrowserManager. App-target adapters will conform and forward commands.
//

import Foundation

/// Commands the sidebar chrome may issue without importing BrowserManager.
@MainActor
public protocol SidebarChromeCommanding: AnyObject {
    /// Select the space identified by `spaceID` in the active window.
    func selectSpace(id spaceID: UUID)

    /// Request a new tab in the currently selected space.
    func createTabInSelectedSpace()
}
