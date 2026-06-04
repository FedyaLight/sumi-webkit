import AppKit

enum PopoverContentSizeAnimator {
    private static let stepCount = 12

    @MainActor
    static func animate(
        popover: NSPopover,
        from startSize: NSSize,
        to targetSize: NSSize,
        duration: TimeInterval,
        animationTask: inout Task<Void, Never>?
    ) {
        guard startSize != targetSize else {
            popover.contentSize = targetSize
            return
        }

        animationTask?.cancel()
        animationTask = Task { @MainActor [weak popover] in
            let stepDuration = duration / Double(stepCount)
            for step in 1...stepCount {
                guard !Task.isCancelled, let popover else { return }
                let rawProgress = Double(step) / Double(stepCount)
                let easedProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                popover.contentSize = NSSize(
                    width: startSize.width + (targetSize.width - startSize.width) * easedProgress,
                    height: startSize.height + (targetSize.height - startSize.height) * easedProgress
                )
                if step < stepCount {
                    try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                }
            }
            guard let popover else { return }
            popover.contentSize = targetSize
        }
    }
}
