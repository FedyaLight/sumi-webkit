import Foundation
import WebKit

struct TabSuspensionResult: Equatable {
    let level: SumiMemoryPressureLevel
    let candidateCount: Int
    let suspendedCount: Int
    let suspendedTabIDs: [UUID]
}

struct TabIdleSuspensionResult: Equatable {
    let memoryMode: SumiMemoryMode
    let policy: TabSuspensionPolicy
    let candidateCount: Int
    let warmTabCount: Int
    let warmWebViewCount: Int
    let suspendedCount: Int
    let suspendedTabIDs: [UUID]
}

struct TabSuspensionPolicy: Equatable {
    static let lightweightIdleThreshold: TimeInterval = 10 * 60
    static let balancedIdleThreshold: TimeInterval = 30 * 60
    static let performanceIdleThreshold: TimeInterval = 90 * 60

    static let lightweightMaximumWarmHiddenWebViewCount = 0
    static let balancedMaximumWarmHiddenWebViewCount = 2
    static let performanceMaximumWarmHiddenWebViewCount = 5

    static let lightweightEvaluationInterval: TimeInterval = 60
    static let balancedEvaluationInterval: TimeInterval = 120
    static let performanceEvaluationInterval: TimeInterval = 300

    let idleThreshold: TimeInterval
    let maximumWarmHiddenWebViewCount: Int
    let allowsLauncherRuntimeSuspension: Bool
    let evaluationInterval: TimeInterval

    init(memoryMode: SumiMemoryMode) {
        switch memoryMode {
        case .lightweight:
            self.init(
                idleThreshold: Self.lightweightIdleThreshold,
                maximumWarmHiddenWebViewCount: Self.lightweightMaximumWarmHiddenWebViewCount,
                allowsLauncherRuntimeSuspension: true,
                evaluationInterval: Self.lightweightEvaluationInterval
            )
        case .balanced:
            self.init(
                idleThreshold: Self.balancedIdleThreshold,
                maximumWarmHiddenWebViewCount: Self.balancedMaximumWarmHiddenWebViewCount,
                allowsLauncherRuntimeSuspension: false,
                evaluationInterval: Self.balancedEvaluationInterval
            )
        case .performance:
            self.init(
                idleThreshold: Self.performanceIdleThreshold,
                maximumWarmHiddenWebViewCount: Self.performanceMaximumWarmHiddenWebViewCount,
                allowsLauncherRuntimeSuspension: false,
                evaluationInterval: Self.performanceEvaluationInterval
            )
        }
    }

    private init(
        idleThreshold: TimeInterval,
        maximumWarmHiddenWebViewCount: Int,
        allowsLauncherRuntimeSuspension: Bool,
        evaluationInterval: TimeInterval
    ) {
        self.idleThreshold = idleThreshold
        self.maximumWarmHiddenWebViewCount = maximumWarmHiddenWebViewCount
        self.allowsLauncherRuntimeSuspension = allowsLauncherRuntimeSuspension
        self.evaluationInterval = evaluationInterval
    }
}

struct TabSuspensionEvaluationContext: Equatable {
    let visibleTabIDs: Set<UUID>
    let selectedTabIDs: Set<UUID>
    let policy: TabSuspensionPolicy
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
    private let startsIdleSchedulerOnAttach: Bool
    private var idleSuspensionTask: Task<Void, Never>?

    private(set) var idleSchedulerStartCountForTesting = 0

    init(
        memoryMonitor: SumiMemoryPressureMonitoring?,
        dateProvider: @escaping () -> Date = Date.init,
        startsIdleSchedulerOnAttach: Bool = true
    ) {
        self.memoryMonitor = memoryMonitor
        self.dateProvider = dateProvider
        self.startsIdleSchedulerOnAttach = startsIdleSchedulerOnAttach
        self.memoryMonitor?.eventHandler = { [weak self] level in
            self?.handleMemoryPressure(level)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stopIdleSuspensionScheduler()
            memoryMonitor?.eventHandler = nil
            memoryMonitor?.stop()
        }
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        memoryMonitor?.start()
        if startsIdleSchedulerOnAttach {
            startIdleSuspensionScheduler()
        }
    }

