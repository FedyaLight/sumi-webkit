import AppKit
import Foundation
//
//  WindowUtils.swift
//  Sumi
//
//
import SwiftUI

extension View {
    func backgroundDraggable(sidebarDragState: SidebarDragState) -> some View {
        modifier(BackgroundDraggableModifier(gesture: WindowDragGesture(sidebarDragState: sidebarDragState)))
    }
}

private struct BackgroundDraggableModifier<G: Gesture>: ViewModifier {
    let gesture: G

    func body(content: Content) -> some View {
        content
            .gesture(
                gesture
            )
    }
}

struct WindowDragGesture: Gesture {
    let sidebarDragState: SidebarDragState

    var body: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                if !sidebarDragState.isDragging {
                    if let event = NSApp.currentEvent,
                       let window = event.window ?? NSApp.keyWindow {
                        if event.clickCount == 2 {
                            window.performZoom(nil)
                            return
                        }
                        window.performDrag(with: event)
                    }
                }
            }
    }
}
