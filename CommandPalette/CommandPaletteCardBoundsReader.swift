//
//  CommandPaletteCardBoundsReader.swift
//  Sumi
//
//

import AppKit
import SwiftUI

private final class CommandPaletteCardBoundsProbeView: NSView {
    override func hitTest(_ _: NSPoint) -> NSView? {
        nil
    }
}

struct CommandPaletteCardBoundsReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = CommandPaletteCardBoundsProbeView()
        onResolve(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        onResolve(nsView)
    }
}
