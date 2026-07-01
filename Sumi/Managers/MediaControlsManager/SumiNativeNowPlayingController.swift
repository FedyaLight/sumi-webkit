import AppKit
import Combine
import Foundation

@MainActor
protocol SumiNativeNowPlayingFeatureControlling: AnyObject {
    func setFeatureEnabled(_ enabled: Bool)
}

@MainActor
protocol SumiNativeNowPlayingRuntimeControlling: SumiNativeNowPlayingFeatureControlling {
    var cardState: SumiBackgroundMediaCardState? { get }
    var cardStatePublisher: AnyPublisher<SumiBackgroundMediaCardState?, Never> { get }

    func configure(context: SumiNativeNowPlayingRuntimeContext)
    func handleSceneActive()
    func scheduleRefresh(delayNanoseconds: UInt64)
    func handleTabActivated(_ tabId: UUID)
    func handleTabUnloaded(_ tabId: UUID)
    func activateOwner()
    func togglePlayPause() async
    func toggleMute() async
}

@MainActor
final class SumiNativeNowPlayingController: ObservableObject, SumiNativeNowPlayingRuntimeControlling {
    static let shared = SumiNativeNowPlayingController()

    typealias Candidate = SumiNativeNowPlayingRuntimeContext.Candidate
    typealias CandidateProvider = @MainActor (SumiNativeNowPlayingRuntimeContext) -> [Candidate]
    typealias InfoProvider = @MainActor (Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) async -> SumiNativeNowPlayingInfo?
    typealias CommandExecutor = @MainActor (SumiNativeNowPlayingCommand, Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) async -> Bool
    typealias ActivationHandler = @MainActor (Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) -> Void

    @Published private(set) var cardState: SumiBackgroundMediaCardState?

    private(set) var isFeatureEnabled = true

    private var runtimeContext: SumiNativeNowPlayingRuntimeContext?
    private let candidateProvider: CandidateProvider
    private let infoProvider: InfoProvider
    private let commandExecutor: CommandExecutor
    private let activationHandler: ActivationHandler
    private var currentOwner: OwnerContext?
    private var pausedCardOwner: OwnerContext?
    private var refreshTask: Task<Void, Never>?

    var cardStatePublisher: AnyPublisher<SumiBackgroundMediaCardState?, Never> {
        $cardState.eraseToAnyPublisher()
    }

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

    func setFeatureEnabled(_ enabled: Bool) {
        guard isFeatureEnabled != enabled else { return }
        isFeatureEnabled = enabled

        if enabled {
            scheduleRefresh(delayNanoseconds: 0)
        } else {
            suspend()
        }
    }

    func configure(context: SumiNativeNowPlayingRuntimeContext) {
        runtimeContext = context
        guard isFeatureEnabled else { return }
        scheduleRefresh(delayNanoseconds: 0)
    }

    func handleSceneActive() {
        guard isFeatureEnabled else { return }
        scheduleRefresh(delayNanoseconds: 0)
    }

    func scheduleRefresh(delayNanoseconds: UInt64 = 100_000_000) {
        guard isFeatureEnabled else { return }
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
        guard isFeatureEnabled else {
            clearCardState()
            return
        }

        guard let runtimeContext else {
            clearCardState()
            return
        }

        if currentOwner == nil,
           pausedCardOwner == nil,
           !candidateProvider(runtimeContext).contains(where: \.tab.audioState.isPlayingAudio) {
            clearCardState()
            return
        }

        if shouldPreferFreshDiscovery,
           let discoveredOwner = await discoverOwner(
            using: runtimeContext,
            preferCurrentOwner: false,
            allowsPausedRetention: false
           ) {
            apply(cardState: discoveredOwner)
            return
        }

        if let retainedOwner = await refreshCurrentOwnerIfPossible(using: runtimeContext) {
            apply(cardState: retainedOwner)
            return
        }

        if let discoveredOwner = await discoverOwner(
            using: runtimeContext,
            preferCurrentOwner: true,
            allowsPausedRetention: true
        ) {
            apply(cardState: discoveredOwner)
            return
        }

        clearCardState()
    }

    func activateOwner() {
        guard isFeatureEnabled,
              let runtimeContext,
              let owner = resolvedOwner(using: runtimeContext)
        else {
            return
        }

        activationHandler(owner.tab, runtimeContext, owner.windowState)
    }

    func togglePlayPause() async {
        guard isFeatureEnabled,
              let runtimeContext,
              let owner = resolvedOwner(using: runtimeContext),
              let cardState
        else {
            return
        }

        let command: SumiNativeNowPlayingCommand =
            cardState.isPlaying ? .pause : .play
        let success = await commandExecutor(command, owner.tab, runtimeContext, owner.windowState)
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
        guard isFeatureEnabled else { return }
        if pausedCardOwner?.tabId == tabId {
            pausedCardOwner = nil
        }
        if currentOwner?.tabId == tabId {
            clearCardState()
        }
    }

    func handleTabUnloaded(_ tabId: UUID) {
        guard isFeatureEnabled else { return }
        if pausedCardOwner?.tabId == tabId {
            pausedCardOwner = nil
        }
        if currentOwner?.tabId == tabId {
            clearCardState()
        }
    }

