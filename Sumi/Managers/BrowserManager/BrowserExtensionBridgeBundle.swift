//
//  BrowserExtensionBridgeBundle.swift
//  Sumi
//
//  Phase 5A capability bag: extension ↔ browser bridge adapter.
//

import Foundation

/// Holds the extension bridge adapter so BrowserManager does not grow another
/// peer lazy for extension surface wiring.
@MainActor
final class BrowserExtensionBridgeBundle {
    let adapter: BrowserExtensionBridgeAdapter

    init(browserManager: BrowserManager) {
        self.adapter = BrowserExtensionBridgeAdapter(
            dependencies: .live(browserManager: browserManager)
        )
    }
}
