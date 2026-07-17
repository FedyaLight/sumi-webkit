import AppKit
import SwiftUI

enum SumiBoostEditorMetrics {
    static let normalWidth: CGFloat = 204
    static let codeWidth: CGFloat = 392
    static let height: CGFloat = 582
    static let sidebarGap: CGFloat = 12
}

@MainActor
final class SumiBoostEditorPanelController: NSObject, NSWindowDelegate {
    private struct PlacementContext {
        let sidebarPosition: SidebarPosition
        let sidebarWidth: CGFloat
        let isSidebarVisible: Bool
    }

    private weak var parentWindow: NSWindow?
    private var panel: NSPanel?
    private var session: SumiBoostEditorSession?
    private var placementContext = PlacementContext(
        sidebarPosition: .left,
        sidebarWidth: BrowserWindowState.sidebarDefaultWidth,
        isSidebarVisible: true
    )

    func present(
        boost: SumiBoost,
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState,
        sidebarPosition: SidebarPosition,
        module: SumiBoostsModule,
        settings: SumiSettingsService?,
        windowRegistry: WindowRegistry? = nil
    ) {
        let session = SumiBoostEditorSession(
            boost: boost,
            tab: tab,
            profile: profile,
            windowState: windowState,
            module: module,
            onClose: { [weak self] in
                self?.panel?.close()
            }
        )
        session.onCodeModeChange = { [weak self] isCodeMode in
            self?.resizePanel(forCodeMode: isCodeMode, animated: true)
        }
        self.session = session
        placementContext = PlacementContext(
            sidebarPosition: sidebarPosition,
            sidebarWidth: windowState.sidebarWidth,
            isSidebarVisible: windowState.isSidebarVisible
        )

        let panel = self.panel ?? makePanel()
        // The panel hosts a bare SwiftUI hierarchy: inject the space theme so
        // the editor (and its popovers) follow the space lightness instead of
        // the environment's dark default. Captured at present time.
        if let settings {
            panel.appearance = windowState.nativeSurfaceAppearance(
                settings: settings,
                in: windowRegistry
            )
            panel.contentViewController = NSHostingController(
                rootView: SumiBoostEditorView(session: session)
                    .sumiChromeThemeScope(
                        context: windowState.nativeSurfaceThemeContext(
                            settings: settings,
                            in: windowRegistry
                        ),
                        settings: settings
                    )
                    .environment(\.sumiSettings, settings)
            )
        } else {
            panel.contentViewController = NSHostingController(
                rootView: SumiBoostEditorView(session: session)
            )
        }
        let appKitWindow = windowState.shellWindow(in: windowRegistry)
        if parentWindow !== appKitWindow {
            parentWindow?.removeChildWindow(panel)
            parentWindow = appKitWindow
            appKitWindow?.addChildWindow(panel, ordered: .above)
        }
        self.panel = panel
        panel.delegate = self
        resizePanel(forCodeMode: false, animated: false)
        placePanel(alongside: appKitWindow)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        session?.close()
        session = nil
        if let panel {
            parentWindow?.removeChildWindow(panel)
        }
        parentWindow = nil
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SumiBoostEditorMetrics.normalWidth,
                height: SumiBoostEditorMetrics.height
            ),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Boost"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(
            width: SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        panel.maxSize = NSSize(
            width: SumiBoostEditorMetrics.codeWidth,
            height: SumiBoostEditorMetrics.height
        )
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func resizePanel(forCodeMode isCodeMode: Bool, animated: Bool) {
        guard let panel else { return }
        let contentSize = NSSize(
            width: isCodeMode ? SumiBoostEditorMetrics.codeWidth : SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var frame = panel.frame
        let previousFrame = frame
        frame.size = frameSize
        switch placementContext.sidebarPosition {
        case .left:
            frame.origin.x = previousFrame.minX
        case .right:
            frame.origin.x = previousFrame.maxX - frameSize.width
        }
        frame.origin.y = previousFrame.midY - frameSize.height / 2
        frame.origin = clampedOrigin(for: frame, parent: parentWindow)
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func placePanel(alongside parent: NSWindow?) {
        guard let panel else { return }
        let referenceFrame = parent?.frame
            ?? parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame

        let sidebarWidth = placementContext.isSidebarVisible ? placementContext.sidebarWidth : 0
        let x: CGFloat
        switch placementContext.sidebarPosition {
        case .left:
            x = referenceFrame.minX + sidebarWidth + SumiBoostEditorMetrics.sidebarGap
        case .right:
            x = referenceFrame.maxX - sidebarWidth - SumiBoostEditorMetrics.sidebarGap - panel.frame.width
        }

        let origin = clampedOrigin(
            for: NSRect(
                x: x,
                y: referenceFrame.midY - panel.frame.height / 2,
                width: panel.frame.width,
                height: panel.frame.height
            ),
            parent: parent
        )
        panel.setFrameOrigin(origin)
    }

    private func clampedOrigin(for frame: NSRect, parent: NSWindow?) -> NSPoint {
        let referenceFrame = parent?.frame
            ?? parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? frame
        let visibleFrame = parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? referenceFrame

        var origin = frame.origin
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return origin
    }
}
