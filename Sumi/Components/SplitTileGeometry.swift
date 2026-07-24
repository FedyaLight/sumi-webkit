import CoreGraphics

struct SplitTileGeometry {
    let outerRect: CGRect
    let contentRects: [CGRect]
    let materialRects: [CGRect]
    let dividerRects: [CGRect]

    static func resolve(
        in size: CGSize,
        count: Int,
        thickness: CGFloat
    ) -> SplitTileGeometry {
        let contentRects = rects(
            in: size,
            count: count,
            gap: max(0, thickness)
        )
        let materialRects = rects(in: size, count: count, gap: 0)
        let width = max(0, size.width)
        let height = max(0, size.height)
        let lineWidth = max(0, min(thickness, min(width, height)))
        let vertical = CGRect(
            x: (width - lineWidth) / 2,
            y: 0,
            width: lineWidth,
            height: height
        )
        let fullHorizontal = CGRect(
            x: 0,
            y: (height - lineWidth) / 2,
            width: width,
            height: lineWidth
        )
        let leftHorizontal = CGRect(
            x: 0,
            y: (height - lineWidth) / 2,
            width: (width + lineWidth) / 2,
            height: lineWidth
        )
        let dividers: [CGRect] = switch count {
        case 2: [vertical]
        case 3: [vertical, leftHorizontal]
        case 4: [vertical, fullHorizontal]
        default: []
        }
        return SplitTileGeometry(
            outerRect: CGRect(x: 0, y: 0, width: width, height: height),
            contentRects: contentRects,
            materialRects: materialRects,
            dividerRects: dividers
        )
    }

    private static func rects(
        in size: CGSize,
        count: Int,
        gap: CGFloat
    ) -> [CGRect] {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let halfWidth = max(0, (width - gap) / 2)
        let halfHeight = max(0, (height - gap) / 2)
        switch count {
        case 2:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: height),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: height
                ),
            ]
        case 3:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                CGRect(
                    x: 0,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: height
                ),
            ]
        case 4:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: 0,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: halfWidth + gap,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
            ]
        default:
            return count == 1
                ? [CGRect(origin: .zero, size: size)] : []
        }
    }
}
