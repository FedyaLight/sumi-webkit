import AppKit
import Foundation

enum WebViewGestureKind: Equatable {
    case primaryMouseDown
    case auxiliaryMouseDown
    case keyDown

    var isMouseDown: Bool {
        switch self {
        case .primaryMouseDown, .auxiliaryMouseDown:
            return true
        case .keyDown:
            return false
        }
    }

    var popupActivationKind: String {
        switch self {
        case .primaryMouseDown:
            return "mouseDown"
        case .auxiliaryMouseDown:
            return "middleMouseDown"
        case .keyDown:
            return "keyDown"
        }
    }
}

struct WebViewGestureSnapshot: Equatable {
    let generation: UInt64
    let kind: WebViewGestureKind
    let eventTimestamp: TimeInterval
    let modifierFlags: NSEvent.ModifierFlags
    let glanceOriginRectInWindow: CGRect?
}

struct WebViewGestureReceipt: Equatable {
    fileprivate let generation: UInt64
}

@MainActor
final class WebViewGestureState {
    private struct PrimaryMouseDownSnapshot {
        let eventTimestamp: TimeInterval
        let originRectInWindow: CGRect
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift,
    ]

    private var nextGeneration: UInt64 = 0
    private var latest: WebViewGestureSnapshot?
    private var lastPrimaryMouseDown: PrimaryMouseDownSnapshot?

    @discardableResult
    func record(_ event: NSEvent, kind: WebViewGestureKind) -> WebViewGestureReceipt {
        nextGeneration &+= 1
        let glanceOriginRectInWindow: CGRect?
        if kind == .primaryMouseDown {
            let point = event.locationInWindow
            glanceOriginRectInWindow = CGRect(
                x: point.x - 22,
                y: point.y - 22,
                width: 44,
                height: 44
            )
            lastPrimaryMouseDown = glanceOriginRectInWindow.map {
                PrimaryMouseDownSnapshot(
                    eventTimestamp: event.timestamp,
                    originRectInWindow: $0
                )
            }
        } else {
            glanceOriginRectInWindow = nil
            lastPrimaryMouseDown = nil
        }

        latest = WebViewGestureSnapshot(
            generation: nextGeneration,
            kind: kind,
            eventTimestamp: event.timestamp,
            modifierFlags: event.modifierFlags.intersection(Self.relevantModifiers),
            glanceOriginRectInWindow: glanceOriginRectInWindow
        )
        return WebViewGestureReceipt(generation: nextGeneration)
    }

    func clear() {
        clearCurrentGesture()
        lastPrimaryMouseDown = nil
    }

    func clearCurrentGesture() {
        latest = nil
    }

    func clear(ifCurrent receipt: WebViewGestureReceipt?) {
        guard let receipt, latest?.generation == receipt.generation else { return }
        latest = nil
    }

    var currentReceipt: WebViewGestureReceipt? {
        latest.map { WebViewGestureReceipt(generation: $0.generation) }
    }

    func resolvedModifierFlags(
        actionFlags: NSEvent.ModifierFlags,
        maxAge: TimeInterval = 1
    ) -> NSEvent.ModifierFlags {
        if let snapshot = recentSnapshot(maxAge: maxAge),
           snapshot.kind.isMouseDown,
           !snapshot.modifierFlags.isEmpty {
            return snapshot.modifierFlags
        }

        let actionFlags = actionFlags.intersection(Self.relevantModifiers)
        if !actionFlags.isEmpty {
            return actionFlags
        }

        return recentSnapshot(maxAge: maxAge)?.modifierFlags ?? []
    }

    func recentGlanceOriginRect(maxAge: TimeInterval = 1.5) -> CGRect? {
        guard let snapshot = recentSnapshot(maxAge: maxAge),
              snapshot.kind == .primaryMouseDown
        else { return nil }
        return snapshot.glanceOriginRectInWindow
    }

    func recentPrimaryMouseDownOriginRect(
        maxAge: TimeInterval = 5
    ) -> CGRect? {
        guard let lastPrimaryMouseDown else { return nil }
        let age = ProcessInfo.processInfo.systemUptime
            - lastPrimaryMouseDown.eventTimestamp
        guard age >= 0, age <= maxAge else { return nil }
        return lastPrimaryMouseDown.originRectInWindow
    }

    var hasRecentAuxiliaryMouseDown: Bool {
        recentSnapshot(maxAge: 1)?.kind == .auxiliaryMouseDown
    }

    private func recentSnapshot(maxAge: TimeInterval) -> WebViewGestureSnapshot? {
        guard let latest else { return nil }
        let age = ProcessInfo.processInfo.systemUptime - latest.eventTimestamp
        guard age >= 0, age <= maxAge else { return nil }
        return latest
    }
}

@MainActor
final class WebViewHoveredLinkObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }

    isolated deinit {
        cancellation?()
    }
}

@MainActor
final class WebViewHoveredLinkState {
    struct Snapshot {
        let href: String?
        let updatedAt: TimeInterval
    }

    private(set) var snapshot = Snapshot(href: nil, updatedAt: 0)
    private var observers: [UUID: (String?) -> Void] = [:]

    var href: String? { snapshot.href }
    var url: URL? { snapshot.href.flatMap(URL.init(string:)) }

    func update(_ href: String?) {
        guard snapshot.href != href else { return }
        snapshot = Snapshot(
            href: href,
            updatedAt: ProcessInfo.processInfo.systemUptime
        )
        for observer in observers.values {
            observer(href)
        }
    }

    func observe(
        _ observer: @escaping (String?) -> Void
    ) -> WebViewHoveredLinkObservation {
        let id = UUID()
        observers[id] = observer
        return WebViewHoveredLinkObservation { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }
}

@MainActor
final class WebViewContextMenuState {
    private var latestTarget: SumiWebPageContextMenuTargetSnapshot?
    private var onNextRecord: ((SumiWebPageContextMenuTargetSnapshot) -> Void)?

    func record(_ target: SumiWebPageContextMenuTargetSnapshot) {
        latestTarget = target
        let pending = onNextRecord
        onNextRecord = nil
        pending?(target)
    }

    /// One-shot continuation for a menu presented before the DOM snapshot
    /// arrived. Consumed by the next `record(_:)`; replaced by re-registration.
    func awaitNextRecord(
        _ handler: @escaping (SumiWebPageContextMenuTargetSnapshot) -> Void
    ) {
        onNextRecord = handler
    }

    func cancelPendingRecordHandler() {
        onNextRecord = nil
    }

    func clear() {
        latestTarget = nil
        onNextRecord = nil
    }

    func recentTarget(maxAge: TimeInterval = 1) -> SumiWebPageContextMenuTargetSnapshot? {
        guard let latestTarget, latestTarget.isRecent(maxAge: maxAge) else { return nil }
        return latestTarget
    }
}
