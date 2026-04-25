import Foundation
import WebKit

struct TabSuspensionResult: Equatable {
    let level: SumiMemoryPressureLevel
    let candidateCount: Int
    let suspendedCount: Int
    let suspendedTabIDs: [UUID]
}

enum TabSuspensionEligibility: Equatable {
    case eligible
    case ineligible(reason: Reason)

    enum Reason: Equatable {
        case selected
        case visible
        case loading
        case playingAudio
        case cameraCapture
        case microphoneCapture
        case fullscreen
        case pictureInPicture
        case pdfDocument
        case unsupportedURLScheme
        case pageVeto
        case noLiveWebView
        case alreadySuspended
        case popupHost
        case noPrimaryWebView
        case compositorProtected
        case launcherRuntimeSuspensionDeferred
    }

    var isEligible: Bool {
        self == .eligible
    }
}

struct TabSuspensionWebViewState: Equatable {
    let isLoading: Bool
    let isPlayingAudio: Bool
    let isCapturingCamera: Bool
    let isCapturingMicrophone: Bool
    let isFullscreen: Bool
    let isPictureInPicture: Bool
    let isPDFDocument: Bool
    let isProtectedFromCompositorMutation: Bool

    init(
        isLoading: Bool = false,
        isPlayingAudio: Bool = false,
        isCapturingCamera: Bool = false,
        isCapturingMicrophone: Bool = false,
        isFullscreen: Bool = false,
        isPictureInPicture: Bool = false,
        isPDFDocument: Bool = false,
        isProtectedFromCompositorMutation: Bool = false
    ) {
        self.isLoading = isLoading
        self.isPlayingAudio = isPlayingAudio
        self.isCapturingCamera = isCapturingCamera
        self.isCapturingMicrophone = isCapturingMicrophone
        self.isFullscreen = isFullscreen
        self.isPictureInPicture = isPictureInPicture
        self.isPDFDocument = isPDFDocument
        self.isProtectedFromCompositorMutation = isProtectedFromCompositorMutation
    }

    @MainActor
    init(webView: WKWebView, tab: Tab, coordinator: WebViewCoordinator) {
        self.init(
            isLoading: webView.isLoading,
            isPlayingAudio: webView.sumiAudioIsPlayingAudio,
            isCapturingCamera: webView.cameraCaptureState != .none,
            isCapturingMicrophone: webView.microphoneCaptureState != .none,
            isFullscreen: webView.sumiIsInFullscreenElementPresentation,
            isPictureInPicture: tab.hasPictureInPictureVideo,
            isPDFDocument: tab.isDisplayingPDFDocument,
            isProtectedFromCompositorMutation: coordinator.isWebViewProtectedFromCompositorMutation(webView)
        )
    }
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
        guard suspensionEligibility(
            for: tab,
            liveWebViews: liveWebViews,
            visibleTabIDs: visibleIDs,
            selectedTabIDs: selectedIDs
        ).isEligible else {
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

    func suspensionEligibility(for tab: Tab) -> TabSuspensionEligibility {
        guard let browserManager,
              let coordinator = browserManager.webViewCoordinator
        else {
            return .ineligible(reason: .noLiveWebView)
        }

        return suspensionEligibility(
            for: tab,
            liveWebViews: coordinator.liveWebViews(for: tab),
            visibleTabIDs: visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
                $0.formUnion($1)
            },
            selectedTabIDs: selectedTabIDs()
        )
    }

    func suspensionEligibility(
        for tab: Tab,
        webViewStates: [TabSuspensionWebViewState]
    ) -> TabSuspensionEligibility {
        suspensionEligibility(
            for: tab,
            webViewStates: webViewStates,
            visibleTabIDs: visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
                $0.formUnion($1)
            },
            selectedTabIDs: selectedTabIDs()
        )
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
                guard suspensionEligibility(
                    for: tab,
                    liveWebViews: webViews,
                    visibleTabIDs: visibleIDs,
                    selectedTabIDs: selectedIDs
                ).isEligible else {
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

    private func suspensionEligibility(
        for tab: Tab,
        liveWebViews: [WKWebView],
        visibleTabIDs: Set<UUID>,
        selectedTabIDs: Set<UUID>
    ) -> TabSuspensionEligibility {
        guard let coordinator = browserManager?.webViewCoordinator else {
            return .ineligible(reason: .noLiveWebView)
        }

        let states = liveWebViews.map {
            TabSuspensionWebViewState(webView: $0, tab: tab, coordinator: coordinator)
        }
        return suspensionEligibility(
            for: tab,
            webViewStates: states,
            visibleTabIDs: visibleTabIDs,
            selectedTabIDs: selectedTabIDs
        )
    }

    private func suspensionEligibility(
        for tab: Tab,
        webViewStates: [TabSuspensionWebViewState],
        visibleTabIDs: Set<UUID>,
        selectedTabIDs: Set<UUID>
    ) -> TabSuspensionEligibility {
        guard !selectedTabIDs.contains(tab.id) else { return .ineligible(reason: .selected) }
        guard !visibleTabIDs.contains(tab.id) else { return .ineligible(reason: .visible) }
        guard tab.requiresPrimaryWebView else { return .ineligible(reason: .noPrimaryWebView) }
        guard isSuspensibleContentURL(tab.url) else { return .ineligible(reason: .unsupportedURLScheme) }

        // Pinned tabs and Essentials are launchers. Current memory-pressure suspension keeps
        // the launcher runtime intact; future Lightweight behavior may suspend only its
        // WebView instance while preserving identity, placement, restore, and shortcuts.
        guard !isPinned(tab) else { return .ineligible(reason: .launcherRuntimeSuspensionDeferred) }

        guard !tab.isPopupHost else { return .ineligible(reason: .popupHost) }
        guard !tab.isSuspended else { return .ineligible(reason: .alreadySuspended) }
        guard !webViewStates.isEmpty else { return .ineligible(reason: .noLiveWebView) }
        guard !tab.isLoading else { return .ineligible(reason: .loading) }
        guard !tab.audioState.isPlayingAudio else { return .ineligible(reason: .playingAudio) }
        guard tab.pageSuspensionVeto == .none else { return .ineligible(reason: .pageVeto) }
        guard !tab.hasPictureInPictureVideo else { return .ineligible(reason: .pictureInPicture) }
        guard !tab.isDisplayingPDFDocument else { return .ineligible(reason: .pdfDocument) }

        for state in webViewStates {
            guard !state.isProtectedFromCompositorMutation else { return .ineligible(reason: .compositorProtected) }
            guard !state.isLoading else { return .ineligible(reason: .loading) }
            guard !state.isPlayingAudio else { return .ineligible(reason: .playingAudio) }
            guard !state.isCapturingCamera else { return .ineligible(reason: .cameraCapture) }
            guard !state.isCapturingMicrophone else { return .ineligible(reason: .microphoneCapture) }
            guard !state.isFullscreen else { return .ineligible(reason: .fullscreen) }
            guard !state.isPictureInPicture else { return .ineligible(reason: .pictureInPicture) }
            guard !state.isPDFDocument else { return .ineligible(reason: .pdfDocument) }
        }
        return .eligible
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
