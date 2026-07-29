import CoreGraphics
import Observation
import SwiftUI

enum BrowserWindowSidebarLayoutSurface: Equatable {
    case docked
    case collapsed
}

enum BrowserWindowSidebarLayoutVisibility: Equatable {
    case hidden
    case visible

    var progress: CGFloat {
        self == .visible ? 1 : 0
    }
}

enum BrowserWindowSidebarLayoutPhase: Equatable {
    case moving(
        surface: BrowserWindowSidebarLayoutSurface,
        toward: BrowserWindowSidebarLayoutVisibility
    )
    case settled(
        surface: BrowserWindowSidebarLayoutSurface,
        visibility: BrowserWindowSidebarLayoutVisibility
    )
}

private struct BrowserWindowSidebarMotionToken: Equatable {
    fileprivate let generation: UInt64
}

struct BrowserWindowDisplayFrameRequest: Equatable {
    let id: UInt64
    let frameCount: Int
}

struct BrowserWindowTrafficLightPresentation: Equatable {
    var rendering: BrowserWindowTrafficLightRendering
    var travelProgress: CGFloat
    var carriesOwnTravel: Bool
}

struct BrowserWindowTrafficLightPlacementState: Equatable {
    var rendering: BrowserWindowTrafficLightRendering
    var isLeadingSidebarChrome: Bool
    var displayFrameRequest: BrowserWindowDisplayFrameRequest?
}

enum BrowserWindowTrafficLightRendering: Equatable {
    case hidden
    case system
    case chrome
    case travelling
    case handoff

    var showsPlaceholder: Bool { self == .travelling || self == .handoff }

    var reservesSidebarWidth: Bool {
        switch self {
        case .chrome, .travelling, .handoff:
            return true
        case .hidden, .system:
            return false
        }
    }
}

/// Window-local authority for Presented Sidebar Layout Phase and its traffic-light projections.
///
/// Docked and collapsed adapters provide their actual layout mutation, while this module owns
/// admission, interruption, progress and settlement. AppKit display confirmation is generation-
/// bound by the same authority, so no caller can publish a half-transition.
@MainActor
@Observable
final class BrowserWindowChromePresentation {
    private enum Destination {
        case hidden
        case system
        case chrome
    }

    private enum DisplayFrameStage {
        case chromeConfirmation
        case placeholderRetirement
    }

    private(set) var sidebarLayoutPhase: BrowserWindowSidebarLayoutPhase = .settled(
        surface: .docked,
        visibility: .hidden
    )
    private(set) var rendering: BrowserWindowTrafficLightRendering = .hidden
    private(set) var travelProgress: CGFloat = 0
    private(set) var carriesOwnTravel = false
    private(set) var displayFrameRequest: BrowserWindowDisplayFrameRequest?

    private var shellEdge: SidebarShellEdge = SidebarPosition.left.shellEdge
    private var isBrowserWindowFullScreen = false
    private var motionGeneration: UInt64 = 0
    private var displayFrameGeneration: UInt64 = 0
    private var displayFrameStage: DisplayFrameStage?

    var trafficLights: BrowserWindowTrafficLightPresentation {
        BrowserWindowTrafficLightPresentation(
            rendering: rendering,
            travelProgress: travelProgress,
            carriesOwnTravel: carriesOwnTravel
        )
    }

    var placement: BrowserWindowTrafficLightPlacementState {
        BrowserWindowTrafficLightPlacementState(
            rendering: rendering,
            isLeadingSidebarChrome: shellEdge.isLeft,
            displayFrameRequest: displayFrameRequest
        )
    }

    func configure(
        shellEdge: SidebarShellEdge,
        isBrowserWindowFullScreen: Bool
    ) {
        guard self.shellEdge != shellEdge
                || self.isBrowserWindowFullScreen != isBrowserWindowFullScreen
        else { return }

        self.shellEdge = shellEdge
        self.isBrowserWindowFullScreen = isBrowserWindowFullScreen
        cancelDisplayFrameConfirmation()
        reconcileRenderingWithCurrentPhase()
    }

