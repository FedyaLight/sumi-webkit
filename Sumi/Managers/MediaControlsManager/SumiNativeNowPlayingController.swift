import AppKit
import Combine
import Foundation

@MainActor
final class SumiNativeNowPlayingController: ObservableObject {
    static let shared = SumiNativeNowPlayingController()

    typealias Candidate = (tab: Tab, windowState: BrowserWindowState)
    typealias CandidateProvider = @MainActor (BrowserManager) -> [Candidate]
    typealias InfoProvider = @MainActor (Tab, BrowserManager, BrowserWindowState) async -> SumiNativeNowPlayingInfo?
    typealias CommandExecutor = @MainActor (SumiNativeNowPlayingCommand, Tab, BrowserManager, BrowserWindowState) async -> Bool
    typealias ActivationHandler = @MainActor (Tab, BrowserManager, BrowserWindowState) -> Void

    @Published private(set) var cardState: SumiBackgroundMediaCardState?

    private weak var browserManager: BrowserManager?
    private let candidateProvider: CandidateProvider
    private let infoProvider: InfoProvider
    private let commandExecutor: CommandExecutor
    private let activationHandler: ActivationHandler
    private var currentOwner: OwnerContext?
    private var pausedCardOwner: OwnerContext?
    private var refreshTask: Task<Void, Never>?

    convenience init() {
        self.init(
            candidateProvider: Self.defaultCandidateProvider,
            infoProvider: Self.defaultInfoProvider,
            commandExecutor: Self.defaultCommandExecutor,
            activationHandler: Self.defaultActivationHandler
        )
    }

    init(
        candidateProvider: @escaping CandidateProvider,
        infoProvider: @escaping InfoProvider,
        commandExecutor: @escaping CommandExecutor,
        activationHandler: @escaping ActivationHandler
    ) {
        self.candidateProvider = candidateProvider
        self.infoProvider = infoProvider
        self.commandExecutor = commandExecutor
        self.activationHandler = activationHandler
    }

    func configure(browserManager: BrowserManager) {
        self.browserManager = browserManager
        scheduleRefresh(delayNanoseconds: 0)
    }

    func handleSceneActive() {
        scheduleRefresh(delayNanoseconds: 0)
    }

