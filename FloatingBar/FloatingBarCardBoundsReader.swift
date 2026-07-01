//
//  FloatingBarCardBoundsReader.swift
//  Sumi
//
//

import AppKit
import SwiftUI

private final class FloatingBarCardBoundsProbeView: NSView {
    override func hitTest(_ _: NSPoint) -> NSView? {
        nil
    }
}

struct FloatingBarCardBoundsReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = FloatingBarCardBoundsProbeView()
        onResolve(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        onResolve(nsView)
    }
}
