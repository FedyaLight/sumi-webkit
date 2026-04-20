//
//  NSView+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSView {

    func sumi_findVisibleRectClampedToBounds() -> NSRect {
        var visibleRect = self.visibleRect

        guard !clipsToBounds, let superview else { return visibleRect }
        let frame = self.frame
        visibleRect = frame

        if superview.isFlipped != isFlipped {
            visibleRect.origin.y = superview.bounds.height - visibleRect.origin.y - visibleRect.height
        }

        visibleRect = visibleRect.intersection(superview.visibleRect)
        visibleRect.origin.x -= frame.origin.x
        visibleRect.origin.y -= frame.origin.y

        return visibleRect
    }

    func sumi_findWithMouseLocationInViewCoordinates<T>(_ point: NSPoint? = nil, body: (NSPoint) -> T?) -> T? {
        guard let window else { return nil }
        let mouseLocation = point ?? window.mouseLocationOutsideOfEventStream
        let locationInView = convert(mouseLocation, from: nil)
        return body(locationInView)
    }

    func sumi_findMouseLocationInsideBounds(_ point: NSPoint? = nil) -> NSPoint? {
        sumi_findWithMouseLocationInViewCoordinates(point) { locationInView in
            guard self.sumi_findVisibleRectClampedToBounds().contains(locationInView) else { return nil }
            return locationInView
        }
    }

    func sumi_findIsMouseLocationInsideBounds(_ point: NSPoint? = nil) -> Bool {
        sumi_findMouseLocationInsideBounds(point) != nil
    }

    func sumi_findMakeMeFirstResponder() {
        guard let window else { return }
        guard window.firstResponder !== (self as? NSControl)?.currentEditor() ?? self else { return }

        window.makeFirstResponder(self)
    }
}