    func toggleMute() async {
        guard isFeatureEnabled,
              let runtimeContext,
              let owner = resolvedOwner(using: runtimeContext),
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
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) async -> SumiBackgroundMediaCardState? {
        guard let owner = resolvedOwner(using: runtimeContext) else {
            return nil
        }

        guard canBecomeOwner(owner.tab, in: owner.windowState) else {
            return nil
        }

        guard qualifiesForCard(
            owner.tab,
            in: owner.windowState,
            allowsPausedRetention: true
        ) else {
            return nil
        }

        let info = await infoProvider(owner.tab, runtimeContext, owner.windowState)
        return makeCardState(
            tab: owner.tab,
            windowState: owner.windowState,
            info: info
        )
    }

    private func discoverOwner(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext,
        preferCurrentOwner: Bool,
        allowsPausedRetention: Bool
    ) async -> SumiBackgroundMediaCardState? {
        let candidates = prioritizedCandidates(
            using: runtimeContext,
            preferCurrentOwner: preferCurrentOwner
        )

        for (tab, windowState) in candidates {
            guard qualifiesForCard(
                tab,
                in: windowState,
                allowsPausedRetention: allowsPausedRetention
            ) else {
                continue
            }

            let info = await infoProvider(tab, runtimeContext, windowState)
            return makeCardState(
                tab: tab,
                windowState: windowState,
                info: info
            )
        }

        return nil
    }

    private func prioritizedCandidates(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext,
        preferCurrentOwner: Bool
    ) -> [Candidate] {
        let ownerTabId = preferCurrentOwner ? currentOwner?.tabId : nil

        return candidateProvider(runtimeContext)
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
        let subtitle = normalizedTitle(info?.artist) ?? ""
        let favicon = SumiFaviconResolver.cacheKey(for: tab.url)
        let ownerContext = OwnerContext(tabId: tab.id, windowId: windowState.id)
        let playbackState: SumiBackgroundMediaPlaybackState
        if tab.audioState.isPlayingAudio {
            playbackState = .playing
        } else if pausedCardOwner == ownerContext {
            playbackState = .paused
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
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Candidate? {
        guard let currentOwner,
              let windowState = runtimeContext.windowState(currentOwner.windowId),
              let tab = resolvedTab(
                tabId: currentOwner.tabId,
                in: windowState,
                using: runtimeContext
              )
        else {
            return nil
        }

        return (tab, windowState)
    }

    private func resolvedTab(
        tabId: UUID,
        in windowState: BrowserWindowState,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Tab? {
        runtimeContext.resolvedTab(tabId, windowState)
    }

    private func apply(cardState: SumiBackgroundMediaCardState) {
        if cardState.isPlaying {
            pausedCardOwner = nil
        }
        self.cardState = cardState
    }

    private func suspend() {
        refreshTask?.cancel()
        refreshTask = nil
        clearCardState()
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
        context: SumiNativeNowPlayingRuntimeContext
    ) -> [Candidate] {
        context.candidateTabs()
    }

    private static func defaultInfoProvider(
        tab: Tab,
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) async -> SumiNativeNowPlayingInfo? {
        await tab.sampleSumiNativeNowPlayingInfo(
            using: context,
            in: windowState
        )
    }

    private static func defaultCommandExecutor(
        command: SumiNativeNowPlayingCommand,
        tab: Tab,
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) async -> Bool {
        switch command {
        case .play:
            return await tab.playSumiNativeNowPlayingSession(
                using: context,
                in: windowState,
                focusIfNeeded: true
            )
        case .pause:
            return await tab.pauseSumiNativeNowPlayingSession(
                using: context,
                in: windowState,
                focusIfNeeded: true
            )
        }
    }

    private static func defaultActivationHandler(
        tab: Tab,
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) {
        NSApp.activate(ignoringOtherApps: true)
        windowState.window?.makeKeyAndOrderFront(nil)
        context.selectTab(tab, windowState)
    }
}

@MainActor
final class SumiBackgroundMediaCardStore: ObservableObject {
    @Published private(set) var cardState: SumiBackgroundMediaCardState?

    private let controller: any SumiNativeNowPlayingRuntimeControlling
    private var cancellables: Set<AnyCancellable> = []
    weak var windowState: BrowserWindowState?

    init(controller: any SumiNativeNowPlayingRuntimeControlling) {
        self.controller = controller

        controller.cardStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.applyVisibleState(state)
            }
            .store(in: &cancellables)
    }

    func configure(
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) {
        self.windowState = windowState
        controller.configure(context: context)
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

        cardState = Self.visibleCardState(globalState: state, in: windowState)
    }

    /// Whether this window should host `MediaControlsView` for the given global controller state.
    static func shouldMountMiniPlayer(
        globalState: SumiBackgroundMediaCardState?,
        in windowState: BrowserWindowState
    ) -> Bool {
        visibleCardState(globalState: globalState, in: windowState) != nil
    }

    private static func visibleCardState(
        globalState: SumiBackgroundMediaCardState?,
        in windowState: BrowserWindowState
    ) -> SumiBackgroundMediaCardState? {
        guard !windowState.isIncognito else { return nil }
        guard let globalState else { return nil }

        if globalState.windowId == windowState.id,
           globalState.tabId == windowState.currentTabId {
            return nil
        }

        return globalState
    }
}
