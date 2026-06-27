import AppKit
import SwiftUI

enum SumiBoostEditorMetrics {
    static let normalWidth: CGFloat = 204
    static let codeWidth: CGFloat = 392
    static let height: CGFloat = 582
}

@MainActor
final class SumiBoostEditorPanelController: NSObject, NSWindowDelegate {
    private weak var parentWindow: NSWindow?
    private var panel: NSPanel?
    private var session: SumiBoostEditorSession?

    func present(
        boost: SumiBoost,
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState,
        module: SumiBoostsModule
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

        let panel = self.panel ?? makePanel()
        panel.contentViewController = NSHostingController(
            rootView: SumiBoostEditorView(session: session)
        )
        if parentWindow !== windowState.window {
            parentWindow?.removeChildWindow(panel)
            parentWindow = windowState.window
            windowState.window?.addChildWindow(panel, ordered: .above)
        }
        self.panel = panel
        panel.delegate = self
        resizePanel(forCodeMode: false, animated: false)
        centerPanel(over: windowState.window)
        panel.makeKeyAndOrderFront(nil)
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
        let midpoint = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = frameSize
        frame.origin.x = midpoint.x - frameSize.width / 2
        frame.origin.y = midpoint.y - frameSize.height / 2
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func centerPanel(over parent: NSWindow?) {
        guard let panel else { return }
        let referenceFrame = parent?.frame
            ?? parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let visibleFrame = parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? referenceFrame

        var origin = NSPoint(
            x: referenceFrame.midX - panel.frame.width / 2,
            y: referenceFrame.midY - panel.frame.height / 2
        )
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
    }
}
