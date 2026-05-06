import AppKit
import SwiftUI

struct SidebarSwipeCaptureSurface: NSViewRepresentable {
    let isEnabled: Bool
    let onEvent: (SpaceSwipeGestureEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
    }
}

extension SidebarSwipeCaptureSurface {
    final class Coordinator: NSObject {
        var parent: SidebarSwipeCaptureSurface
        var tracker = SpaceSwipeGestureTracker()

        init(parent: SidebarSwipeCaptureSurface) {
            self.parent = parent
            super.init()
        }

        @MainActor
        func observeScrollWheel(
            _ event: NSEvent,
            in view: CaptureView
        ) -> Bool {
            let result = tracker.process(
                .init(event: event),
                width: view.bounds.width,
                isEnabled: parent.isEnabled
            )

            for emittedEvent in result.emittedEvents {
                parent.onEvent(emittedEvent)
            }

            switch result.handling {
            case .consume:
                return true
            case .forwardToUnderlying:
                return view.forwardScrollWheelToUnderlying(event)
            }
        }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?

        override var isOpaque: Bool {
            false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point),
                  NSApp.currentEvent?.type == .scrollWheel
            else {
                return nil
            }

            return self
        }

        override func scrollWheel(with event: NSEvent) {
            if coordinator?.observeScrollWheel(event, in: self) == true {
                return
            }

            super.scrollWheel(with: event)
        }

        func forwardScrollWheelToUnderlying(_ event: NSEvent) -> Bool {
            guard let target = underlyingScrollTarget(for: event) else {
                return false
            }

            target.scrollWheel(with: event)
            return true
        }

        private func underlyingScrollTarget(for event: NSEvent) -> NSView? {
            let locationInWindow = event.locationInWindow
            var currentView: NSView = self

            while let container = currentView.superview {
                let pointInContainer = container.convert(locationInWindow, from: nil)

                for sibling in container.subviews.reversed() {
                    guard sibling !== currentView else { continue }

                    let pointInSibling = sibling.convert(pointInContainer, from: container)
                    guard let hitView = sibling.hitTest(pointInSibling) else { continue }
                    guard hitView !== self, !hitView.isDescendant(of: self) else { continue }
                    return hitView
                }

                currentView = container
            }

            return nil
        }
    }
}