    func scheduleRefresh(delayNanoseconds: UInt64 = 100_000_000) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.refreshImmediately()
        }
    }

    func refreshImmediately() async {
        guard let browserManager else {
            clearCardState()
            return
        }

        if currentOwner == nil,
           pausedCardOwner == nil,
           !candidateProvider(browserManager).contains(where: { $0.tab.audioState.isPlayingAudio })
        {
            clearCardState()
            return
        }

        if shouldPreferFreshDiscovery,
           let discoveredOwner = await discoverOwner(
            using: browserManager,
            preferCurrentOwner: false,
            allowsPausedRetention: false
           )
        {
            apply(cardState: discoveredOwner)
            return
        }

        if let retainedOwner = await refreshCurrentOwnerIfPossible(using: browserManager) {
            apply(cardState: retainedOwner)
            return
        }

        if let discoveredOwner = await discoverOwner(
            using: browserManager,
            preferCurrentOwner: true,
            allowsPausedRetention: true
        ) {
            apply(cardState: discoveredOwner)
            return
        }

        clearCardState()
    }

    func activateOwner() {
        guard let browserManager,
              let owner = resolvedOwner(using: browserManager)
        else {
            return
        }

        activationHandler(owner.tab, browserManager, owner.windowState)
    }

    func togglePlayPause() async {
        guard let browserManager,
              let owner = resolvedOwner(using: browserManager),
              let cardState
        else {
            return
        }

        let command: SumiNativeNowPlayingCommand =
            cardState.isPlaying ? .pause : .play
        let success = await commandExecutor(command, owner.tab, browserManager, owner.windowState)
        guard success else { return }

        switch command {
        case .pause:
            pausedCardOwner = OwnerContext(tabId: owner.tab.id, windowId: owner.windowState.id)
        case .play:
            pausedCardOwner = nil
        }

        if var updatedCardState = self.cardState {
            updatedCardState.playbackState = command == .pause ? .paused : .playing
            self.cardState = updatedCardState
        }
        scheduleRefresh(delayNanoseconds: 120_000_000)
    }

    func handleTabActivated(_ tabId: UUID) {
        if pausedCardOwner?.tabId == tabId {
            pausedCardOwner = nil
        }
        if currentOwner?.tabId == tabId {
            clearCardState()
        }
    }

    func handleTabUnloaded(_ tabId: UUID) {
        if pausedCardOwner?.tabId == tabId {
            pausedCardOwner = nil
        }
        if currentOwner?.tabId == tabId {
            clearCardState()
        }
    }

    func toggleMute() async {
        guard let browserManager,
              let owner = resolvedOwner(using: browserManager),
              let cardState,
              cardState.canMute
        else {
            return
        }

        owner.tab.toggleMute()

        self.cardState = cardState.withMuted(owner.tab.audioState.isMuted)
        scheduleRefresh(delayNanoseconds: 0)
    }

    private var shouldPreferFreshDiscovery: Bool {
        currentOwner != nil && currentOwner == pausedCardOwner
    }

    private func refreshCurrentOwnerIfPossible(
        using browserManager: BrowserManager
    ) async -> SumiBackgroundMediaCardState? {
        guard let owner = resolvedOwner(using: browserManager) else {
            return nil
        }

        guard canBecomeOwner(owner.tab, in: owner.windowState) else {
            return nil
        }

        let info = await infoProvider(owner.tab, browserManager, owner.windowState)
        guard qualifiesForCard(
            owner.tab,
            in: owner.windowState,
            allowsPausedRetention: true
        ) else {
            return nil
        }

        return makeCardState(
            tab: owner.tab,
            windowState: owner.windowState,
            info: info
        )
    }

    private func discoverOwner(
        using browserManager: BrowserManager,
        preferCurrentOwner: Bool,
        allowsPausedRetention: Bool
    ) async -> SumiBackgroundMediaCardState? {
        let candidates = prioritizedCandidates(
            using: browserManager,
            preferCurrentOwner: preferCurrentOwner
        )

        for (tab, windowState) in candidates {
            let info = await infoProvider(tab, browserManager, windowState)
            guard qualifiesForCard(
                tab,
                in: windowState,
                allowsPausedRetention: allowsPausedRetention
            ) else {
                continue
            }

            return makeCardState(
                tab: tab,
                windowState: windowState,
                info: info
            )
        }

        return nil
    }

    private func prioritizedCandidates(
        using browserManager: BrowserManager,
        preferCurrentOwner: Bool
    ) -> [Candidate] {
        let ownerTabId = preferCurrentOwner ? currentOwner?.tabId : nil

        return candidateProvider(browserManager)
            .filter { canBecomeOwner($0.tab, in: $0.windowState) }
            .sorted { lhs, rhs in
                let lhsIsOwner = lhs.tab.id == ownerTabId
                let rhsIsOwner = rhs.tab.id == ownerTabId
                if lhsIsOwner != rhsIsOwner {
                    return lhsIsOwner
                }

                if lhs.tab.lastMediaActivityAt != rhs.tab.lastMediaActivityAt {
                    return lhs.tab.lastMediaActivityAt > rhs.tab.lastMediaActivityAt
                }

                return lhs.tab.id.uuidString < rhs.tab.id.uuidString
            }
    }

    private func canBecomeOwner(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard !windowState.isIncognito else { return false }
        guard !tab.isEphemeral else { return false }
        guard windowState.currentTabId != tab.id else { return false }
        return true
    }

    private func qualifiesForCard(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        allowsPausedRetention: Bool
    ) -> Bool {
        let ownerContext = OwnerContext(tabId: tab.id, windowId: windowState.id)

        if allowsPausedRetention, pausedCardOwner == ownerContext {
            return true
        }

        return tab.audioState.isPlayingAudio
    }

    private func makeCardState(
        tab: Tab,
        windowState: BrowserWindowState,
        info: SumiNativeNowPlayingInfo?
    ) -> SumiBackgroundMediaCardState {
        let sourceHost = normalizedHost(for: tab.url)
        let tabTitle = normalizedTitle(tab.name) ?? "Media"
        let title = normalizedTitle(info?.title) ?? tabTitle
        let subtitle = normalizedTitle(info?.artist) ?? sourceHost ?? tabTitle
        let favicon = SumiFaviconResolver.cacheKey(for: tab.url)
        let ownerContext = OwnerContext(tabId: tab.id, windowId: windowState.id)
        let playbackState: SumiBackgroundMediaPlaybackState
        if pausedCardOwner == ownerContext {
            playbackState = .paused
        } else if tab.audioState.isPlayingAudio {
            playbackState = .playing
        } else {
            playbackState = info?.playbackState ?? .paused
        }

        currentOwner = OwnerContext(tabId: tab.id, windowId: windowState.id)

        return SumiBackgroundMediaCardState(
            id: "sumi:\(tab.id.uuidString)",
            tabId: tab.id,
            windowId: windowState.id,
            title: title,
            subtitle: subtitle,
            sourceHost: sourceHost,
            tabTitle: tabTitle,
            playbackState: playbackState,
            isMuted: tab.audioState.isMuted,
            favicon: favicon,
            canPlayPause: true,
            canMute: playbackState == .playing
        )
    }

    private func normalizedTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedHost(for url: URL) -> String? {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (host?.isEmpty == false) ? host : nil
    }

    private func resolvedOwner(
        using browserManager: BrowserManager
    ) -> Candidate? {
        guard let currentOwner,
              let windowState = browserManager.windowRegistry?.windows[currentOwner.windowId],
              let tab = resolvedTab(
                tabId: currentOwner.tabId,
                in: windowState,
                using: browserManager
              )
        else {
            return nil
        }

        return (tab, windowState)
    }

    private func resolvedTab(
        tabId: UUID,
        in windowState: BrowserWindowState,
        using browserManager: BrowserManager
    ) -> Tab? {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first(where: { $0.id == tabId })
        }

        if let visibleTab = browserManager.windowScopedMediaCandidateTabs(in: windowState)
            .first(where: { $0.id == tabId })
        {
            return visibleTab
        }

        return browserManager.tabManager.tab(for: tabId)
    }

    private func apply(cardState: SumiBackgroundMediaCardState) {
        if cardState.isPlaying {
            pausedCardOwner = nil
        }
        self.cardState = cardState
    }

    private func clearCardState() {
        currentOwner = nil
        pausedCardOwner = nil
        cardState = nil
    }

    private struct OwnerContext: Equatable {
        let tabId: UUID
        let windowId: UUID
    }

    enum SumiNativeNowPlayingCommand {
        case play
        case pause
    }
}

