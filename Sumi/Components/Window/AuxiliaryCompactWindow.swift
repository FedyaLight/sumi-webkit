//
//  AuxiliaryCompactWindow.swift
//  Sumi
//

import AppKit

@MainActor
final class AuxiliaryCompactWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        titlebarAppearsTransparent = false
        titleVisibility = .visible
        isMovableByWindowBackground = false
        contentMinSize = NSSize(
            width: AuxiliaryWindowGeometryResolver.minimumWidth,
            height: AuxiliaryWindowGeometryResolver.minimumHeight
        )
        collectionBehavior.insert(.fullScreenAuxiliary)
    }

    func present(shouldActivateApp: Bool) {
        if shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKeyAndOrderFront(nil)
    }
}
