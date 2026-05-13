//
//  NSView+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSView {

    func sumi_chromeVisibleRectClampedToBounds() -> NSRect {
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

    func sumi_chromeWithMouseLocationInViewCoordinates<T>(_ point: NSPoint? = nil, body: (NSPoint) -> T?) -> T? {
        guard let window else { return nil }
        let mouseLocation = point ?? window.mouseLocationOutsideOfEventStream
        let locationInView = convert(mouseLocation, from: nil)
        return body(locationInView)
    }

    func sumi_chromeMouseLocationInsideBounds(_ point: NSPoint? = nil) -> NSPoint? {
        sumi_chromeWithMouseLocationInViewCoordinates(point) { locationInView in
            guard self.sumi_chromeVisibleRectClampedToBounds().contains(locationInView) else { return nil }
            return locationInView
        }
    }

    func sumi_chromeIsMouseLocationInsideBounds(_ point: NSPoint? = nil) -> Bool {
        sumi_chromeMouseLocationInsideBounds(point) != nil
    }

    func sumi_chromeMakeMeFirstResponder() {
        guard let window else { return }
        guard window.firstResponder !== (self as? NSControl)?.currentEditor() ?? self else { return }

        window.makeFirstResponder(self)
    }

    func sumi_findVisibleRectClampedToBounds() -> NSRect {
        sumi_chromeVisibleRectClampedToBounds()
    }

    func sumi_findWithMouseLocationInViewCoordinates<T>(_ point: NSPoint? = nil, body: (NSPoint) -> T?) -> T? {
        sumi_chromeWithMouseLocationInViewCoordinates(point, body: body)
    }

    func sumi_findMouseLocationInsideBounds(_ point: NSPoint? = nil) -> NSPoint? {
        sumi_chromeMouseLocationInsideBounds(point)
    }

    func sumi_findIsMouseLocationInsideBounds(_ point: NSPoint? = nil) -> Bool {
        sumi_chromeIsMouseLocationInsideBounds(point)
    }

    func sumi_findMakeMeFirstResponder() {
        sumi_chromeMakeMeFirstResponder()
    }
}
