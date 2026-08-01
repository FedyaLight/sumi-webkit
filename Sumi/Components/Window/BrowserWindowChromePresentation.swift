import Observation
import SwiftUI

enum BrowserWindowSidebarLayoutSurface: Equatable {
    case docked
    case collapsed
}

enum BrowserWindowSidebarLayoutVisibility: Equatable {
    case hidden
    case visible
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

struct BrowserWindowTrafficLightPresentation: Equatable {
    var rendering: BrowserWindowTrafficLightRendering
}

struct BrowserWindowTrafficLightPlacementState: Equatable {
    var rendering: BrowserWindowTrafficLightRendering
    var isLeadingSidebarChrome: Bool
}

enum BrowserWindowTrafficLightRendering: Equatable {
    case hidden
    case system
    case chrome
    case travelling

    /// The placeholder is a permanent part of leading sidebar chrome. In `.chrome` the real
    /// AppKit buttons cover it; in `.travelling` it moves with the sidebar on its own.
    var showsPlaceholder: Bool { self == .chrome || self == .travelling }

    var showsNativeButtons: Bool { self == .chrome || self == .system }

    var reservesSidebarWidth: Bool { self == .chrome || self == .travelling }
}

/// Window-local authority for Presented Sidebar Layout Phase and its traffic-light projections.
///
/// The sidebar owns the travelling placeholder. AppKit owns the stationary interactive buttons.
/// A transition therefore needs no independent progress, display-link confirmation, or handoff
/// state: the native buttons are visible only after the matching sidebar motion has settled.
@MainActor
@Observable
final class BrowserWindowChromePresentation {
    private enum Destination {
        case hidden
        case system
        case chrome
    }

    private(set) var sidebarLayoutPhase: BrowserWindowSidebarLayoutPhase = .settled(
        surface: .docked,
        visibility: .hidden
    )
    private(set) var rendering: BrowserWindowTrafficLightRendering = .hidden

    private var shellEdge: SidebarShellEdge = SidebarPosition.left.shellEdge
    private var isBrowserWindowFullScreen = false
    private var motionGeneration: UInt64 = 0

    var trafficLights: BrowserWindowTrafficLightPresentation {
        BrowserWindowTrafficLightPresentation(rendering: rendering)
    }

    var placement: BrowserWindowTrafficLightPlacementState {
        BrowserWindowTrafficLightPlacementState(
            rendering: rendering,
            isLeadingSidebarChrome: shellEdge.isLeft
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
        reconcileRenderingWithCurrentPhase()
    }

    /// Performs one Presented Sidebar Layout motion as a single transaction.
    ///
    /// The supplied update mutates the real docked or collapsed layout. Callers never receive the
    /// generation token and therefore cannot let an interrupted completion reveal native controls.
    func performSidebarMotion(
        surface: BrowserWindowSidebarLayoutSurface,
        toward visibility: BrowserWindowSidebarLayoutVisibility,
        animation: Animation?,
        updateLayout: @escaping @MainActor () -> Void,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let token = beginSidebarMotion(surface: surface, toward: visibility)

        guard let animation else {
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction, updateLayout)

            // A collapsed overlay is attached by AppKit on the next actor turn. Keep the native
            // buttons withdrawn until that stable host exists.
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

        withAnimation(animation, completionCriteria: .removed, updateLayout) { [weak self] in
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
        sidebarLayoutPhase = .moving(surface: surface, toward: visibility)
        rendering = movingRendering(toward: visibility)
        return token
    }

    private func settleSidebarMotion(_ token: BrowserWindowSidebarMotionToken?) {
        guard let token,
              token.generation == motionGeneration,
              case .moving(let surface, let visibility) = sidebarLayoutPhase
        else { return }

        sidebarLayoutPhase = .settled(surface: surface, visibility: visibility)
        rendering = settledRendering(visibility: visibility)
    }

    private func isCurrentMotion(_ token: BrowserWindowSidebarMotionToken?) -> Bool {
        guard let token else { return false }
        return token.generation == motionGeneration
    }

    private func reconcileRenderingWithCurrentPhase() {
        switch sidebarLayoutPhase {
        case .moving(_, let visibility):
            rendering = movingRendering(toward: visibility)
        case .settled(_, let visibility):
            rendering = settledRendering(visibility: visibility)
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

    private func movingRendering(
        toward visibility: BrowserWindowSidebarLayoutVisibility
    ) -> BrowserWindowTrafficLightRendering {
        switch destination(visibility: visibility) {
        case .system:
            return .system
        case .hidden where !shellEdge.isLeft:
            return .hidden
        case .hidden, .chrome:
            return .travelling
        }
    }

    private func settledRendering(
        visibility: BrowserWindowSidebarLayoutVisibility
    ) -> BrowserWindowTrafficLightRendering {
        switch destination(visibility: visibility) {
        case .chrome: .chrome
        case .hidden: .hidden
        case .system: .system
        }
    }

    private func destination(
        visibility: BrowserWindowSidebarLayoutVisibility
    ) -> Destination {
        guard shellEdge.isLeft else { return .hidden }
        guard !isBrowserWindowFullScreen else { return .system }
        return visibility == .visible ? .chrome : .hidden
    }
}
