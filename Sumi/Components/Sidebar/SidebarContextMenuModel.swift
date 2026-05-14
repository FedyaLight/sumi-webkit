//
//  SidebarContextMenuModel.swift
//  Sumi
//

import AppKit

enum SidebarContextMenuRole {
    case normal
    case destructive
}

enum SidebarContextMenuActionClassification: String {
    case presentationOnly
    case stateMutationNonStructural
    case structuralMutation

    var recoveryTier: SidebarRecoveryTier {
        switch self {
        case .presentationOnly, .stateMutationNonStructural, .structuralMutation:
            return .soft
        }
    }
}

struct SidebarContextMenuChoice: Identifiable, Equatable {
    let id: UUID
    let title: String
    var isSelected: Bool = false
}

struct SidebarContextMenuAction {
    let title: String
    let systemImage: String?
    let isEnabled: Bool
    let state: NSControl.StateValue
    let role: SidebarContextMenuRole
    let classification: SidebarContextMenuActionClassification
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        state: NSControl.StateValue = .off,
        role: SidebarContextMenuRole = .normal,
        classification: SidebarContextMenuActionClassification = .stateMutationNonStructural,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.state = state
        self.role = role
        self.classification = classification
        self.action = action
    }
}

indirect enum SidebarContextMenuEntry {
    case action(SidebarContextMenuAction)
    case submenu(title: String, systemImage: String? = nil, children: [SidebarContextMenuEntry])
    case separator
}

enum SidebarContextMenuSurfaceKind: Equatable {
    case row
    case button
    case background
}

func sidebarContextMenuSurfaceDebugDescription(_ surfaceKind: SidebarContextMenuSurfaceKind) -> String {
    switch surfaceKind {
    case .row:
        return "row"
    case .button:
        return "button"
    case .background:
        return "background"
    }
}

func sidebarPresentationModeDebugDescription(_ mode: SidebarPresentationMode) -> String {
    switch mode {
    case .docked:
        return "docked"
    case .collapsedHidden:
        return "collapsedHidden"
    case .collapsedVisible:
        return "collapsedVisible"
    }
}

struct SidebarContextMenuTriggers: OptionSet {
    let rawValue: Int

    static let leftClick = SidebarContextMenuTriggers(rawValue: 1 << 0)
    static let rightClick = SidebarContextMenuTriggers(rawValue: 1 << 1)
}

enum SidebarContextMenuMouseTrigger {
    case leftMouseDown
    case rightMouseDown
}

enum SidebarContextMenuPresentationStyle: Equatable {
    case contextualEvent
    case anchoredPopup
}

enum SidebarContextMenuRoutingPolicy {
    static func presentationStyle(
        for trigger: SidebarContextMenuMouseTrigger
    ) -> SidebarContextMenuPresentationStyle {
        switch trigger {
        case .rightMouseDown:
            return .contextualEvent
        case .leftMouseDown:
            return .anchoredPopup
        }
    }

    static func shouldIntercept(
        _ trigger: SidebarContextMenuMouseTrigger,
        triggers: SidebarContextMenuTriggers
    ) -> Bool {
        switch trigger {
        case .leftMouseDown:
            triggers.contains(.leftClick)
        case .rightMouseDown:
            triggers.contains(.rightClick)
        }
    }
}

struct SidebarContextMenuLeafConfiguration {
    let isEnabled: Bool
    let surfaceKind: SidebarContextMenuSurfaceKind
    let triggers: SidebarContextMenuTriggers
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void
}

struct SidebarAppKitItemConfiguration {
    var isInteractionEnabled: Bool = true
    var interactionState: SidebarInteractionState? = nil
    var menu: SidebarContextMenuLeafConfiguration? = nil
    var dragSource: SidebarDragSourceConfiguration? = nil
    var dragScope: SidebarDragScope? = nil
    var primaryAction: (() -> Void)? = nil
    var onMiddleClick: (() -> Void)? = nil
    var sourceID: String? = nil
    var suppressesPrimaryActionAnimation: Bool = false
    var presentationMode: SidebarPresentationMode = .docked

    var surfaceKind: SidebarContextMenuSurfaceKind {
        menu?.surfaceKind ?? .row
    }
}

enum SidebarItemInputRoutingReason: Equatable {
    case collapsedOverlay
    case dragSource
    case middleClick
    case primaryMouseTracking
    case leftMouseDownMenu
    case rightMouseDownMenu
    case appKitRecovery
    case unavailableLeanContextMenu
}

enum SidebarItemInputRoute: Equatable {
    case appKitOwner(SidebarItemInputRoutingReason)
    case leanDockedContextMenu
    case nativeSwiftUI
}

enum SidebarItemInputRouting {
    static func route(
        in presentationContext: SidebarPresentationContext,
        menu: SidebarContextMenuLeafConfiguration?,
        dragSource: SidebarDragSourceConfiguration? = nil,
        hasMiddleClick: Bool = false,
        requiresManualPrimaryMouseTracking: Bool = false,
        requiresAppKitRecovery: Bool = false
    ) -> SidebarItemInputRoute {
        if presentationContext.inputMode == .collapsedOverlay {
            return .appKitOwner(.collapsedOverlay)
        }
        if dragSource != nil {
            return .appKitOwner(.dragSource)
        }
        if hasMiddleClick {
            return .appKitOwner(.middleClick)
        }
        if requiresManualPrimaryMouseTracking {
            return .appKitOwner(.primaryMouseTracking)
        }
        if requiresAppKitRecovery {
            return .appKitOwner(.appKitRecovery)
        }

        guard let menu else {
            return .nativeSwiftUI
        }

        if menu.triggers.contains(.leftClick) {
            return .appKitOwner(.leftMouseDownMenu)
        }
        if menu.triggers == .rightClick {
            return .appKitOwner(.rightMouseDownMenu)
        }
        return .appKitOwner(.unavailableLeanContextMenu)
    }

}

struct SidebarContextMenuResolvedTarget {
    let entries: [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void
}
