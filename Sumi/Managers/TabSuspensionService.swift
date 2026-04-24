import Foundation
import WebKit

struct TabSuspensionResult: Equatable {
    let level: SumiMemoryPressureLevel
    let candidateCount: Int
    let suspendedCount: Int
    let suspendedTabIDs: [UUID]
}

@MainActor
final class TabSuspensionService {
    private static let defaultMinimumInactiveInterval: TimeInterval = 10 * 60

    private struct Candidate {
        let tab: Tab
        let webViews: [WKWebView]
    }

    private weak var browserManager: BrowserManager?
    private let memoryMonitor: SumiMemoryPressureMonitoring?
    private let dateProvider: () -> Date

    init(
        memoryMonitor: SumiMemoryPressureMonitoring?,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryMonitor = memoryMonitor
        self.dateProvider = dateProvider
        self.memoryMonitor?.eventHandler = { [weak self] level in
            self?.handleMemoryPressure(level)
        }
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        memoryMonitor?.start()
    }

    @discardableResult
    func handleMemoryPressure(_ level: SumiMemoryPressureLevel) -> TabSuspensionResult {
        let signpostState = PerformanceTrace.beginInterval("TabSuspension.memoryPressure")
        defer {
            PerformanceTrace.endInterval("TabSuspension.memoryPressure", signpostState)
        }

        PerformanceTrace.emitEvent("TabSuspension.memoryPressureEvent")

        let inactiveCutoff = dateProvider().addingTimeInterval(-Self.defaultMinimumInactiveInterval)
        let candidates = suspensionCandidates(inactiveBefore: inactiveCutoff)
        PerformanceTrace.emitEvent("TabSuspension.candidatesRanked")

        let suspensionLimit: Int
        switch level {
        case .warning:
            suspensionLimit = min(1, candidates.count)
        case .critical:
            suspensionLimit = candidates.count
        }

        var suspendedTabIDs: [UUID] = []
        for candidate in candidates.prefix(suspensionLimit) {
            guard suspend(candidate.tab, reason: "memory-pressure-\(level.rawValue)") else {
                continue
            }
            suspendedTabIDs.append(candidate.tab.id)
        }

        PerformanceTrace.emitEvent("TabSuspension.tabsSuspended")
        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "memoryPressure level=\(level.rawValue) candidates=\(candidates.count) suspended=\(suspendedTabIDs.count)"
        }

        return TabSuspensionResult(
            level: level,
            candidateCount: candidates.count,
            suspendedCount: suspendedTabIDs.count,
            suspendedTabIDs: suspendedTabIDs
        )
    }

    @discardableResult
    func suspend(_ tab: Tab, reason: String) -> Bool {
        guard let browserManager,
              let coordinator = browserManager.webViewCoordinator
        else { return false }

        let visibleIDs = visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
            $0.formUnion($1)
        }
        let selectedIDs = selectedTabIDs()
        let liveWebViews = coordinator.liveWebViews(for: tab)
        guard isEligible(tab, liveWebViews: liveWebViews, visibleTabIDs: visibleIDs, selectedTabIDs: selectedIDs) else {
            return false
        }

        guard coordinator.suspendWebViews(for: tab, reason: reason) else {
            return false
        }

        tab.markSuspended(at: dateProvider())
        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "suspended tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)"
        }
        return true
    }

    func suspensionCandidateTabIDsForTesting() -> [UUID] {
        suspensionCandidates().map { $0.tab.id }
    }

    private func suspensionCandidates(inactiveBefore cutoffDate: Date? = nil) -> [Candidate] {
        guard let browserManager,
              let coordinator = browserManager.webViewCoordinator
        else { return [] }

        let visibleIDs = visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
            $0.formUnion($1)
        }
        let selectedIDs = selectedTabIDs()

        return allKnownTabs()
            .compactMap { tab -> Candidate? in
                let webViews = coordinator.liveWebViews(for: tab)
                guard isEligible(
                    tab,
                    liveWebViews: webViews,
                    visibleTabIDs: visibleIDs,
                    selectedTabIDs: selectedIDs
                ) else {
                    return nil
                }
                if let cutoffDate,
                   let lastSelectedAt = tab.lastSelectedAt,
                   lastSelectedAt >= cutoffDate {
                    return nil
                }
                return Candidate(tab: tab, webViews: webViews)
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.tab.lastSelectedAt ?? .distantPast
                let rightDate = rhs.tab.lastSelectedAt ?? .distantPast
                if leftDate != rightDate {
                    return leftDate < rightDate
                }
                return lhs.tab.id.uuidString < rhs.tab.id.uuidString
            }
    }

    private func isEligible(
        _ tab: Tab,
        liveWebViews: [WKWebView],
        visibleTabIDs: Set<UUID>,
        selectedTabIDs: Set<UUID>
    ) -> Bool {
        guard tab.requiresPrimaryWebView else { return false }
        guard isSuspensibleContentURL(tab.url) else { return false }
        guard !isPinned(tab) else { return false }
        guard !tab.isPopupHost else { return false }
        guard !tab.isSuspended else { return false }
        guard !liveWebViews.isEmpty else { return false }
        guard !visibleTabIDs.contains(tab.id) else { return false }
        guard !selectedTabIDs.contains(tab.id) else { return false }
        guard !tab.isLoading else { return false }
        guard !tab.audioState.isPlayingAudio else { return false }

        for webView in liveWebViews {
            guard canSuspend(webView) else { return false }
        }
        return true
    }

    private func isSuspensibleContentURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func isPinned(_ tab: Tab) -> Bool {
        if tab.isPinned || tab.isSpacePinned || tab.isShortcutLiveInstance {
            return true
        }

        guard let tabManager = browserManager?.tabManager else { return false }
        return tabManager.isGlobalPinned(tab) || tabManager.isSpacePinned(tab)
    }

    private func canSuspend(_ webView: WKWebView) -> Bool {
        guard let coordinator = browserManager?.webViewCoordinator else { return false }
        guard !coordinator.isWebViewProtectedFromCompositorMutation(webView) else { return false }
        guard !webView.isLoading else { return false }
        guard !webView.sumiAudioIsPlayingAudio else { return false }
        guard webView.cameraCaptureState == .none else { return false }
        guard webView.microphoneCaptureState == .none else { return false }
        guard !webView.sumiIsInFullscreenElementPresentation else { return false }
        return true
    }

    private func allKnownTabs() -> [Tab] {
        guard let browserManager else { return [] }

        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        browserManager.tabManager.allTabs().forEach(append)
        (browserManager.windowRegistry?.windows.values.map { $0 } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }

    private func selectedTabIDs() -> Set<UUID> {
        guard let browserManager else { return [] }

        var selectedIDs = Set<UUID>()
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            if let current = browserManager.currentTab(for: windowState) {
                selectedIDs.insert(current.id)
            }
        }
        if let current = browserManager.tabManager.currentTab {
            selectedIDs.insert(current.id)
        }
        return selectedIDs
    }

    private func visibleTabIDsByWindow() -> [UUID: Set<UUID>] {
        guard let browserManager else { return [:] }

        var visible: [UUID: Set<UUID>] = [:]
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                isSplit: browserManager.splitManager.isSplit(for: windowState.id),
                leftTabId: browserManager.splitManager.leftTabId(for: windowState.id),
                rightTabId: browserManager.splitManager.rightTabId(for: windowState.id),
                isPreviewActive: browserManager.splitManager.getSplitState(for: windowState.id).isPreviewActive
            )
            visible[windowState.id] = Set(tabIDs)
        }
        return visible
    }
}