extension SumiNativeNowPlayingController {
    private static func defaultCandidateProvider(
        browserManager: BrowserManager
    ) -> [Candidate] {
        guard let windowRegistry = browserManager.windowRegistry else { return [] }

        var candidates: [Candidate] = []
        var seen = Set<UUID>()

        for windowState in windowRegistry.windows.values {
            guard !windowState.isIncognito else { continue }

            let scopedTabs = browserManager.windowScopedMediaCandidateTabs(in: windowState)
            let preferredTabs = scopedTabs.filter { $0.audioState.isPlayingAudio }
            let discoveryTabs = preferredTabs.isEmpty
                ? [browserManager.currentTab(for: windowState)].compactMap { $0 }
                : preferredTabs

            for tab in discoveryTabs {
                guard seen.insert(tab.id).inserted else { continue }
                candidates.append((tab, windowState))
            }
        }

        return candidates
    }

    private static func defaultInfoProvider(
        tab: Tab,
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) async -> SumiNativeNowPlayingInfo? {
        await tab.sampleSumiNativeNowPlayingInfo(
            using: browserManager,
            in: windowState
        )
    }

    private static func defaultCommandExecutor(
        command: SumiNativeNowPlayingCommand,
        tab: Tab,
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) async -> Bool {
        switch command {
        case .play:
            return await tab.playSumiNativeNowPlayingSession(
                using: browserManager,
                in: windowState,
                focusIfNeeded: true
            )
        case .pause:
            return await tab.pauseSumiNativeNowPlayingSession(
                using: browserManager,
                in: windowState,
                focusIfNeeded: true
            )
        }
    }

    private static func defaultActivationHandler(
        tab: Tab,
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) {
        NSApp.activate(ignoringOtherApps: true)
        windowState.window?.makeKeyAndOrderFront(nil)
        browserManager.selectTab(tab, in: windowState)
    }
}

@MainActor
final class SumiBackgroundMediaCardStore: ObservableObject {
    @Published private(set) var cardState: SumiBackgroundMediaCardState?

    private let controller: SumiNativeNowPlayingController
    private var cancellables: Set<AnyCancellable> = []
    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?

    convenience init() {
        self.init(controller: .shared)
    }

    init(controller: SumiNativeNowPlayingController) {
        self.controller = controller

        controller.$cardState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.applyVisibleState(state)
            }
            .store(in: &cancellables)
    }

    func configure(
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) {
        self.browserManager = browserManager
        self.windowState = windowState
        controller.configure(browserManager: browserManager)
        applyVisibleState(controller.cardState)
    }

    func handleSceneActive() {
        controller.handleSceneActive()
    }

    func handleSelectionChange() {
        controller.scheduleRefresh(delayNanoseconds: 0)
    }

    func activateSource() {
        controller.activateOwner()
    }

    func togglePlayPause() async {
        await controller.togglePlayPause()
    }

    func toggleMute() async {
        await controller.toggleMute()
    }

    private func applyVisibleState(_ state: SumiBackgroundMediaCardState?) {
        guard let windowState else {
            cardState = state
            return
        }

        guard !windowState.isIncognito else {
            cardState = nil
            return
        }

        guard let state else {
            cardState = nil
            return
        }

        if state.windowId == windowState.id,
           state.tabId == windowState.currentTabId
        {
            cardState = nil
            return
        }

        cardState = state
    }
}
