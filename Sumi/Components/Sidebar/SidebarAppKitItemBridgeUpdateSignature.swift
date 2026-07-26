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
    let primaryActionExclusionZones: [SidebarDragSourceExclusionZone]
    let hasPageActivation: Bool
    let hasReleaseAction: Bool
    let showsPressVisual: Bool
    let hasMiddleClick: Bool
    let sourceID: String?
    let routingPriorityBoost: Int
    let suppressesActionAnimation: Bool
    let presentationMode: SidebarPresentationMode
    let supportsPrimaryMouseTracking: Bool
}

struct SidebarAppKitItemInteractionIdentity: Equatable {
    enum SemanticItem: Equatable {
        case sourceID(String)
        case dragItem(id: UUID, kind: SumiDragItemKind)
        case anonymous
    }

    let item: SemanticItem
    let interactionStateID: ObjectIdentifier?
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
            primaryActionExclusionZones: primaryActionExclusionZones,
            hasPageActivation: pageActivation != nil,
            hasReleaseAction: releaseAction != nil,
            showsPressVisual: showsPressVisual,
            hasMiddleClick: onMiddleClick != nil,
            sourceID: sourceID,
            routingPriorityBoost: routingPriorityBoost,
            suppressesActionAnimation: suppressesActionAnimation,
            presentationMode: presentationMode,
            supportsPrimaryMouseTracking: supportsPrimaryMouseTracking
        )
    }

    var supportsPrimaryMouseTracking: Bool {
        pageActivation != nil || releaseAction != nil || dragSource?.isEnabled == true
    }

    var interactionIdentity: SidebarAppKitItemInteractionIdentity {
        let item: SidebarAppKitItemInteractionIdentity.SemanticItem
        if let sourceID {
            item = .sourceID(sourceID)
        } else if let dragItem = dragSource?.item {
            item = .dragItem(id: dragItem.stableID, kind: dragItem.kind)
        } else {
            item = .anonymous
        }

        return SidebarAppKitItemInteractionIdentity(
            item: item,
            interactionStateID: interactionState.map(ObjectIdentifier.init)
        )
    }
}
