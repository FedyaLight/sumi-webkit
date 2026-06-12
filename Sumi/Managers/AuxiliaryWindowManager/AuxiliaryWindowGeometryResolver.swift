//
//  AuxiliaryWindowGeometryResolver.swift
//  Sumi
//

import AppKit
import WebKit

struct AuxiliaryWindowGeometry: Equatable {
    let contentRect: NSRect
    let screen: NSScreen?
}

@MainActor
enum AuxiliaryWindowGeometryResolver {
    static let defaultWidth: CGFloat = 420
    static let defaultHeight: CGFloat = 580
    static let minimumWidth: CGFloat = 320
    static let minimumHeight: CGFloat = 240
    static let visibleFrameScale: CGFloat = 0.85

    static func resolve(
        windowFeatures: WKWindowFeatures,
        parentWindow: NSWindow?
    ) -> AuxiliaryWindowGeometry {
        let width = CGFloat(windowFeatures.width?.doubleValue ?? Double(defaultWidth))
        let height = CGFloat(windowFeatures.height?.doubleValue ?? Double(defaultHeight))
        let origin = windowFeatures.sumiOrigin
        return resolve(
            width: width,
            height: height,
            originX: origin.map { Double($0.x) },
            originY: origin.map { Double($0.y) },
            parentWindow: parentWindow
        )
    }

    static func resolve(
        extensionFrame: CGRect,
        parentWindow: NSWindow?
    ) -> AuxiliaryWindowGeometry {
        let width = extensionFrame.width.isNaN ? defaultWidth : CGFloat(extensionFrame.width)
        let height = extensionFrame.height.isNaN ? defaultHeight : CGFloat(extensionFrame.height)
        let originX = extensionFrame.origin.x.isNaN ? nil : Double(extensionFrame.origin.x)
        let originY = extensionFrame.origin.y.isNaN ? nil : Double(extensionFrame.origin.y)
        return resolve(
            width: width,
            height: height,
            originX: originX,
            originY: originY,
            parentWindow: parentWindow
        )
    }

    static func resolveDefault(parentWindow: NSWindow?) -> AuxiliaryWindowGeometry {
        resolve(
            width: defaultWidth,
            height: defaultHeight,
            originX: nil,
            originY: nil,
            parentWindow: parentWindow
        )
    }

    private static func resolve(
        width: CGFloat,
        height: CGFloat,
        originX: Double?,
        originY: Double?,
        parentWindow: NSWindow?
    ) -> AuxiliaryWindowGeometry {
        let screen = parentWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        let clampedWidth = min(
            max(width, minimumWidth),
            max(minimumWidth, visibleFrame.width * visibleFrameScale)
        )
        let clampedHeight = min(
            max(height, minimumHeight),
            max(minimumHeight, visibleFrame.height * visibleFrameScale)
        )

        let resolvedOrigin: NSPoint
        if let originX, let originY, visibleFrame != .zero {
            let appKitY = visibleFrame.maxY - CGFloat(originY) - clampedHeight
            resolvedOrigin = NSPoint(x: CGFloat(originX), y: appKitY)
        } else if let parentWindow {
            let parentFrame = parentWindow.frame
            resolvedOrigin = NSPoint(
                x: parentFrame.midX - (clampedWidth / 2),
                y: parentFrame.midY - (clampedHeight / 2)
            )
        } else if visibleFrame != .zero {
            resolvedOrigin = NSPoint(
                x: visibleFrame.midX - (clampedWidth / 2),
                y: visibleFrame.midY - (clampedHeight / 2)
            )
        } else {
            resolvedOrigin = .zero
        }

        let clampedOrigin = clampOrigin(
            resolvedOrigin,
            size: NSSize(width: clampedWidth, height: clampedHeight),
            within: visibleFrame
        )

        return AuxiliaryWindowGeometry(
            contentRect: NSRect(
                origin: clampedOrigin,
                size: NSSize(width: clampedWidth, height: clampedHeight)
            ),
            screen: screen
        )
    }

    private static func clampOrigin(
        _ origin: NSPoint,
        size: NSSize,
        within visibleFrame: NSRect
    ) -> NSPoint {
        guard visibleFrame != .zero else { return origin }

        var x = origin.x
        var y = origin.y

        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        if x + size.width > visibleFrame.maxX {
            x = visibleFrame.maxX - size.width
        }
        if y < visibleFrame.minY {
            y = visibleFrame.minY
        }
        if y + size.height > visibleFrame.maxY {
            y = visibleFrame.maxY - size.height
        }

        return NSPoint(x: x, y: y)
    }
}
