import Foundation
import WebKit

struct TabSuspensionResult: Equatable {
    let level: SumiMemoryPressureLevel
    let candidateCount: Int
    let suspendedCount: Int
    let suspendedTabIDs: [UUID]
}

struct TabSuspensionPolicy: Equatable {
    static let moderateProactiveDeactivationDelay: TimeInterval = 6 * 60 * 60
    static let balancedProactiveDeactivationDelay: TimeInterval = 4 * 60 * 60
    static let maximumProactiveDeactivationDelay: TimeInterval = 2 * 60 * 60
    static let moderateRevisitProtectionLimit = 5
    static let balancedRevisitProtectionLimit = 15
    static let maximumRevisitProtectionLimit = 15
    static let customRevisitProtectionLimit = 15
    static let recentlyAudibleProtectionInterval: TimeInterval = 60

    let memoryMode: SumiMemoryMode
    let proactiveDeactivationDelay: TimeInterval
    let revisitProtectionLimit: Int

    init(
        memoryMode: SumiMemoryMode,
        customDeactivationDelay: TimeInterval = SumiMemorySaverCustomDelay.defaultDelay
    ) {
        switch memoryMode {
        case .moderate:
            self.init(
                memoryMode: memoryMode,
                proactiveDeactivationDelay: Self.moderateProactiveDeactivationDelay,
                revisitProtectionLimit: Self.moderateRevisitProtectionLimit
            )
        case .balanced:
            self.init(
                memoryMode: memoryMode,
                proactiveDeactivationDelay: Self.balancedProactiveDeactivationDelay,
                revisitProtectionLimit: Self.balancedRevisitProtectionLimit
            )
        case .maximum:
            self.init(
                memoryMode: memoryMode,
                proactiveDeactivationDelay: Self.maximumProactiveDeactivationDelay,
                revisitProtectionLimit: Self.maximumRevisitProtectionLimit
            )
        case .custom:
            self.init(
                memoryMode: memoryMode,
                proactiveDeactivationDelay: SumiMemorySaverCustomDelay.clamped(customDeactivationDelay),
                revisitProtectionLimit: Self.customRevisitProtectionLimit
            )
        }
    }

    private init(
        memoryMode: SumiMemoryMode,
        proactiveDeactivationDelay: TimeInterval,
        revisitProtectionLimit: Int
    ) {
        self.memoryMode = memoryMode
        self.proactiveDeactivationDelay = proactiveDeactivationDelay
        self.revisitProtectionLimit = revisitProtectionLimit
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
        case recentlyAudible
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
    }

    var isEligible: Bool {
        self == .eligible
    }
}

protocol SumiSuspensionClock {
    var liveUptime: TimeInterval { get }
}

struct SumiSystemSuspensionClock: SumiSuspensionClock {
    var liveUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
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
    private static let maxScheduledProactiveTimerReconcileReasons = 8

    private struct Candidate {
        let tab: Tab
        let webViews: [WKWebView]
    }

    private struct HiddenTabState {
        let hiddenStartedAtLiveUptime: TimeInterval
    }

    private struct ProactiveTimerState {
        let hiddenStartedAtLiveUptime: TimeInterval
        let requestedDelay: TimeInterval
        let task: Task<Void, Never>
    }

    private weak var browserManager: BrowserManager?
    private let memoryMonitor: SumiMemoryPressureMonitoring?
    private let dateProvider: () -> Date
    private let suspensionClock: SumiSuspensionClock
    private let timerSleep: (TimeInterval) async throws -> Void
    private var memorySaverPolicyObserver: NSObjectProtocol?
    private var hiddenTabStates: [UUID: HiddenTabState] = [:]
    private var proactiveTimers: [UUID: ProactiveTimerState] = [:]
    private var revisitCounts: [UUID: Int] = [:]
    private var scheduledProactiveTimerReconcileTask: Task<Void, Never>?
    private var pendingProactiveTimerReconcileReasons: Set<String> = []
    private var didTruncatePendingProactiveTimerReconcileReasons = false

