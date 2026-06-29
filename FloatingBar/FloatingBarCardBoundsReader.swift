//
//  FloatingBarCardBoundsReader.swift
//  Sumi
//
//

import AppKit
import SwiftUI

private final class FloatingBarCardBoundsProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct FloatingBarCardBoundsReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FloatingBarCardBoundsProbeView()
        onResolve(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onResolve(nsView)
    }
}
