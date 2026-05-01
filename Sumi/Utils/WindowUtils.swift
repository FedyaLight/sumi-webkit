import AppKit
import Foundation
//
//  WindowUtils.swift
//  Sumi
//
//  Created by Maciek Bagiński on 31/07/2025.
//
import SwiftUI

func zoomCurrentWindow() {
    if let window = NSApp.keyWindow {
        window.zoom(nil)
    }
}

extension View {
    public func backgroundDraggable() -> some View {
        modifier(BackgroundDraggableModifier(gesture: WindowDragGesture()))
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
    var body: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                if !SidebarDragState.shared.isDragging {
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
