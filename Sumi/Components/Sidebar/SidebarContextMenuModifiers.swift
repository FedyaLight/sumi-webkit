//
//  SidebarContextMenuModifiers.swift
//  Sumi
//

import SwiftUI

private struct SidebarAppKitItemModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext

    let menu: SidebarContextMenuLeafConfiguration
    let dragSource: SidebarDragSourceConfiguration?
    let primaryActionExclusionZones: [SidebarDragSourceExclusionZone]
    let pageActivation: (() -> Void)?
    let releaseAction: (() -> Void)?
    let showsPressVisual: Bool
    let onMiddleClick: (() -> Void)?
    let sourceID: String?
    let isInteractionEnabled: Bool
    let suppressesActionAnimation: Bool?

    @ViewBuilder
    func body(content: Content) -> some View {
        let effectiveInteractionEnabled = isInteractionEnabled
            && presentationContext.allowsInteractiveWork
        let route = SidebarItemInputRouting.route(
            in: presentationContext,
            menu: menu,
            dragSource: dragSource,
            hasMiddleClick: onMiddleClick != nil,
            requiresManualPrimaryMouseTracking:
                pageActivation != nil || releaseAction != nil,
            requiresAppKitRecovery: sourceID != nil
        )

        switch route {
        case .appKitOwner:
            let dragScope = dragSource.flatMap {
                SidebarDragScope(
                    windowState: windowState,
                    sourceZone: $0.sourceZone,
                    item: $0.item
                )
            }

            content.overlay {
                SidebarAppKitItemOverlay(
                    controller: windowState.sidebarContextMenuController,
                    configuration: SidebarAppKitItemConfiguration(
                        isInteractionEnabled: effectiveInteractionEnabled,
                        interactionState: windowState.sidebarInteractionState,
                        menu: menu,
                        dragSource: dragSource,
                        dragScope: dragScope,
                        primaryActionExclusionZones: primaryActionExclusionZones,
                        pageActivation: pageActivation,
                        releaseAction: releaseAction,
                        showsPressVisual: showsPressVisual,
                        onMiddleClick: onMiddleClick,
                        sourceID: sourceID,
                        suppressesActionAnimation:
                            suppressesActionAnimation ?? (dragSource != nil),
                        presentationMode: presentationContext.mode
                    )
                )
            }
            .geometryGroup()
        case .leanDockedContextMenu:
            content.overlay {
                SumiAppKitContextMenuOverlay(
                    controller: windowState.sidebarContextMenuController,
                    isEnabled: menu.isEnabled,
                    entries: menu.entries,
                    onMenuVisibilityChanged: menu.onMenuVisibilityChanged
                )
            }
        case .nativeSwiftUI:
            content
        }
    }
}

private struct SidebarAppKitPrimaryActionModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext

    let isEnabled: Bool
    let isInteractionEnabled: Bool
    let sourceID: String?
    let routingPriorityBoost: Int
    let onMiddleClick: (() -> Void)?
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if SidebarPrimaryActionInputRouting.usesAppKitOwner(
            in: presentationContext,
            sourceID: sourceID,
            hasMiddleClick: onMiddleClick != nil
        ) {
            let releaseAction: (() -> Void)? = isEnabled ? action : nil
            let middleClickAction: (() -> Void)? = isEnabled ? onMiddleClick : nil
            let effectiveInteractionEnabled = isInteractionEnabled
                && presentationContext.allowsInteractiveWork
            content.overlay {
                SidebarAppKitItemOverlay(
                    controller: windowState.sidebarContextMenuController,
                    configuration: SidebarAppKitItemConfiguration(
                        isInteractionEnabled: effectiveInteractionEnabled,
                        interactionState: windowState.sidebarInteractionState,
                        releaseAction: releaseAction,
                        onMiddleClick: middleClickAction,
                        sourceID: sourceID,
                        routingPriorityBoost: routingPriorityBoost,
                        presentationMode: presentationContext.mode
                    )
                )
            }
        } else {
            content
        }
    }
}

