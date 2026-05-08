import AppKit
import SwiftUI

private enum CommandPalettePanelFrameResolver {
    @MainActor
    static func panelFrame(in parentWindow: NSWindow) -> NSRect? {
        guard let contentFrame = TransientChromePanelFrameResolver.parentContentScreenFrame(
            in: parentWindow
        ) else { return nil }

        let panelWidth = CommandPaletteLayoutPolicy.panelWidth(
            availableWindowWidth: contentFrame.width
        )
        let panelHeight = CommandPaletteLayoutPolicy.panelHeight
        return NSRect(
            x: contentFrame.midX - panelWidth / 2,
            y: contentFrame.midY - panelHeight / 2,
            width: panelWidth,
            height: panelHeight
        )
    }
}

@MainActor
final class CommandPalettePanelController {
    private var panelWindow: TransientChromePanelWindow?
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let parentObserver = TransientChromeParentWindowObserver()
    private weak var anchorView: NSView?
    private weak var attachedParentWindow: NSWindow?
    private var currentRoot = AnyView(EmptyView())
    private var currentIsPresented = false
    private var isSuspendedForParentSheet = false

    func update(
        parentWindow: NSWindow?,
        anchorView: NSView,
        root: AnyView,
        isPresented: Bool
    ) {
        self.anchorView = anchorView
        currentRoot = root
        currentIsPresented = isPresented

        guard isPresented, let parentWindow else {
            orderOutAndDetach(destroyWindow: true)
            return
        }

        bindParentWindow(parentWindow)

        if isSuspendedForParentSheet || !parentWindow.sheets.isEmpty {
            isSuspendedForParentSheet = true
            orderOutAndDetach(destroyWindow: false, restoreParentKey: false)
            return
        }

        let panel = ensurePanelWindow()
        TransientChromePanelConfiguration.configure(panel, for: parentWindow)

        hostingController.rootView = root
        if panel.contentViewController !== hostingController {
            panel.contentViewController = hostingController
        }

        syncFrame()
        attachAndShow(panel, to: parentWindow)
    }

    func parentWindowDidChange(_ parentWindow: NSWindow?, anchorView: NSView) {
        update(
            parentWindow: parentWindow,
            anchorView: anchorView,
            root: currentRoot,
            isPresented: currentIsPresented
        )
    }

    func teardown() {
        orderOutAndDetach(destroyWindow: true)
        unbindParentWindow()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    private func ensurePanelWindow() -> TransientChromePanelWindow {
        if let panelWindow {
            return panelWindow
        }
        let panel = TransientChromePanelConfiguration.makePanel()
        panelWindow = panel
        return panel
    }

    private func syncFrame() {
        guard let panelWindow,
              let parentWindow = parentObserver.parentWindow ?? attachedParentWindow ?? anchorView?.window,
              let frame = CommandPalettePanelFrameResolver.panelFrame(in: parentWindow)
        else { return }

        guard panelWindow.frame != frame else { return }
        panelWindow.setFrame(frame, display: panelWindow.isVisible)
    }

    private func attachAndShow(_ panel: TransientChromePanelWindow, to parentWindow: NSWindow) {
        if attachedParentWindow !== parentWindow {
            detachFromParent()
        }

        if parentWindow.childWindows?.contains(panel) != true {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        attachedParentWindow = parentWindow
        panel.orderFront(nil)
        panel.makeKey()
        syncFrame()
    }

    private func orderOutAndDetach(destroyWindow: Bool, restoreParentKey: Bool = true) {
        let parentWindow = attachedParentWindow
        detachFromParent()
        panelWindow?.orderOut(nil)
        hostingController.rootView = AnyView(EmptyView())
        if restoreParentKey {
            parentWindow?.makeKey()
        }

        if destroyWindow {
            panelWindow?.contentViewController = nil
            panelWindow = nil
            unbindParentWindow()
        }
    }

    private func detachFromParent() {
        guard let panelWindow, let attachedParentWindow else {
            self.attachedParentWindow = nil
            return
        }

        if attachedParentWindow.childWindows?.contains(panelWindow) == true {
            attachedParentWindow.removeChildWindow(panelWindow)
        }
        self.attachedParentWindow = nil
    }

    private func bindParentWindow(_ parentWindow: NSWindow) {
        parentObserver.bind(
            to: parentWindow,
            onGeometryChange: { [weak self] in
                self?.syncFrame()
            },
            onWillClose: { [weak self] in
                self?.teardown()
            },
            onSheetBegin: { [weak self] in
                self?.suspendForParentSheet()
            },
            onSheetEnd: { [weak self] in
                self?.resumeAfterParentSheet()
            }
        )
    }

    private func suspendForParentSheet() {
        isSuspendedForParentSheet = true
        orderOutAndDetach(destroyWindow: false, restoreParentKey: false)
    }

    private func resumeAfterParentSheet() {
        isSuspendedForParentSheet = false
        guard let anchorView else { return }
        update(
            parentWindow: parentObserver.parentWindow ?? attachedParentWindow,
            anchorView: anchorView,
            root: currentRoot,
            isPresented: currentIsPresented
        )
    }

    private func unbindParentWindow() {
        parentObserver.unbind()
        isSuspendedForParentSheet = false
    }
}

struct CommandPalettePanelHost: NSViewRepresentable {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var colorScheme: ColorScheme
    var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TransientChromePanelAnchorView {
        let view = TransientChromePanelAnchorView(frame: .zero)
        view.onWindowChanged = { [weak controller = context.coordinator.controller] window in
            MainActor.assumeIsolated {
                controller?.parentWindowDidChange(window, anchorView: view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: TransientChromePanelAnchorView, context: Context) {
        context.coordinator.controller.update(
            parentWindow: nsView.window ?? windowState.window,
            anchorView: nsView,
            root: rootView,
            isPresented: isPresented
        )
    }

    static func dismantleNSView(_ nsView: TransientChromePanelAnchorView, coordinator: Coordinator) {
        coordinator.controller.teardown()
    }

    private var rootView: AnyView {
        AnyView(
            CommandPaletteView()
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(commandPalette)
                .environment(\.sumiSettings, sumiSettings)
                .environment(\.resolvedThemeContext, resolvedThemeContext)
                .environment(\.colorScheme, colorScheme)
        )
    }

    @MainActor
    final class Coordinator {
        let controller = CommandPalettePanelController()
    }
}
