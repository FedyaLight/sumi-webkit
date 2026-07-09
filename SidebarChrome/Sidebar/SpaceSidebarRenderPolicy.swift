//
//  SpaceSidebarRenderPolicy.swift
//  Sumi
//
//

import SwiftUI

enum SidebarPageRenderMode: Equatable {
    case interactive
    case transitionSnapshot

    var spaceRenderMode: SpaceViewRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }

    var animatesEssentialsLayout: Bool {
        self == .interactive
    }
}

extension SidebarPageRenderMode {
    var geometryRenderMode: SidebarPageGeometryRenderMode {
        switch self {
        case .interactive:
            return .interactive
        case .transitionSnapshot:
            return .transitionSnapshot
        }
    }
}

enum SpaceSidebarRenderPolicy {
    static let completionDelay = SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration

    static func pageRenderMode(for role: Role) -> SidebarPageRenderMode {
        switch role {
        case .committed:
            return .interactive
        case .transitionLayer:
            return .transitionSnapshot
        }
    }

    static func shouldUseTransitionLayers(for state: SpaceSidebarTransitionState) -> Bool {
        state.hasDestination
    }

    static func shouldBeginSwipeTransition(for event: SpaceSwipeGestureEvent) -> Bool {
        event.phase == .changed && event.direction != nil
    }

    enum Role {
        case committed
        case transitionLayer
    }
}

@MainActor
enum SpaceSidebarChromePreviewPolicy {
    static func shouldAnimateEssentialsLayout(
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode
    ) -> Bool {
        isActiveWindow
            && !isTransitioningProfile
            && pageRenderMode.animatesEssentialsLayout
    }
}

enum SpaceSidebarEssentialsPlacementPolicy {
    static func usesSharedPinnedGrid(
        sourceProfileId: UUID?,
        destinationProfileId: UUID?
    ) -> Bool {
        sourceProfileId == destinationProfileId
    }
}
