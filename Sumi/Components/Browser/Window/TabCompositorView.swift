import AppKit
import Combine

// MARK: - Tab Compositor Manager
@MainActor
class TabCompositorManager: ObservableObject {
    /// Single timer: next tab idle deadline (`lastAccess` + `unloadTimeout`).
    private var scheduleTimer: Timer?
    private var scheduledFireDate: Date?
    private var lastAccessTimes: [UUID: Date] = [:]

    // Default unload timeout (5 minutes)
    var unloadTimeout: TimeInterval = 300

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimeoutChange),
            name: .tabUnloadTimeoutChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleTimeoutChange(_ notification: Notification) {
        if let timeout = notification.userInfo?["timeout"] as? TimeInterval {
            setUnloadTimeout(timeout)
        }
    }

    func setUnloadTimeout(_ timeout: TimeInterval) {
        self.unloadTimeout = timeout
        scheduleNextUnloadFire()
    }

    func markTabAccessed(_ tabId: UUID) {
        lastAccessTimes[tabId] = Date()
        scheduleNextUnloadFire()
    }

    func unloadTab(_ tab: Tab) {
        if browserManager?.isTabDisplayedInAnyWindow(tab.id) == true {
            markTabAccessed(tab.id)
            return
        }
        lastAccessTimes.removeValue(forKey: tab.id)
        tab.unloadWebView()
        scheduleNextUnloadFire()
    }

    func loadTab(_ tab: Tab) {
        if tab.representsSumiSettingsSurface {
            return
        }
        markTabAccessed(tab.id)
        tab.loadWebViewIfNeeded()
    }

    private func scheduleNextUnloadFire() {
        guard !lastAccessTimes.isEmpty else {
            invalidateScheduledTimer()
            return
        }

        let now = Date()
        guard let nextDeadline = lastAccessTimes.values.map({ $0.addingTimeInterval(unloadTimeout) }).min() else {
            invalidateScheduledTimer()
            return
        }

        if let scheduledFireDate,
           scheduleTimer != nil,
           scheduledFireDate <= nextDeadline
        {
            return
        }

        invalidateScheduledTimer()

        let delay = max(0.05, nextDeadline.timeIntervalSince(now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processDueUnloads()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
        scheduledFireDate = nextDeadline
    }

    private func processDueUnloads() {
        invalidateScheduledTimer()

        let now = Date()
        let deadline = now.addingTimeInterval(-unloadTimeout)
        let dueIds = lastAccessTimes.filter { $0.value <= deadline }.map(\.key)
        for tabId in dueIds {
            handleTabTimeout(tabId)
        }
        scheduleNextUnloadFire()
    }

    private func invalidateScheduledTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        scheduledFireDate = nil
    }

    private func handleTabTimeout(_ tabId: UUID) {
        guard let tab = findTab(by: tabId) else {
            lastAccessTimes.removeValue(forKey: tabId)
            return
        }

        if tab.isCurrentTab {
            lastAccessTimes[tabId] = Date()
            return
        }

        if browserManager?.isTabDisplayedInAnyWindow(tab.id) == true {
            lastAccessTimes[tabId] = Date()
            return
        }

        if tab.audioState.isPlayingAudio {
            lastAccessTimes[tabId] = Date()
            return
        }

        unloadTab(tab)
    }

    private func findTab(by id: UUID) -> Tab? {
        guard let browserManager = browserManager else { return nil }
        return browserManager.tabManager.tab(for: id)
    }

    // MARK: - Public Interface
    func updateTabVisibility(currentTabId: UUID?) {
        guard let browserManager = browserManager,
              let coordinator = browserManager.webViewCoordinator else { return }
        for (windowId, _) in coordinator.compositorContainers() {
            guard let windowState = browserManager.windowRegistry?.windows[windowId] else { continue }
            browserManager.refreshCompositor(for: windowState)
        }
    }

    /// Update tab visibility for a specific window
    func updateTabVisibility(for windowState: BrowserWindowState) {
        browserManager?.refreshCompositor(for: windowState)
    }

    // MARK: - Dependencies
    weak var browserManager: BrowserManager?
}
