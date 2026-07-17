import Foundation

@MainActor
final class GlanceTabCloseInterception {
    private let glanceManager: GlanceManager

    init(glanceManager: GlanceManager) {
        self.glanceManager = glanceManager
    }

    func interceptCurrentClose(in windowState: BrowserWindowState) -> Bool {
        guard glanceManager.activePreviewTab(for: windowState) != nil else {
            return false
        }
        glanceManager.dismissGlance()
        return true
    }

    func interceptSourceClose(_ tab: Tab) {
        guard glanceManager.currentSession?.sourceTab?.id == tab.id else {
            return
        }
        glanceManager.dismissGlance()
    }
}