    func startIdleSuspensionScheduler() {
        guard idleSuspensionTask == nil else { return }
        idleSchedulerStartCountForTesting += 1
        idleSuspensionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let evaluationInterval = self?.currentSuspensionPolicy.evaluationInterval else { return }
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: evaluationInterval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.evaluateIdleSuspension()
            }
        }
    }

    func stopIdleSuspensionScheduler() {
        idleSuspensionTask?.cancel()
        idleSuspensionTask = nil
    }

    var isIdleSuspensionSchedulerRunningForTesting: Bool {
        idleSuspensionTask != nil
    }

    func idleSuspensionPolicyForTesting() -> TabSuspensionPolicy {
        currentSuspensionPolicy
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
    func evaluateIdleSuspension() -> TabIdleSuspensionResult {
        evaluateIdleSuspension(webViewStatesByTabID: [:])
    }

#if DEBUG
    @discardableResult
    func evaluateIdleSuspensionForTesting(
        webViewStatesByTabID: [UUID: [TabSuspensionWebViewState]]
    ) -> TabIdleSuspensionResult {
        evaluateIdleSuspension(webViewStatesByTabID: webViewStatesByTabID)
    }
#endif

    @discardableResult
    func suspend(_ tab: Tab, reason: String) -> Bool {
        suspend(tab, reason: reason, context: suspensionEvaluationContext())
    }

    @discardableResult
    func suspend(
        _ tab: Tab,
        reason: String,
        context: TabSuspensionEvaluationContext
    ) -> Bool {
        guard let browserManager,
              let coordinator = browserManager.webViewCoordinator
        else { return false }

        let liveWebViews = coordinator.liveWebViews(for: tab)
        guard suspensionEligibility(
            for: tab,
            liveWebViews: liveWebViews,
            context: context
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
            context: suspensionEvaluationContext()
        )
    }

    func suspensionEligibility(
        for tab: Tab,
        webViewStates: [TabSuspensionWebViewState]
    ) -> TabSuspensionEligibility {
        suspensionEligibility(
            for: tab,
            webViewStates: webViewStates,
            context: suspensionEvaluationContext()
        )
    }

    func suspensionEvaluationContext() -> TabSuspensionEvaluationContext {
        suspensionEvaluationContext(policy: currentSuspensionPolicy)
    }

    func suspensionEvaluationContext(policy: TabSuspensionPolicy) -> TabSuspensionEvaluationContext {
        TabSuspensionEvaluationContext(
            visibleTabIDs: visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
                $0.formUnion($1)
            },
            selectedTabIDs: selectedTabIDs(),
            policy: policy
        )
    }

    private var currentMemoryMode: SumiMemoryMode {
        browserManager?.sumiSettings?.memoryMode ?? .balanced
    }

    private var currentSuspensionPolicy: TabSuspensionPolicy {
        TabSuspensionPolicy(memoryMode: currentMemoryMode)
    }

    private func evaluateIdleSuspension(
        webViewStatesByTabID: [UUID: [TabSuspensionWebViewState]]
    ) -> TabIdleSuspensionResult {
        let memoryMode = currentMemoryMode
        let policy = TabSuspensionPolicy(memoryMode: memoryMode)
        let context = suspensionEvaluationContext(policy: policy)
        let candidates = suspensionCandidates(
            webViewStatesByTabID: webViewStatesByTabID,
            context: context
        )
        let warmSet = warmCandidateTabIDs(
            from: candidates,
            maximumWarmHiddenWebViewCount: policy.maximumWarmHiddenWebViewCount
        )
        let cutoffDate = dateProvider().addingTimeInterval(-policy.idleThreshold)

        var suspendedTabIDs: [UUID] = []
        for candidate in candidates {
            guard !warmSet.tabIDs.contains(candidate.tab.id) else { continue }
            if let lastSelectedAt = candidate.tab.lastSelectedAt,
               lastSelectedAt >= cutoffDate {
                continue
            }
            guard suspend(candidate.tab, reason: "idle-\(memoryMode.rawValue)", context: context) else {
                continue
            }
            suspendedTabIDs.append(candidate.tab.id)
        }

        return TabIdleSuspensionResult(
            memoryMode: memoryMode,
            policy: policy,
            candidateCount: candidates.count,
            warmTabCount: warmSet.tabIDs.count,
            warmWebViewCount: warmSet.webViewCount,
            suspendedCount: suspendedTabIDs.count,
            suspendedTabIDs: suspendedTabIDs
        )
    }

    private func suspensionCandidates(
        inactiveBefore cutoffDate: Date? = nil,
        webViewStatesByTabID: [UUID: [TabSuspensionWebViewState]] = [:],
        context: TabSuspensionEvaluationContext? = nil
    ) -> [Candidate] {
        guard let browserManager,
              let coordinator = browserManager.webViewCoordinator
        else { return [] }

        let context = context ?? suspensionEvaluationContext()

        return allKnownTabs()
            .compactMap { tab -> Candidate? in
                let webViews = coordinator.liveWebViews(for: tab)
                let eligibility = if let webViewStates = webViewStatesByTabID[tab.id] {
                    suspensionEligibility(
                        for: tab,
                        webViewStates: webViewStates,
                        context: context
                    )
                } else {
                    suspensionEligibility(
                        for: tab,
                        liveWebViews: webViews,
                        context: context
                    )
                }
                guard eligibility.isEligible else {
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

    private func warmCandidateTabIDs(
        from candidates: [Candidate],
        maximumWarmHiddenWebViewCount: Int
    ) -> (tabIDs: Set<UUID>, webViewCount: Int) {
        guard maximumWarmHiddenWebViewCount > 0 else {
            return ([], 0)
        }

        var warmTabIDs = Set<UUID>()
        var warmWebViewCount = 0
        let mostRecentFirst = candidates.sorted { lhs, rhs in
            let leftDate = lhs.tab.lastSelectedAt ?? .distantPast
            let rightDate = rhs.tab.lastSelectedAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.tab.id.uuidString < rhs.tab.id.uuidString
        }

        for candidate in mostRecentFirst {
            let webViewCount = candidate.webViews.count
            guard webViewCount > 0 else { continue }
            guard warmWebViewCount + webViewCount <= maximumWarmHiddenWebViewCount else { continue }
            warmTabIDs.insert(candidate.tab.id)
            warmWebViewCount += webViewCount
        }

        return (warmTabIDs, warmWebViewCount)
    }

    func suspensionEligibility(
        for tab: Tab,
        liveWebViews: [WKWebView],
        context: TabSuspensionEvaluationContext
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
            context: context
        )
    }

    func suspensionEligibility(
        for tab: Tab,
        webViewStates: [TabSuspensionWebViewState],
        context: TabSuspensionEvaluationContext
    ) -> TabSuspensionEligibility {
        guard !context.selectedTabIDs.contains(tab.id) else { return .ineligible(reason: .selected) }
        guard !context.visibleTabIDs.contains(tab.id) else { return .ineligible(reason: .visible) }
        guard tab.requiresPrimaryWebView else { return .ineligible(reason: .noPrimaryWebView) }
        guard isSuspensibleContentURL(tab.url) else { return .ineligible(reason: .unsupportedURLScheme) }

        // Pinned tabs and Essentials are launchers; only Lightweight may release their
        // live WebView runtime while preserving the launcher tab/pin identity.
        if isPinned(tab), !context.policy.allowsLauncherRuntimeSuspension {
            return .ineligible(reason: .launcherRuntimeSuspensionDeferred)
        }

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

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(interval, 0) * 1_000_000_000)
    }
}
