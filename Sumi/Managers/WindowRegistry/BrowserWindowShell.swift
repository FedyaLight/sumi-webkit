//
//  BrowserWindowShell.swift
//  Sumi
//
//  Phase 6A: AppKit NSWindow runtime handle, kept off BrowserWindowState data.
//

import AppKit
import Foundation

/// Weak AppKit window handle for a browser window id.
///
/// Owned/keyed by `WindowRegistry` as the sole SoT for AppKit window lookup.
@MainActor
final class BrowserWindowShell {
    let windowId: UUID
    weak var window: NSWindow?

    init(windowId: UUID, window: NSWindow? = nil) {
        self.windowId = windowId
        self.window = window
    }
}