    private(set) var proactiveTimerStartCountForTesting = 0
#if DEBUG
    private(set) var proactiveTimerReconcileCountForTesting = 0
    private(set) var lastProactiveTimerReconcileReasonForTesting: String?
#endif

    init(
        memoryMonitor: SumiMemoryPressureMonitoring?,
        dateProvider: @escaping () -> Date = Date.init,
        suspensionClock: SumiSuspensionClock = SumiSystemSuspensionClock(),
        timerSleep: @escaping (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: TabSuspensionService.nanoseconds(for: interval))
        }
    ) {
        self.memoryMonitor = memoryMonitor
        self.dateProvider = dateProvider
        self.suspensionClock = suspensionClock
        self.timerSleep = timerSleep
        self.memoryMonitor?.eventHandler = { [weak self] level in
            self?.handleMemoryPressure(level)
        }
        self.memorySaverPolicyObserver = NotificationCenter.default.addObserver(
            forName: .sumiMemorySaverPolicyChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildProactiveTimers(reason: "memory-saver-policy-changed")
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            cancelScheduledProactiveTimerReconcile()
            cancelAllProactiveTimers()
            if let memorySaverPolicyObserver {
                NotificationCenter.default.removeObserver(memorySaverPolicyObserver)
            }
            memoryMonitor?.eventHandler = nil
            memoryMonitor?.stop()
        }
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        memoryMonitor?.start()
        reconcileProactiveTimers(reason: "attach")
    }

    func proactiveSuspensionPolicyForTesting() -> TabSuspensionPolicy {
        currentSuspensionPolicy
    }

    @discardableResult
    func handleMemoryPressure(_ level: SumiMemoryPressureLevel) -> TabSuspensionResult {
        let signpostState = PerformanceTrace.beginInterval("TabSuspension.memoryPressure")
        defer {
            PerformanceTrace.endInterval("TabSuspension.memoryPressure", signpostState)
        }

        PerformanceTrace.emitEvent("TabSuspension.memoryPressureEvent")
        NotificationCenter.default.post(
            name: .sumiMemoryPressureReceived,
            object: self,
            userInfo: ["level": level.rawValue]
        )

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

        cancelProactiveTimer(for: tab.id)
        hiddenTabStates.removeValue(forKey: tab.id)
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
        TabSuspensionPolicy(
            memoryMode: currentMemoryMode,
            customDeactivationDelay: browserManager?.sumiSettings?.memorySaverCustomDeactivationDelay
                ?? SumiMemorySaverCustomDelay.defaultDelay
        )
    }

    func scheduleProactiveTimerReconcile(reason: String) {
        notePendingProactiveTimerReconcileReason(reason)
        guard scheduledProactiveTimerReconcileTask == nil else { return }

        scheduledProactiveTimerReconcileTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            let reasons = self.pendingProactiveTimerReconcileReasons
            let didTruncateReasons = self.didTruncatePendingProactiveTimerReconcileReasons
            self.pendingProactiveTimerReconcileReasons.removeAll()
            self.didTruncatePendingProactiveTimerReconcileReasons = false
            self.scheduledProactiveTimerReconcileTask = nil

            self.reconcileProactiveTimers(
                reason: Self.coalescedProactiveTimerReconcileReason(
                    reasons: reasons,
                    didTruncateReasons: didTruncateReasons
                )
            )
        }
    }

    func reconcileProactiveTimers(reason: String) {
#if DEBUG
        proactiveTimerReconcileCountForTesting += 1
        lastProactiveTimerReconcileReasonForTesting = reason
#endif

        let tabs = allKnownTabs()
        let knownTabIDs = Set(tabs.map(\.id))
        for tabID in proactiveTimers.keys where !knownTabIDs.contains(tabID) {
            cancelProactiveTimer(for: tabID)
        }
        hiddenTabStates = hiddenTabStates.filter { knownTabIDs.contains($0.key) }
        revisitCounts = revisitCounts.filter { knownTabIDs.contains($0.key) }

        let context = suspensionEvaluationContext()
        for tab in tabs {
            if context.selectedTabIDs.contains(tab.id) || context.visibleTabIDs.contains(tab.id) {
                noteTabBecameVisible(tab)
            } else {
                noteTabBecameHidden(tab, context: context)
            }
        }

        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "reconciled proactive timers reason=\(reason) active=\(proactiveTimers.count)"
        }
    }

    private func notePendingProactiveTimerReconcileReason(_ reason: String) {
        if pendingProactiveTimerReconcileReasons.contains(reason) {
            return
        }

        guard pendingProactiveTimerReconcileReasons.count
            < Self.maxScheduledProactiveTimerReconcileReasons
        else {
            didTruncatePendingProactiveTimerReconcileReasons = true
            return
        }

        pendingProactiveTimerReconcileReasons.insert(reason)
    }

    private func cancelScheduledProactiveTimerReconcile() {
        scheduledProactiveTimerReconcileTask?.cancel()
        scheduledProactiveTimerReconcileTask = nil
        pendingProactiveTimerReconcileReasons.removeAll()
        didTruncatePendingProactiveTimerReconcileReasons = false
    }

    private static func coalescedProactiveTimerReconcileReason(
        reasons: Set<String>,
        didTruncateReasons: Bool
    ) -> String {
        var components = reasons.sorted()
        if didTruncateReasons {
            components.append("more")
        }
        if components.isEmpty {
            components.append("unknown")
        }
        return "coalesced(\(components.joined(separator: ",")))"
    }

    func rebuildProactiveTimers(reason: String) {
        cancelAllProactiveTimers()

        let now = suspensionClock.liveUptime
        let context = suspensionEvaluationContext()
        for tab in allKnownTabs() {
            guard !context.selectedTabIDs.contains(tab.id),
                  !context.visibleTabIDs.contains(tab.id)
            else { continue }
            hiddenTabStates[tab.id] = HiddenTabState(hiddenStartedAtLiveUptime: now)
            noteTabBecameHidden(tab, context: context)
        }

        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "rebuilt proactive timers reason=\(reason) active=\(proactiveTimers.count)"
        }
    }

    func resetRevisitProtection(for tab: Tab) {
        revisitCounts[tab.id] = 0
        cancelProactiveTimer(for: tab.id)

        let context = suspensionEvaluationContext()
        if !context.selectedTabIDs.contains(tab.id),
           !context.visibleTabIDs.contains(tab.id) {
            hiddenTabStates[tab.id] = HiddenTabState(hiddenStartedAtLiveUptime: suspensionClock.liveUptime)
            noteTabBecameHidden(tab, context: context)
        }
    }

    private func noteTabBecameVisible(_ tab: Tab) {
        cancelProactiveTimer(for: tab.id)
        guard hiddenTabStates.removeValue(forKey: tab.id) != nil else { return }
        revisitCounts[tab.id, default: 0] += 1
    }

    private func noteTabBecameHidden(
        _ tab: Tab,
        context: TabSuspensionEvaluationContext
    ) {
        let hiddenState = hiddenTabStates[tab.id] ?? HiddenTabState(
            hiddenStartedAtLiveUptime: suspensionClock.liveUptime
        )
        hiddenTabStates[tab.id] = hiddenState

        guard proactiveTimers[tab.id] == nil else { return }
        guard shouldStartProactiveTimer(for: tab, context: context) else { return }

        armProactiveTimer(
            for: tab.id,
            hiddenStartedAtLiveUptime: hiddenState.hiddenStartedAtLiveUptime,
            requestedDelay: context.policy.proactiveDeactivationDelay,
            sleepDelay: context.policy.proactiveDeactivationDelay
        )
    }

    private func shouldStartProactiveTimer(
        for tab: Tab,
        context: TabSuspensionEvaluationContext
    ) -> Bool {
        guard revisitCounts[tab.id, default: 0] <= context.policy.revisitProtectionLimit else {
            return false
        }
        guard let coordinator = browserManager?.webViewCoordinator else { return false }
        return suspensionEligibility(
            for: tab,
            liveWebViews: coordinator.liveWebViews(for: tab),
            context: context
        ).isEligible
    }

    private func armProactiveTimer(
        for tabID: UUID,
        hiddenStartedAtLiveUptime: TimeInterval,
        requestedDelay: TimeInterval,
        sleepDelay: TimeInterval
    ) {
        cancelProactiveTimer(for: tabID)
        proactiveTimerStartCountForTesting += 1
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.timerSleep(sleepDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.handleProactiveTimerFired(
                tabID: tabID,
                hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime,
                requestedDelay: requestedDelay
            )
        }
        proactiveTimers[tabID] = ProactiveTimerState(
            hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime,
            requestedDelay: requestedDelay,
            task: task
        )
    }

    private func handleProactiveTimerFired(
        tabID: UUID,
        hiddenStartedAtLiveUptime: TimeInterval,
        requestedDelay: TimeInterval
    ) {
        proactiveTimers.removeValue(forKey: tabID)

        let elapsed = max(0, suspensionClock.liveUptime - hiddenStartedAtLiveUptime)
        if elapsed + 0.001 < requestedDelay {
            armProactiveTimer(
                for: tabID,
                hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime,
                requestedDelay: requestedDelay,
                sleepDelay: requestedDelay - elapsed
            )
            return
        }

        guard let tab = allKnownTabs().first(where: { $0.id == tabID }) else { return }
        let context = suspensionEvaluationContext()
        guard !context.selectedTabIDs.contains(tab.id),
              !context.visibleTabIDs.contains(tab.id)
        else {
            noteTabBecameVisible(tab)
            return
        }

        guard let coordinator = browserManager?.webViewCoordinator,
              suspensionEligibility(
                  for: tab,
                  liveWebViews: coordinator.liveWebViews(for: tab),
                  context: context
              ).isEligible
        else {
            return
        }

        _ = suspend(tab, reason: "proactive-\(context.policy.memoryMode.rawValue)", context: context)
    }

    private func cancelProactiveTimer(for tabID: UUID) {
        proactiveTimers.removeValue(forKey: tabID)?.task.cancel()
    }

    private func cancelAllProactiveTimers() {
        for timer in proactiveTimers.values {
            timer.task.cancel()
        }
        proactiveTimers.removeAll()
    }

