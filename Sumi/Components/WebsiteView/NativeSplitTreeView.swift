import AppKit

final class NativeSplitTreeView: NSSplitView, NSSplitViewDelegate {
    let path: [Int]
    var resizeHandler: (([Int], [Double]) -> Void)?
    private var storedSizes: [Double]
    private var needsStoredSizeApplication = true
    private var isApplyingStoredSizes = false
    private var lastReportedSizes: [Double] = []

    init(axis: SplitAxis, path: [Int], sizes: [Double]) {
        self.path = path
        self.storedSizes = sizes
        super.init(frame: .zero)
        isVertical = axis == .row
        dividerStyle = .thin
        wantsLayer = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        let shouldSuppressResizeReports = needsStoredSizeApplication
        if shouldSuppressResizeReports {
            isApplyingStoredSizes = true
        }
        super.layout()
        if shouldSuppressResizeReports {
            isApplyingStoredSizes = false
        }
        applyStoredSizesIfNeeded()
    }

    func updateStoredSizes(_ sizes: [Double]) {
        guard sizes.count == subviews.count else { return }
        let normalized = Self.normalizedSizes(sizes, fallbackCount: subviews.count)
        guard !normalized.isApproximatelyEqual(to: storedSizes) else { return }
        storedSizes = normalized
        needsStoredSizeApplication = true
        needsLayout = true
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingStoredSizes,
              !needsStoredSizeApplication,
              !isHidden,
              bounds.width > 0,
              bounds.height > 0
        else { return }
        let lengths = subviews.map { isVertical ? $0.frame.width : $0.frame.height }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return }
        let sizes = lengths.map { Double($0 / total) }
        guard !sizes.isApproximatelyEqual(to: lastReportedSizes) else { return }
        lastReportedSizes = sizes
        resizeHandler?(path, sizes)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMinimumPosition + 48
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMaximumPosition - 48
    }

    private func applyStoredSizesIfNeeded() {
        guard needsStoredSizeApplication, subviews.count >= 2 else { return }
        let totalLength = isVertical ? bounds.width : bounds.height
        guard totalLength > 0 else { return }

        needsStoredSizeApplication = false
        isApplyingStoredSizes = true
        let normalized = Self.normalizedSizes(storedSizes, fallbackCount: subviews.count)
        storedSizes = normalized
        lastReportedSizes = normalized
        var accumulated: CGFloat = 0
        for index in 0..<subviews.count - 1 {
            let fraction = CGFloat(normalized[index])
            accumulated += totalLength * fraction
            setPosition(accumulated, ofDividerAt: index)
        }
        isApplyingStoredSizes = false
    }

    private static func normalizedSizes(_ sizes: [Double], fallbackCount: Int) -> [Double] {
        guard sizes.count == fallbackCount, fallbackCount > 0 else {
            return Array(repeating: 1 / Double(max(1, fallbackCount)), count: max(0, fallbackCount))
        }
        let total = sizes.reduce(0) { $0 + max(0.01, $1) }
        guard total > 0 else {
            return Array(repeating: 1 / Double(fallbackCount), count: fallbackCount)
        }
        return sizes.map { max(0.01, $0) / total }
    }
}

private extension Array where Element == Double {
    func isApproximatelyEqual(to other: [Double], accuracy: Double = 0.0005) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { abs($0 - $1) <= accuracy }
    }
}
