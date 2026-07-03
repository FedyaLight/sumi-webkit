import AppKit
import SwiftUI

enum SidebarMouseButtonWorkspaceNavigationPolicy {
    static func spaceOffset(for buttonNumber: Int) -> Int? {
        switch buttonNumber {
        case 3:
            return -1
        case 4:
            return 1
        default:
            return nil
        }
    }

    static func shouldCapture(_ event: NSEvent) -> Bool {
        event.type == .otherMouseDown && spaceOffset(for: event.buttonNumber) != nil
    }
}

@MainActor
final class SidebarMouseButtonCaptureRegistry {
    static let shared = SidebarMouseButtonCaptureRegistry()

    private final class WeakCaptureView {
        weak var view: NSView?
        var isEnabled: Bool

        init(view: NSView, isEnabled: Bool) {
            self.view = view
            self.isEnabled = isEnabled
        }
    }

    private var viewsByIdentifier: [ObjectIdentifier: WeakCaptureView] = [:]

    func register(_ view: NSView, isEnabled: Bool) {
        cleanupReleasedViews()
        viewsByIdentifier[ObjectIdentifier(view)] = WeakCaptureView(view: view, isEnabled: isEnabled)
    }

    func unregister(_ view: NSView) {
        viewsByIdentifier[ObjectIdentifier(view)] = nil
    }

    func setEnabled(_ isEnabled: Bool, for view: NSView) {
        let identifier = ObjectIdentifier(view)
        if let registeredView = viewsByIdentifier[identifier] {
            registeredView.isEnabled = isEnabled
        } else {
            viewsByIdentifier[identifier] = WeakCaptureView(view: view, isEnabled: isEnabled)
        }
        cleanupReleasedViews()
    }

    func containsWorkspaceMouseButtonEvent(_ event: NSEvent) -> Bool {
        containsWorkspaceMouseButtonEvent(
            buttonNumber: event.buttonNumber,
            locationInWindow: event.locationInWindow,
            in: event.window
        )
    }

    func containsWorkspaceMouseButtonEvent(
        buttonNumber: Int,
        locationInWindow: CGPoint,
        in eventWindow: NSWindow?
    ) -> Bool {
        guard SidebarMouseButtonWorkspaceNavigationPolicy.spaceOffset(for: buttonNumber) != nil,
              let eventWindow
        else {
            return false
        }

        cleanupReleasedViews()

        return viewsByIdentifier.values.contains { registeredView in
            guard registeredView.isEnabled,
                  let view = registeredView.view,
                  view.window === eventWindow,
                  !view.isHiddenOrHasHiddenAncestor
            else {
                return false
            }

            return view.convert(view.bounds, to: nil).contains(locationInWindow)
        }
    }

    private func cleanupReleasedViews() {
        viewsByIdentifier = viewsByIdentifier.filter { $0.value.view != nil }
    }
}

struct SidebarMouseButtonCaptureSurface: NSViewRepresentable {
    let isEnabled: Bool
    let onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.coordinator = context.coordinator
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.isEnabled = isEnabled
    }
}

extension SidebarMouseButtonCaptureSurface {
    final class Coordinator: NSObject {
        var parent: SidebarMouseButtonCaptureSurface

        init(parent: SidebarMouseButtonCaptureSurface) {
            self.parent = parent
            super.init()
        }

        @MainActor
        func handleOtherMouseDown(_ event: NSEvent) -> Bool {
            guard parent.isEnabled,
                  let offset = SidebarMouseButtonWorkspaceNavigationPolicy.spaceOffset(
                    for: event.buttonNumber
                  )
            else {
                return false
            }

            parent.onNavigate(offset)
            return true
        }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        var isEnabled = false {
            didSet {
                SidebarMouseButtonCaptureRegistry.shared.setEnabled(isEnabled, for: self)
            }
        }

        override var isOpaque: Bool {
            false
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                SidebarMouseButtonCaptureRegistry.shared.unregister(self)
            } else {
                SidebarMouseButtonCaptureRegistry.shared.register(self, isEnabled: isEnabled)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isEnabled,
                  bounds.contains(point),
                  let event = NSApp.currentEvent,
                  SidebarMouseButtonWorkspaceNavigationPolicy.shouldCapture(event)
            else {
                return nil
            }

            return self
        }

        override func otherMouseDown(with event: NSEvent) {
            if coordinator?.handleOtherMouseDown(event) == true {
                return
            }

            super.otherMouseDown(with: event)
        }
    }
}