#if DEBUG
    var proactiveTimerTabIDsForTesting: Set<UUID> {
        Set(proactiveTimers.keys)
    }

    func proactiveTimerStateForTesting(tabID: UUID) -> (hiddenStartedAtLiveUptime: TimeInterval, requestedDelay: TimeInterval)? {
        guard let state = proactiveTimers[tabID] else { return nil }
        return (state.hiddenStartedAtLiveUptime, state.requestedDelay)
    }

    func revisitCountForTesting(tabID: UUID) -> Int {
        revisitCounts[tabID, default: 0]
    }

    func fireProactiveTimerForTesting(tabID: UUID) {
        guard let state = proactiveTimers[tabID] else { return }
        handleProactiveTimerFired(
            tabID: tabID,
            hiddenStartedAtLiveUptime: state.hiddenStartedAtLiveUptime,
            requestedDelay: state.requestedDelay
        )
    }

    var isProactiveTimerReconcileScheduledForTesting: Bool {
        scheduledProactiveTimerReconcileTask != nil
    }

    func drainScheduledProactiveTimerReconcileForTesting() async {
        await scheduledProactiveTimerReconcileTask?.value
    }
#endif

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

        guard !tab.isPopupHost else { return .ineligible(reason: .popupHost) }
        guard !tab.isSuspended else { return .ineligible(reason: .alreadySuspended) }
        guard !webViewStates.isEmpty else { return .ineligible(reason: .noLiveWebView) }
        guard !tab.isLoading else { return .ineligible(reason: .loading) }
        guard !tab.audioState.isPlayingAudio else { return .ineligible(reason: .playingAudio) }
        guard !isRecentlyAudible(tab) else { return .ineligible(reason: .recentlyAudible) }
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

    private func isRecentlyAudible(_ tab: Tab) -> Bool {
        guard tab.lastMediaActivityAt != .distantPast else { return false }
        return dateProvider().timeIntervalSince(tab.lastMediaActivityAt)
            < TabSuspensionPolicy.recentlyAudibleProtectionInterval
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
