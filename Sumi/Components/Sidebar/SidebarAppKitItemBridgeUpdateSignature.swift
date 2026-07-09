//
//  SidebarAppKitItemBridgeUpdateSignature.swift
//  Sumi
//

import AppKit
import Foundation

struct SidebarAppKitItemBridgeUpdateSignature: Equatable {
    let isInteractionEnabled: Bool
    let menuIsEnabled: Bool?
    let menuSurfaceKind: SidebarContextMenuSurfaceKind
    let menuTriggersRawValue: Int?
    let dragItem: SumiDragItem?
    let dragSourceZone: DropZoneID?
    let dragPreviewKind: SidebarDragPreviewKind?
    let dragIsEnabled: Bool?
    let dragScope: SidebarDragScope?
    let hasPrimaryAction: Bool
    let hasMiddleClick: Bool
    let sourceID: String?
    let routingPriorityBoost: Int
    let suppressesPrimaryActionAnimation: Bool
    let presentationMode: SidebarPresentationMode
    let supportsPrimaryMouseTracking: Bool
}

extension SidebarAppKitItemConfiguration {
    var bridgeUpdateSignature: SidebarAppKitItemBridgeUpdateSignature {
        SidebarAppKitItemBridgeUpdateSignature(
            isInteractionEnabled: isInteractionEnabled,
            menuIsEnabled: menu?.isEnabled,
            menuSurfaceKind: surfaceKind,
            menuTriggersRawValue: menu?.triggers.rawValue,
            dragItem: dragSource?.item,
            dragSourceZone: dragSource?.sourceZone,
            dragPreviewKind: dragSource?.previewKind,
            dragIsEnabled: dragSource?.isEnabled,
            dragScope: dragScope,
            hasPrimaryAction: primaryAction != nil,
            hasMiddleClick: onMiddleClick != nil,
            sourceID: sourceID,
            routingPriorityBoost: routingPriorityBoost,
            suppressesPrimaryActionAnimation: suppressesPrimaryActionAnimation,
            presentationMode: presentationMode,
            supportsPrimaryMouseTracking: supportsPrimaryMouseTracking
        )
    }

    var supportsPrimaryMouseTracking: Bool {
        primaryAction != nil || dragSource?.isEnabled == true || dragSource?.onActivate != nil
    }
}
