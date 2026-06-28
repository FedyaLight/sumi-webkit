import CoreGraphics

struct GlanceOverlayLayout {
    enum Metrics {
        static let webAreaVerticalInset: CGFloat = 12
        static let minimumContentWidth: CGFloat = 320
        static let contentWidthFraction: CGFloat = 0.8
        static let glanceShadowOpacity: Float = 0.22
        static let glanceShadowRadius: CGFloat = 24
        static let glanceShadowOffset = CGSize(width: 0, height: -6)
        static let actionButtonSize: CGFloat = 32
        static let actionButtonSpacing: CGFloat = 12
        static let actionStackWidth: CGFloat = 44
        static let actionButtonHitOutset: CGFloat = 6
        static let actionStackTopInset: CGFloat = 15
        static let actionStackSideGap: CGFloat = 12
    }

    func targetContentFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        let webArea = webAreaFrame(in: bounds, configuration: configuration)
        guard webArea.width > 0, webArea.height > 0 else { return .zero }

        let width = max(Metrics.minimumContentWidth, webArea.width * Metrics.contentWidthFraction)
        let x = webArea.midX - width / 2
        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: webArea.minY.rounded(.toNearestOrAwayFromZero),
            width: min(width, webArea.width).rounded(.toNearestOrAwayFromZero),
            height: webArea.height.rounded(.toNearestOrAwayFromZero)
        )
    }

    func webAreaFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let horizontalInset = max(0, configuration.browserContentInset)
        var webArea = bounds.insetBy(
            dx: horizontalInset,
            dy: Metrics.webAreaVerticalInset
        )
        if configuration.isSidebarVisible {
            let sidebarWidth = min(configuration.sidebarWidth, max(0, webArea.width - 160))
            if configuration.sidebarPosition == .left {
                webArea.origin.x += sidebarWidth
                webArea.size.width -= sidebarWidth
            } else {
                webArea.size.width -= sidebarWidth
            }
        }
        return webArea
    }

    func promotionContentFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        // Match the browser viewport, not the full window: keep the visual chrome gutters
        // during promotion while avoiding an extra side gutter beside a docked sidebar.
        GlancePromotionTargetLayout.contentFrame(
            in: bounds,
            isSidebarVisible: configuration.isSidebarVisible,
            sidebarWidth: configuration.sidebarWidth,
            sidebarPosition: configuration.sidebarPosition,
            elementSeparation: configuration.browserContentInset
        )
    }

    func startContentFrame(
        originFrameInRootBounds: CGRect,
        rootBounds: CGRect,
        targetFrame: CGRect
    ) -> CGRect {
        let converted = originFrameInRootBounds.standardized
        guard converted.width > 0,
              converted.height > 0,
              rootBounds.intersects(converted)
        else {
            return clampedOriginFrame(converted, in: rootBounds, fallback: targetFrame)
        }
        return converted
    }

    func actionChromeFrame(
        for contentFrame: CGRect,
        in rootBounds: CGRect,
        buttonCount: Int,
        sidebarPosition: SidebarPosition
    ) -> CGRect {
        guard buttonCount > 0 else { return .zero }

        let buttonStackHeight = CGFloat(buttonCount) * Metrics.actionButtonSize
            + CGFloat(max(0, buttonCount - 1)) * Metrics.actionButtonSpacing
        let buttonSize = CGSize(width: Metrics.actionStackWidth, height: buttonStackHeight)
        let x: CGFloat
        if sidebarPosition == .right {
            x = max(8, contentFrame.minX - buttonSize.width - Metrics.actionStackSideGap)
        } else {
            x = min(
                rootBounds.maxX - buttonSize.width - 8,
                contentFrame.maxX + Metrics.actionStackSideGap
            )
        }
        let y = contentFrame.maxY - buttonSize.height - Metrics.actionStackTopInset
        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: max(16, y).rounded(.toNearestOrAwayFromZero),
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    func sidebarPassthroughRect(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect? {
        guard configuration.isSidebarVisible,
              configuration.sidebarWidth > 0,
              bounds.width > 0,
              bounds.height > 0
        else { return nil }

        let width = min(configuration.sidebarWidth, bounds.width)
        let x = configuration.sidebarPosition == .left
            ? bounds.minX
            : bounds.maxX - width
        return CGRect(
            x: x,
            y: bounds.minY,
            width: width,
            height: bounds.height
        )
    }

    func swiftUIContentFrame(
        _ frame: CGRect?,
        rootBoundsHeight: CGFloat,
        isRootViewFlipped: Bool
    ) -> CGRect? {
        guard let frame else {
            return nil
        }

        if isRootViewFlipped {
            return frame
        }

        return CGRect(
            x: frame.minX,
            y: rootBoundsHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func clampedOriginFrame(
        _ frame: CGRect,
        in bounds: CGRect,
        fallback: CGRect
    ) -> CGRect {
        let sourcePoint = CGPoint(
            x: frame.midX.isFinite ? frame.midX : fallback.midX,
            y: frame.midY.isFinite ? frame.midY : fallback.midY
        )
        let clampedPoint = CGPoint(
            x: min(max(sourcePoint.x, bounds.minX + 22), bounds.maxX - 22),
            y: min(max(sourcePoint.y, bounds.minY + 22), bounds.maxY - 22)
        )
        return CGRect(
            x: clampedPoint.x - 22,
            y: clampedPoint.y - 22,
            width: 44,
            height: 44
        )
    }
}

enum GlancePromotionTargetLayout {
    static func contentFrame(
        in bounds: CGRect,
        isSidebarVisible: Bool,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition,
        elementSeparation: CGFloat
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let inset = max(0, elementSeparation)
        let hasLeftSidebar = isSidebarVisible && sidebarPosition == .left
        let hasRightSidebar = isSidebarVisible && sidebarPosition == .right
        let leadingInset = hasLeftSidebar ? CGFloat.zero : inset
        let trailingInset = hasRightSidebar ? CGFloat.zero : inset

        var contentFrame = bounds
        contentFrame.origin.x += leadingInset
        contentFrame.origin.y += inset
        contentFrame.size.width -= leadingInset + trailingInset
        contentFrame.size.height -= inset * 2

        if isSidebarVisible {
            let sidebarWidth = min(max(0, sidebarWidth), max(0, contentFrame.width))
            if sidebarPosition == .left {
                contentFrame.origin.x += sidebarWidth
                contentFrame.size.width -= sidebarWidth
            } else {
                contentFrame.size.width -= sidebarWidth
            }
        }

        contentFrame.size.width = max(0, contentFrame.width)
        contentFrame.size.height = max(0, contentFrame.height)
        return contentFrame
            .standardized
            .integral
    }
}
