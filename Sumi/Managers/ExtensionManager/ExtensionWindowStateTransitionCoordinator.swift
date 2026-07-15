import AppKit
import WebKit

private final class ExtensionWindowNotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: NotificationCenter = .default,
        name: Notification.Name,
        object: AnyObject,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = center.addObserver(
            forName: name,
            object: object,
            queue: nil,
            using: handler
        )
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowStateTransitionCoordinator {
    typealias CurrentValidation = @MainActor () -> Bool
    typealias ErrorFactory = @MainActor () -> Error
    typealias Completion = @MainActor (Error?) -> Void

    private let supersededError: ErrorFactory
    private let invalidatedError: ErrorFactory
    private var active: ExtensionWindowStateTransition?
    private var admissionGeneration: UInt64 = 0

    init(
        supersededError: @escaping ErrorFactory,
        invalidatedError: @escaping ErrorFactory
    ) {
        self.supersededError = supersededError
        self.invalidatedError = invalidatedError
    }

    func transition(
        window: NSWindow,
        to targetState: WKWebExtension.WindowState,
        isCurrent: @escaping CurrentValidation,
        completion: @escaping Completion
    ) {
        admissionGeneration &+= 1
        let requestGeneration = admissionGeneration
        let windowIdentity = ObjectIdentifier(window)
        var inheritedSettlement: ExtensionWindowStateSettlement?

        if let previous = active {
            if previous.ownsWindow(with: windowIdentity) {
                inheritedSettlement = previous.awaitedSettlement
            }
            active = nil
            previous.cancel(with: supersededError())

            guard admissionGeneration == requestGeneration,
                  active == nil else {
                completion(supersededError())
                return
            }
        }

        guard ObjectIdentifier(window) == windowIdentity,
              isCurrent() else {
            completion(invalidatedError())
            return
        }

        let transitionID = UUID()
        let transition = ExtensionWindowStateTransition(
            id: transitionID,
            window: window,
            windowIdentity: windowIdentity,
            targetState: targetState,
            initialSettlement: inheritedSettlement,
            isCurrent: isCurrent,
            invalidatedError: invalidatedError,
            completion: completion,
            didFinish: { [weak self] finishedID in
                guard self?.active?.id == finishedID else { return }
                self?.active = nil
            }
        )
        active = transition
        transition.start()
    }

    func invalidateActiveTransition() {
        guard let transition = active else { return }
        active = nil
        transition.cancel(with: invalidatedError())
    }
}

@available(macOS 15.5, *)
private enum ExtensionWindowStateSettlement {
    case miniaturized
    case deminiaturized
    case enteredFullScreen
    case exitedFullScreen
    case zoomed(Bool)

    var notificationName: Notification.Name {
        switch self {
        case .miniaturized:
            NSWindow.didMiniaturizeNotification
        case .deminiaturized:
            NSWindow.didDeminiaturizeNotification
        case .enteredFullScreen:
            NSWindow.didEnterFullScreenNotification
        case .exitedFullScreen:
            NSWindow.didExitFullScreenNotification
        case .zoomed:
            NSWindow.didResizeNotification
        }
    }

