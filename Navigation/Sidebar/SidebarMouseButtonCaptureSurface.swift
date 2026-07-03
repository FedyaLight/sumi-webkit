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

    static func spaceOffset(for event: NSEvent) -> Int? {
        guard event.type == .otherMouseDown else { return nil }
        return spaceOffset(for: event.buttonNumber)
    }

    static func shouldCapture(_ event: NSEvent) -> Bool {
        spaceOffset(for: event) != nil
    }
}

@MainActor
final class SidebarMouseButtonCaptureRegistry {
    static let shared = SidebarMouseButtonCaptureRegistry()

    private final class WeakCaptureView {
        weak var view: NSView?

        init(view: NSView) {
            self.view = view
        }
    }

    private var viewsByIdentifier: [ObjectIdentifier: WeakCaptureView] = [:]

    func register(_ view: NSView) {
        cleanupReleasedViews()
        viewsByIdentifier[ObjectIdentifier(view)] = WeakCaptureView(view: view)
    }

    func unregister(_ view: NSView) {
        viewsByIdentifier[ObjectIdentifier(view)] = nil
    }

    func containsWorkspaceMouseButtonEvent(_ event: NSEvent) -> Bool {
        guard SidebarMouseButtonWorkspaceNavigationPolicy.spaceOffset(for: event) != nil else {
            return false
        }

        return containsWorkspaceMouseButtonLocation(
            buttonNumber: event.buttonNumber,
            locationInWindow: event.locationInWindow,
            in: event.window
        )
    }

    func containsWorkspaceMouseButtonLocation(
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
            guard let view = registeredView.view,
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
                updateRegistryRegistration()
            }
        }

        override var isOpaque: Bool {
            false
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateRegistryRegistration()
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

        private func updateRegistryRegistration() {
            guard window != nil, isEnabled else {
                SidebarMouseButtonCaptureRegistry.shared.unregister(self)
                return
            }

            SidebarMouseButtonCaptureRegistry.shared.register(self)
        }
    }
}