private struct SidebarAppKitItemOverlay: View {
    let controller: SidebarContextMenuController
    let configuration: SidebarAppKitItemConfiguration

    var body: some View {
        GeometryReader { proxy in
            SidebarAppKitItemBridge(
                controller: controller,
                configuration: configuration
            )
            .frame(
                width: max(proxy.size.width, 0),
                height: max(proxy.size.height, 0)
            )
        }
    }
}

private struct SumiAppKitContextMenuOverlay: View {
    let controller: SidebarContextMenuController
    let isEnabled: Bool
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            SumiAppKitContextMenuBridge(
                controller: controller,
                isEnabled: isEnabled,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
            .frame(
                width: max(proxy.size.width, 0),
                height: max(proxy.size.height, 0)
            )
        }
    }
}

enum SidebarPrimaryActionInputRouting {
    static func usesAppKitOwner(
        in presentationContext: SidebarPresentationContext,
        sourceID: String? = nil,
        hasMiddleClick: Bool = false
    ) -> Bool {
        presentationContext.inputMode == .collapsedOverlay || sourceID != nil || hasMiddleClick
    }
}

private struct SumiAppKitContextMenuModifier: ViewModifier {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext

    let isEnabled: Bool
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            SumiAppKitContextMenuOverlay(
                controller: windowState.sidebarContextMenuController,
                isEnabled: isEnabled && presentationContext.allowsInteractiveWork,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
        }
    }
}

extension View {
    func sidebarAppKitContextMenu(
        isEnabled: Bool = true,
        isInteractionEnabled: Bool = true,
        surfaceKind: SidebarContextMenuSurfaceKind = .row,
        triggers: SidebarContextMenuTriggers = [.rightClick],
        dragSource: SidebarDragSourceConfiguration? = nil,
        primaryActionExclusionZones: [SidebarDragSourceExclusionZone] = [],
        pageActivation: (() -> Void)? = nil,
        releaseAction: (() -> Void)? = nil,
        showsPressVisual: Bool = true,
        onMiddleClick: (() -> Void)? = nil,
        sourceID: String? = nil,
        suppressesActionAnimation: Bool? = nil,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(
            SidebarAppKitItemModifier(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: isEnabled,
                    surfaceKind: surfaceKind,
                    triggers: triggers,
                    entries: entries,
                    onMenuVisibilityChanged: onMenuVisibilityChanged
                ),
                dragSource: dragSource,
                primaryActionExclusionZones: primaryActionExclusionZones,
                pageActivation: pageActivation,
                releaseAction: releaseAction,
                showsPressVisual: showsPressVisual,
                onMiddleClick: onMiddleClick,
                sourceID: sourceID,
                isInteractionEnabled: isInteractionEnabled,
                suppressesActionAnimation: suppressesActionAnimation
            )
        )
    }

    func sidebarAppKitPrimaryAction(
        isEnabled: Bool = true,
        isInteractionEnabled: Bool = true,
        sourceID: String? = nil,
        routingPriorityBoost: Int = 0,
        onMiddleClick: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            SidebarAppKitPrimaryActionModifier(
                isEnabled: isEnabled,
                isInteractionEnabled: isInteractionEnabled,
                sourceID: sourceID,
                routingPriorityBoost: routingPriorityBoost,
                onMiddleClick: onMiddleClick,
                action: action
            )
        )
    }

    func sidebarAppKitBackgroundContextMenu(
        controller: SidebarContextMenuController,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        background(
            SidebarBackgroundMenuConfigurationBridge(
                controller: controller,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
            .frame(width: 0, height: 0)
        )
    }

    func sumiAppKitContextMenu(
        isEnabled: Bool = true,
        entries: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(
            SumiAppKitContextMenuModifier(
                isEnabled: isEnabled,
                entries: entries,
                onMenuVisibilityChanged: onMenuVisibilityChanged
            )
        )
    }
}
