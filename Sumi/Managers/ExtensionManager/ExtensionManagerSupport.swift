//
//  ExtensionManagerSupport.swift
//  Sumi
//
//  Small support types used by ExtensionManager orchestration.
//

import AppKit
import Foundation

@available(macOS 15.5, *)
final class WeakAnchor {
    weak var view: NSView?
    weak var window: NSWindow?

    init(view: NSView?, window: NSWindow?) {
        self.view = view
        self.window = window
    }
}
