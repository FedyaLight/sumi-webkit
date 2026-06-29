import AppKit
import Foundation

@MainActor
private final class SidebarSharingServicePickerRetainer {
    static let shared = SidebarSharingServicePickerRetainer()

    private var bridges: [ObjectIdentifier: SidebarSharingServicePickerBridge] = [:]

    func retain(_ bridge: SidebarSharingServicePickerBridge) {
        bridges[ObjectIdentifier(bridge)] = bridge
    }

    func release(_ bridge: SidebarSharingServicePickerBridge) {
        bridges.removeValue(forKey: ObjectIdentifier(bridge))
    }
}

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
        SidebarSharingServicePickerRetainer.shared.retain(self)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
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
        SidebarSharingServicePickerRetainer.shared.release(self)
    }
}

@MainActor
final class BrowserNativeDialogPresentationOwner {
    struct Dependencies {
        let windowRegistry: @MainActor @Sendable () -> WindowRegistry?
        let nativeModalPresentation: @MainActor @Sendable () -> BrowserNativeModalPresentation?
        let setNativeModalPresentation: @MainActor @Sendable (BrowserNativeModalPresentation?) -> Void
        let postCollapsedSidebarOverlayDismissal: @MainActor @Sendable () -> Void
        let dismissFloatingBarForActiveWindow: @MainActor @Sendable (Bool) -> Void
        let dismissWorkspaceThemePickerIfNeededDiscarding: @MainActor @Sendable () -> Void
        let dismissWorkspaceThemePickerIfNeededCommitting: @MainActor @Sendable () -> Void
        let terminateApplication: @MainActor @Sendable () -> Void
        let keyWindow: @MainActor @Sendable () -> NSWindow?
        let mainWindow: @MainActor @Sendable () -> NSWindow?
        let recoverSidebarHost: @MainActor @Sendable (NSWindow?) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func requestCollapsedSidebarOverlayDismissal() {
        dependencies.postCollapsedSidebarOverlayDismissal()
    }

    func showQuitDialog() {
        requestCollapsedSidebarOverlayDismissal()
        dependencies.dismissFloatingBarForActiveWindow(true)
        dependencies.dismissWorkspaceThemePickerIfNeededCommitting()
        dependencies.terminateApplication()
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        _ = presentNativeModal(.browsingData, windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        presentNativeModal(
            .basicAuth(session),
            windowState: windowState,
            onDismiss: {
                session.cancel()
            }
        )
    }

    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) {
        _ = presentNativeModal(.notice(notice), source: source)
    }

    func dismissNativeModalPresentation() {
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.dismissNativeModalPresentation",
            invokeOnDismiss: false
        )
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        dismissNativeModalPresentation(
            for: windowID,
            reason: "BrowserManager.nativeModalPresentationBindingDismissed",
            invokeOnDismiss: true
        )
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        guard let presentation = dependencies.nativeModalPresentation() else { return false }
        guard let windowID else { return true }
        return presentation.windowID == windowID
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        guard let presentation = dependencies.nativeModalPresentation() else { return false }
        guard let window else { return true }
        if let presentedWindow = presentation.window {
            return presentedWindow === window
        }
        return dependencies.windowRegistry()?.windows[presentation.windowID]?.window === window
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
                    path: "BrowserManager.presentSharingServicePicker"
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

    private func prepareForNativeModalPresentation() {
        requestCollapsedSidebarOverlayDismissal()
        dependencies.dismissWorkspaceThemePickerIfNeededDiscarding()
    }

    @discardableResult
    private func presentNativeModal(
        _ kind: BrowserNativeModalKind,
        windowState: BrowserWindowState? = nil,
        source: SidebarTransientPresentationSource? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        prepareForNativeModalPresentation()
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.presentNativeModalReplacingExisting",
            invokeOnDismiss: true
        )

        let targetWindowState = windowState ?? dependencies.windowRegistry()?.activeWindow
        let windowID = source?.windowID ?? targetWindowState?.id
        guard let windowID else { return false }

        let window = source?.window?.parent
            ?? source?.window
            ?? targetWindowState?.window
            ?? modalPresentationWindow(for: source)
        let transientSessionToken: SidebarTransientSessionToken?
        if let source {
            transientSessionToken = source.coordinator?.beginSession(
                kind: .dialog,
                source: source,
                path: "BrowserManager.presentNativeModal"
            )
        } else {
            transientSessionToken = nil
        }

        dependencies.setNativeModalPresentation(
            BrowserNativeModalPresentation(
                windowID: windowID,
                window: window,
                kind: kind,
                source: source,
                transientSessionToken: transientSessionToken,
                onDismiss: onDismiss
            )
        )
        return true
    }

    private func dismissNativeModalPresentation(
        for windowID: UUID?,
        reason: String,
        invokeOnDismiss: Bool
    ) {
        guard let presentation = dependencies.nativeModalPresentation() else { return }
        guard windowID == nil || presentation.windowID == windowID else { return }

        dependencies.setNativeModalPresentation(nil)

        if let transientSessionToken = presentation.transientSessionToken,
           let coordinator = presentation.source?.coordinator {
            coordinator.finishSession(
                transientSessionToken,
                reason: reason
            )
        } else {
            dependencies.recoverSidebarHost(presentation.window)
        }

        if invokeOnDismiss {
            presentation.onDismiss?()
        }
    }

    private func modalPresentationWindow(
        for source: SidebarTransientPresentationSource? = nil
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? dependencies.windowRegistry()?.activeWindow?.window
            ?? dependencies.keyWindow()
            ?? dependencies.mainWindow()
    }
}

extension BrowserNativeDialogPresentationOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            nativeModalPresentation: { [weak browserManager] in browserManager?.nativeModalPresentation },
            setNativeModalPresentation: { [weak browserManager] presentation in
                browserManager?.nativeModalPresentation = presentation
            },
            postCollapsedSidebarOverlayDismissal: { [weak browserManager] in
                guard let browserManager else { return }
                NotificationCenter.default.post(
                    name: .sumiShouldHideCollapsedSidebarOverlay,
                    object: browserManager
                )
            },
            dismissFloatingBarForActiveWindow: { [weak browserManager] preserveDraft in
                browserManager?.dismissFloatingBarForActiveWindow(preserveDraft: preserveDraft)
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededDiscarding()
            },
            dismissWorkspaceThemePickerIfNeededCommitting: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededCommitting()
            },
            terminateApplication: {
                NSApplication.shared.terminate(nil)
            },
            keyWindow: {
                NSApp.keyWindow
            },
            mainWindow: {
                NSApp.mainWindow
            },
            recoverSidebarHost: { window in
                SidebarHostRecoveryCoordinator.shared.recover(in: window)
            }
        )
    }
}
