//
//  BrowserURLBarBundle.swift
//  Sumi
//
//  Phase 5A capability bag: URL bar context, floating bar, and URL-bar commands.
//

import Foundation

/// Groups URL-bar / floating-bar owners and the Phase 4C URL-bar command façade.
@MainActor
final class BrowserURLBarBundle {
    let commands: BrowserURLBarCommands
    let contextOwner: BrowserURLBarContextOwner
    let floatingBarRoutingOwner: BrowserFloatingBarRoutingOwner
    let floatingBarBrowserContextOwner: BrowserFloatingBarBrowserContextOwner
    let activePageRoutingOwner: BrowserActivePageRoutingOwner

    init(browserManager: BrowserManager) {
        self.commands = BrowserURLBarCommands(
            browserManager: browserManager,
            notifications: { [weak browserManager] in browserManager?.notificationPresenter }
        )
        self.contextOwner = BrowserURLBarContextOwner(
            dependencies: .live(browserManager: browserManager)
        )
        self.floatingBarRoutingOwner = BrowserFloatingBarRoutingOwner(
            dependencies: .live(browserManager: browserManager)
        )
        self.floatingBarBrowserContextOwner = BrowserFloatingBarBrowserContextOwner(
            dependencies: .live(browserManager: browserManager)
        )
        self.activePageRoutingOwner = BrowserActivePageRoutingOwner(
            dependencies: .live(browserManager: browserManager)
        )
    }
}