    /// Performs one Presented Sidebar Layout motion as a single transaction.
    ///
    /// The supplied update mutates the real docked or collapsed layout. Callers never receive the
    /// generation token and therefore cannot forget to advance or settle the chrome projection.
    func performSidebarMotion(
        surface: BrowserWindowSidebarLayoutSurface,
        toward visibility: BrowserWindowSidebarLayoutVisibility,
        animation: Animation?,
        updateLayout: @escaping @MainActor () -> Void,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let token = beginSidebarMotion(surface: surface, toward: visibility)

        let update = {
            updateLayout()
            self.advanceSidebarMotion(token)
        }

        guard let animation else {
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction, update)

            if token != nil, surface == .collapsed, visibility == .visible {
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, self.isCurrentMotion(token) else { return }
                    completion?()
                    self.settleSidebarMotion(token)
                }
            } else if isCurrentMotion(token) {
                completion?()
                settleSidebarMotion(token)
            }
            return
        }

        withAnimation(animation, completionCriteria: .removed, update) { [weak self] in
            guard let self, self.isCurrentMotion(token) else { return }
            completion?()
            self.settleSidebarMotion(token)
        }
    }

    private func beginSidebarMotion(
        surface: BrowserWindowSidebarLayoutSurface,
        toward visibility: BrowserWindowSidebarLayoutVisibility
    ) -> BrowserWindowSidebarMotionToken? {
        guard surface != .collapsed || !dockedSurfaceOwnsPresentation else { return nil }

        motionGeneration &+= 1
        let token = BrowserWindowSidebarMotionToken(generation: motionGeneration)
        cancelDisplayFrameConfirmation()
        sidebarLayoutPhase = .moving(surface: surface, toward: visibility)
        carriesOwnTravel = surface == .docked && shellEdge.isLeft

        switch destination(visibility: visibility) {
        case .hidden where shellEdge.isLeft && !isBrowserWindowFullScreen:
            rendering = .travelling
        case .chrome:
            rendering = .travelling
        case .hidden:
            rendering = .hidden
        case .system:
            rendering = .system
        }

        return token
    }

    private func advanceSidebarMotion(_ token: BrowserWindowSidebarMotionToken?) {
        guard let token,
              token.generation == motionGeneration,
              case .moving(_, let visibility) = sidebarLayoutPhase
        else { return }
        travelProgress = visibility.progress
    }

    private func settleSidebarMotion(_ token: BrowserWindowSidebarMotionToken?) {
        guard let token,
              token.generation == motionGeneration,
              case .moving(let surface, let visibility) = sidebarLayoutPhase
        else { return }

        sidebarLayoutPhase = .settled(surface: surface, visibility: visibility)
        settleRendering(visibility: visibility)
    }

    private func isCurrentMotion(_ token: BrowserWindowSidebarMotionToken?) -> Bool {
        guard let token else { return false }
        return token.generation == motionGeneration
    }

    func displayFramesDidElapse(requestID: UInt64) {
        guard placement.displayFrameRequest?.id == requestID,
              let displayFrameStage
        else { return }

        switch displayFrameStage {
        case .chromeConfirmation:
            rendering = .handoff
            requestDisplayFrames(1, stage: .placeholderRetirement)
        case .placeholderRetirement:
            rendering = .chrome
            cancelDisplayFrameConfirmation()
        }
    }

    private func reconcileRenderingWithCurrentPhase() {
        switch sidebarLayoutPhase {
        case .moving(let surface, let visibility):
            carriesOwnTravel = surface == .docked && shellEdge.isLeft
            switch destination(visibility: visibility) {
            case .system:
                rendering = .system
            case .hidden where !shellEdge.isLeft:
                rendering = .hidden
            case .hidden, .chrome:
                rendering = .travelling
            }
        case .settled(let surface, let visibility):
            carriesOwnTravel = surface == .docked && shellEdge.isLeft
            settleRendering(visibility: visibility)
        }
    }

    private var dockedSurfaceOwnsPresentation: Bool {
        switch sidebarLayoutPhase {
        case .moving(surface: .docked, toward: _),
             .settled(surface: .docked, visibility: .visible):
            return true
        case .moving(surface: .collapsed, toward: _),
             .settled(surface: .collapsed, visibility: _),
             .settled(surface: .docked, visibility: .hidden):
            return false
        }
    }

    private func settleRendering(
        visibility: BrowserWindowSidebarLayoutVisibility
    ) {
        switch destination(visibility: visibility) {
        case .chrome:
            rendering = .travelling
            requestDisplayFrames(2, stage: .chromeConfirmation)
        case .hidden:
            rendering = .hidden
            cancelDisplayFrameConfirmation()
        case .system:
            rendering = .system
            cancelDisplayFrameConfirmation()
        }
    }

    private func destination(
        visibility: BrowserWindowSidebarLayoutVisibility
    ) -> Destination {
        guard shellEdge.isLeft else { return .hidden }
        guard !isBrowserWindowFullScreen else { return .system }
        return visibility == .visible ? .chrome : .hidden
    }

    private func requestDisplayFrames(_ count: Int, stage: DisplayFrameStage) {
        displayFrameGeneration &+= 1
        displayFrameStage = stage
        displayFrameRequest = BrowserWindowDisplayFrameRequest(
            id: displayFrameGeneration,
            frameCount: count
        )
    }

    private func cancelDisplayFrameConfirmation() {
        displayFrameStage = nil
        displayFrameRequest = nil
    }
}