    @MainActor
    func isSatisfied(by window: NSWindow) -> Bool {
        switch self {
        case .miniaturized:
            window.isMiniaturized
        case .deminiaturized:
            window.isMiniaturized == false
        case .enteredFullScreen:
            window.styleMask.contains(.fullScreen)
        case .exitedFullScreen:
            window.styleMask.contains(.fullScreen) == false
        case .zoomed(let expected):
            window.isZoomed == expected
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ExtensionWindowStateTransition: @unchecked Sendable {
    typealias CurrentValidation = ExtensionWindowStateTransitionCoordinator
        .CurrentValidation
    typealias ErrorFactory = ExtensionWindowStateTransitionCoordinator
        .ErrorFactory
    typealias Completion = ExtensionWindowStateTransitionCoordinator.Completion

    let id: UUID
    private weak var window: NSWindow?
    private let windowIdentity: ObjectIdentifier
    private let targetState: WKWebExtension.WindowState
    private let initialSettlement: ExtensionWindowStateSettlement?
    private let isCurrent: CurrentValidation
    private let invalidatedError: ErrorFactory
    private var completion: Completion?
    private let didFinish: @MainActor (UUID) -> Void
    private var settlementObservation: ExtensionWindowNotificationObservation?
    private var closeObservation: ExtensionWindowNotificationObservation?
    private var didStart = false
    private var didComplete = false

    private(set) var awaitedSettlement: ExtensionWindowStateSettlement?

    init(
        id: UUID,
        window: NSWindow,
        windowIdentity: ObjectIdentifier,
        targetState: WKWebExtension.WindowState,
        initialSettlement: ExtensionWindowStateSettlement?,
        isCurrent: @escaping CurrentValidation,
        invalidatedError: @escaping ErrorFactory,
        completion: @escaping Completion,
        didFinish: @escaping @MainActor (UUID) -> Void
    ) {
        self.id = id
        self.window = window
        self.windowIdentity = windowIdentity
        self.targetState = targetState
        self.initialSettlement = initialSettlement
        self.isCurrent = isCurrent
        self.invalidatedError = invalidatedError
        self.completion = completion
        self.didFinish = didFinish
    }

    func ownsWindow(with identity: ObjectIdentifier) -> Bool {
        windowIdentity == identity
    }

    func start() {
        precondition(didStart == false)
        didStart = true

        guard validateCurrentWindow(), let window else {
            failInvalidated()
            return
        }
        installCloseObserver()

        if let initialSettlement,
           initialSettlement.isSatisfied(by: window) == false {
            awaitSettlement(initialSettlement, action: nil)
            return
        }
        advance()
    }

    func cancel(with error: Error) {
        finish(error)
    }

    private func advance() {
        guard validateCurrentWindow(), let window else {
            failInvalidated()
            return
        }

        switch targetState {
        case .minimized:
            if window.isMiniaturized {
                finishCurrent()
            } else if window.styleMask.contains(.fullScreen) {
                awaitSettlement(.exitedFullScreen) { $0.toggleFullScreen(nil) }
            } else if window.styleMask.contains(.miniaturizable) {
                awaitSettlement(.miniaturized) { $0.performMiniaturize(nil) }
            } else {
                failInvalidated()
            }
        case .maximized:
            if window.isMiniaturized {
                awaitSettlement(.deminiaturized) { $0.deminiaturize(nil) }
            } else if window.styleMask.contains(.fullScreen) {
                awaitSettlement(.exitedFullScreen) { $0.toggleFullScreen(nil) }
            } else if window.isZoomed {
                finishCurrent()
            } else if window.styleMask.contains(.resizable) {
                awaitSettlement(.zoomed(true)) { $0.performZoom(nil) }
            } else {
                failInvalidated()
            }
        case .fullscreen:
            if window.styleMask.contains(.fullScreen) {
                finishCurrent()
            } else if window.isMiniaturized {
                awaitSettlement(.deminiaturized) { $0.deminiaturize(nil) }
            } else {
                awaitSettlement(.enteredFullScreen) { $0.toggleFullScreen(nil) }
            }
        case .normal:
            if window.isMiniaturized {
                awaitSettlement(.deminiaturized) { $0.deminiaturize(nil) }
            } else if window.styleMask.contains(.fullScreen) {
                awaitSettlement(.exitedFullScreen) { $0.toggleFullScreen(nil) }
            } else if window.isZoomed {
                awaitSettlement(.zoomed(false)) { $0.performZoom(nil) }
            } else {
                finishCurrent()
            }
        @unknown default:
            failInvalidated()
        }
    }

    private func awaitSettlement(
        _ settlement: ExtensionWindowStateSettlement,
        action: (@MainActor (NSWindow) -> Void)?
    ) {
        guard validateCurrentWindow(), let window else {
            failInvalidated()
            return
        }

        removeSettlementObserver()
        awaitedSettlement = settlement
        settlementObservation = ExtensionWindowNotificationObservation(
            name: settlement.notificationName,
            object: window
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.receiveSettlement()
            }
        }

        guard validateCurrentWindow() else {
            failInvalidated()
            return
        }
        action?(window)
        guard validateCurrentWindow() else {
            failInvalidated()
            return
        }
    }

    private func receiveSettlement() {
        guard let settlement = awaitedSettlement,
              validateCurrentWindow(),
              let window,
              settlement.isSatisfied(by: window) else {
            if validateCurrentWindow() == false {
                failInvalidated()
            }
            return
        }

        removeSettlementObserver()
        advance()
    }

    private func installCloseObserver() {
        guard let window else { return }
        closeObservation = ExtensionWindowNotificationObservation(
            name: NSWindow.willCloseNotification,
            object: window
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.failInvalidated()
            }
        }
    }

    private func validateCurrentWindow() -> Bool {
        guard didComplete == false,
              let window,
              ObjectIdentifier(window) == windowIdentity else {
            return false
        }
        return isCurrent()
    }

    private func finishCurrent() {
        guard validateCurrentWindow() else {
            failInvalidated()
            return
        }
        finish(nil)
    }

    private func failInvalidated() {
        finish(invalidatedError())
    }

    private func finish(_ error: Error?) {
        guard didComplete == false else { return }
        didComplete = true
        removeObservers()
        let completion = self.completion
        self.completion = nil
        didFinish(id)
        completion?(error)
    }

    private func removeObservers() {
        removeSettlementObserver()
        closeObservation?.invalidate()
        closeObservation = nil
    }

    private func removeSettlementObserver() {
        awaitedSettlement = nil
        settlementObservation?.invalidate()
        settlementObservation = nil
    }
}
