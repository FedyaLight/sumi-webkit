import AppKit
import Foundation

@MainActor
private final class SidebarSharingServicePickerRetainer {
    private var bridges: [ObjectIdentifier: SidebarSharingServicePickerBridge] = [:]

    func retain(_ bridge: SidebarSharingServicePickerBridge) {
        bridges[ObjectIdentifier(bridge)] = bridge
    }

    func release(_ bridge: SidebarSharingServicePickerBridge) {
        bridges.removeValue(forKey: ObjectIdentifier(bridge))
    }
}

@MainActor
private let sidebarSharingServicePickerRetainer = SidebarSharingServicePickerRetainer()

@MainActor
private final class SidebarSharingServicePickerBridge: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    private let token: SidebarTransientSessionToken
    private weak var coordinator: SidebarTransientSessionCoordinator?
    private var hasFinished = false

    init(
        token: SidebarTransientSessionToken,
        coordinator: SidebarTransientSessionCoordinator
    ) {
        self.token = token
        self.coordinator = coordinator
        super.init()
        sidebarSharingServicePickerRetainer.retain(self)
    }

    func sharingServicePicker(
        _ _: NSSharingServicePicker,
        didChoose _: NSSharingService?
    ) {
        finish()
    }

    func scheduleFallbackFinish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        coordinator?.finishSession(
            token,
            reason: "SidebarSharingServicePickerBridge.finish"
        )
        sidebarSharingServicePickerRetainer.release(self)
    }
}

/// AppKit sharing-service picker presentation for sidebar / URL-bar share actions.
@MainActor
final class BrowserSharingPickerPresentationOwner {
    private let windows: WindowRegistry

    init(windows: WindowRegistry) {
        self.windows = windows
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        guard let contentView = source.window?.contentView ?? modalPresentationWindow(for: source)?.contentView else {
            return
        }

        let picker = NSSharingServicePicker(items: items)
        let bridge = source.coordinator.flatMap {
            SidebarSharingServicePickerBridge(
                token: $0.beginSession(
                    kind: .sharingPicker,
                    source: source,
                    path: "BrowserSharingPickerPresentationOwner.present"
                ),
                coordinator: $0
            )
        }
        picker.delegate = bridge

        let anchorView: NSView
        let anchorRect: NSRect
        if let ownerView = source.originOwnerView,
           ownerView.window != nil,
           ownerView.superview != nil,
           !ownerView.isHiddenOrHasHiddenAncestor,
           ownerView.alphaValue > 0 {
            anchorView = ownerView
            anchorRect = ownerView.bounds
        } else {
            anchorView = contentView
            anchorRect = NSRect(
                x: contentView.bounds.midX,
                y: contentView.bounds.midY,
                width: 1,
                height: 1
            )
        }
        picker.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .minY)
        bridge?.scheduleFallbackFinish()
    }

    private func modalPresentationWindow(
        for source: SidebarTransientPresentationSource? = nil
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? windows.activeWindow.flatMap { windows.appKitWindow(for: $0) }
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
    }
}
