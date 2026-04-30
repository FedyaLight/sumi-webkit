//
//  SidebarAppKitItemBridge.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SidebarAppKitItemBridge<Content: View>: NSViewRepresentable {
    let content: Content
    let controller: SidebarContextMenuController
    let configuration: SidebarAppKitItemConfiguration

    func makeNSView(context: Context) -> SidebarInteractiveItemView {
        let view = SidebarInteractiveItemView(frame: .zero)
        #if DEBUG
        SidebarDebugMetrics.recordSidebarAppKitItemBridgeAttached(ObjectIdentifier(view))
        #endif
        view.contextMenuController = controller
        view.update(rootView: AnyView(content), configuration: configuration)
        SidebarUITestDragMarker.recordEvent(
            "bridgeMake",
            dragItemID: configuration.dragSource?.item.tabId,
            ownerDescription: view.recoveryDebugDescription,
            sourceID: configuration.sourceID,
            viewDescription: view.debugViewDescription,
            details: "source=\(configuration.sourceID ?? "nil") inputEnabled=\(configuration.isInteractionEnabled) view=\(view.debugViewDescription) hostedRoot=\(view.hostedSidebarRootDebugDescription) controller=\(view.contextMenuControllerDebugDescription)"
        )
        return view
    }

    func updateNSView(_ nsView: SidebarInteractiveItemView, context: Context) {
        nsView.contextMenuController = controller
        nsView.update(rootView: AnyView(content), configuration: configuration)
    }

    static func dismantleNSView(_ nsView: SidebarInteractiveItemView, coordinator: ()) {
        #if DEBUG
        SidebarDebugMetrics.recordSidebarAppKitItemBridgeDetached(ObjectIdentifier(nsView))
        #endif
        SidebarUITestDragMarker.recordEvent(
            "bridgeDismantle",
            dragItemID: nsView.recoveryMetadata.dragItemID,
            ownerDescription: nsView.recoveryDebugDescription,
            sourceID: nsView.sourceID,
            viewDescription: nsView.debugViewDescription,
            details: "source=\(nsView.identifier?.rawValue ?? "nil") view=\(nsView.debugViewDescription) hostedRoot=\(nsView.hostedSidebarRootDebugDescription) controller=\(nsView.contextMenuControllerDebugDescription)"
        )
        nsView.prepareForDismantle()
    }
}
struct SidebarBackgroundMenuConfigurationBridge: NSViewRepresentable {
    let controller: SidebarContextMenuController
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        controller.configureBackgroundMenu(
            entriesProvider: entries,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.configureBackgroundMenu(
            entriesProvider: entries,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
    }
}

@MainActor
final class SumiAppKitContextMenuHostView: NSView {
    weak var controller: SidebarContextMenuController?
    var isContextMenuEnabled = true
    var entriesProvider: () -> [SidebarContextMenuEntry] = { [] }
    var onMenuVisibilityChanged: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard canHandleContextMenu(for: window?.currentEvent, at: point) else {
            return nil
        }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    func reset() {
        controller = nil
        isContextMenuEnabled = false
        entriesProvider = { [] }
        onMenuVisibilityChanged = { _ in }
    }

    func canHandleContextMenu(for event: NSEvent?, at point: NSPoint) -> Bool {
        guard isContextMenuEnabled,
              bounds.contains(point),
              controller != nil,
              entriesProvider().isEmpty == false,
              let event
        else {
            return false
        }

        switch event.type {
        case .rightMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    private func presentContextMenu(
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent
    ) {
        controller?.presentTransientMenu(
            entries: entriesProvider(),
            onMenuVisibilityChanged: onMenuVisibilityChanged,
            trigger: trigger,
            event: event,
            in: self
        )
    }
}

struct SumiAppKitContextMenuBridge: NSViewRepresentable {
    let controller: SidebarContextMenuController
    let isEnabled: Bool
    let entries: () -> [SidebarContextMenuEntry]
    let onMenuVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> SumiAppKitContextMenuHostView {
        let view = SumiAppKitContextMenuHostView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: SumiAppKitContextMenuHostView, context: Context) {
        update(nsView)
    }

    static func dismantleNSView(_ nsView: SumiAppKitContextMenuHostView, coordinator: ()) {
        nsView.reset()
    }

    private func update(_ view: SumiAppKitContextMenuHostView) {
        view.controller = controller
        view.isContextMenuEnabled = isEnabled
        view.entriesProvider = entries
        view.onMenuVisibilityChanged = onMenuVisibilityChanged
    }
}
