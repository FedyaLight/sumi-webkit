import AppKit
import OSLog
import QuartzCore

@MainActor
final class PageActivationPerformanceMonitor {
    enum Residency: Equatable {
        case live
        case cold
    }

    private struct PendingActivation {
        let tabID: UUID
        let residency: Residency
        let startedAt: TimeInterval
        let interval: OSSignpostIntervalState
    }

    private static let logger = Logger.sumi(category: "PageActivation")
    private let onFirstPaint: @MainActor () -> Void
    private var pendingByWindowID: [UUID: PendingActivation] = [:]
    private var paintHooksByWindowID: [UUID: PageActivationPaintHook] = [:]
    private var timeoutsByWindowID: [UUID: DispatchWorkItem] = [:]
    private var initialPaintHook: PageActivationPaintHook?
    private var initialPaintTimeout: DispatchWorkItem?
    private var observedInitialPaint = false

    init(onFirstPaint: @escaping @MainActor () -> Void = {}) {
        self.onFirstPaint = onFirstPaint
    }

    func begin(tabID: UUID, in windowID: UUID, residency: Residency) {
        cancel(in: windowID)
        let interval = switch residency {
        case .live:
            PerformanceTrace.beginInterval("PageActivation.liveToFirstPaint")
        case .cold:
            PerformanceTrace.beginInterval("PageActivation.coldToFirstPaint")
        }
        pendingByWindowID[windowID] = PendingActivation(
            tabID: tabID,
            residency: residency,
            startedAt: CACurrentMediaTime(),
            interval: interval
        )
        let timeout = DispatchWorkItem { [weak self] in
            self?.cancel(in: windowID)
        }
        timeoutsByWindowID[windowID] = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2,
            execute: timeout
        )
    }

    func hostDidAttach(
        tabID: UUID,
        in windowID: UUID,
        window: NSWindow?
    ) {
        let hasPendingActivation =
            pendingByWindowID[windowID]?.tabID == tabID
        if hasPendingActivation == false {
            observeInitialPaintIfNeeded(window: window)
        }
        guard hasPendingActivation,
              paintHooksByWindowID[windowID] == nil
        else {
            return
        }

        CATransaction.flush()
        let hook = PageActivationPaintHook(window: window) { [weak self] frameTime in
            self?.finish(in: windowID, frameTime: frameTime)
        }
        paintHooksByWindowID[windowID] = hook
        if hook.start() == false {
            paintHooksByWindowID[windowID] = nil
            DispatchQueue.main.async { [weak self] in
                self?.finish(
                    in: windowID,
                    frameTime: CACurrentMediaTime()
                )
            }
        }
    }

    func cancel(in windowID: UUID) {
        timeoutsByWindowID.removeValue(forKey: windowID)?.cancel()
        paintHooksByWindowID.removeValue(forKey: windowID)?.stop()
        guard let pending = pendingByWindowID.removeValue(forKey: windowID) else {
            return
        }
        endInterval(for: pending)
    }

    private func finish(in windowID: UUID, frameTime: TimeInterval) {
        timeoutsByWindowID.removeValue(forKey: windowID)?.cancel()
        paintHooksByWindowID.removeValue(forKey: windowID)?.stop()
        guard let pending = pendingByWindowID.removeValue(forKey: windowID) else {
            return
        }
        endInterval(for: pending)

        let milliseconds = max(0, frameTime - pending.startedAt) * 1_000
        let residency = pending.residency == .live ? "live" : "cold"
        Self.logger.debug(
            "First paint residency=\(residency, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 2), privacy: .public)"
        )
        publishPaintObservation()
    }

    private func observeInitialPaintIfNeeded(window: NSWindow?) {
        guard observedInitialPaint == false, initialPaintHook == nil else {
            return
        }
        CATransaction.flush()
        let hook = PageActivationPaintHook(window: window) { [weak self] _ in
            self?.publishPaintObservation()
        }
        initialPaintHook = hook
        if hook.start() == false {
            initialPaintHook = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, observedInitialPaint == false else {
                    return
                }
                publishPaintObservation()
            }
        } else {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, observedInitialPaint == false else {
                    return
                }
                publishPaintObservation()
            }
            initialPaintTimeout = timeout
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 2,
                execute: timeout
            )
        }
    }

    private func publishPaintObservation() {
        initialPaintTimeout?.cancel()
        initialPaintTimeout = nil
        initialPaintHook?.stop()
        initialPaintHook = nil
        observedInitialPaint = true
        onFirstPaint()
    }

    private func endInterval(for pending: PendingActivation) {
        switch pending.residency {
        case .live:
            PerformanceTrace.endInterval(
                "PageActivation.liveToFirstPaint",
                pending.interval
            )
        case .cold:
            PerformanceTrace.endInterval(
                "PageActivation.coldToFirstPaint",
                pending.interval
            )
        }
    }
}

@MainActor
private final class PageActivationPaintHook: NSObject {
    typealias Tick = @MainActor (TimeInterval) -> Void

    private let onTick: Tick
    private var displayLink: CADisplayLink?

    init(window: NSWindow?, onTick: @escaping Tick) {
        self.onTick = onTick
        super.init()
        self.displayLink = window?.displayLink(
            target: self,
            selector: #selector(handleDisplayLink(_:))
        )
    }

    func start() -> Bool {
        guard let displayLink else { return false }
        displayLink.add(to: .main, forMode: .common)
        return true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func handleDisplayLink(_ displayLink: CADisplayLink) {
        onTick(displayLink.targetTimestamp)
    }
}
