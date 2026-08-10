import AppKit
import Combine
import Foundation

@MainActor
protocol SumiNativeNowPlayingFeatureControlling: AnyObject {
    func setFeatureEnabled(_ enabled: Bool)
}

@MainActor
protocol SumiNativeNowPlayingRuntimeControlling: SumiNativeNowPlayingFeatureControlling {
    var cardStates: [SumiBackgroundMediaCardState] { get }

    func configure(context: SumiNativeNowPlayingRuntimeContext)
    func scheduleRefresh(delayNanoseconds: UInt64)
    func handleTabActivated(_ tabId: UUID)
    func handleTabUnloaded(_ tabId: UUID)
    func activateOwner(cardID: SumiBackgroundMediaCardID)
    func togglePlayPause(cardID: SumiBackgroundMediaCardID) async
    func toggleMute(cardID: SumiBackgroundMediaCardID) async
    func togglePictureInPicture(cardID: SumiBackgroundMediaCardID) async
    func dismiss(cardID: SumiBackgroundMediaCardID) async
}

@MainActor
final class SumiNativeNowPlayingController: ObservableObject, SumiNativeNowPlayingRuntimeControlling {
    typealias Candidate = SumiNativeNowPlayingRuntimeContext.Candidate
    private typealias OwnerContext = SumiBackgroundMediaCardID
    typealias CandidateProvider = @MainActor (SumiNativeNowPlayingRuntimeContext) -> [Candidate]
    typealias InfoProvider = @MainActor (Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) async -> SumiNativeNowPlayingInfo?
    typealias CommandExecutor = @MainActor (SumiNativeNowPlayingCommand, Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) async -> Bool
    typealias ActivationHandler = @MainActor (Tab, SumiNativeNowPlayingRuntimeContext, BrowserWindowState) -> Void

    @Published private(set) var cardStates: [SumiBackgroundMediaCardState] = []

    private(set) var isFeatureEnabled = true

    private var runtimeContext: SumiNativeNowPlayingRuntimeContext?
    private let candidateProvider: CandidateProvider
    private let infoProvider: InfoProvider
    private let commandExecutor: CommandExecutor
    private let activationHandler: ActivationHandler
    private var retainedPausedOwners: Set<OwnerContext> = []
    private var dismissedOwners: Set<OwnerContext> = []
    private var inFlightTransportOwners: Set<OwnerContext> = []
    private var invalidatedResidenceByCandidate: [SumiMediaResidenceKey: OwnerContext] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

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
        refreshGeneration &+= 1
        let generation = refreshGeneration

        guard isFeatureEnabled, let runtimeContext else {
            publish([])
            return
        }

        pruneInvalidatedResidences(using: runtimeContext)
        let trackedCandidates = Set(
            retainedPausedOwners.lazy.map(\.residenceKey)
        ).union(
            dismissedOwners.lazy.map(\.residenceKey)
        )
        let candidates = prioritizedCandidates(using: runtimeContext)
            .filter { candidate in
                canBecomeOwner(candidate.tab, in: candidate.windowState)
                    && (candidate.tab.audioState.isPlayingAudio
                        || trackedCandidates.contains(residenceKey(for: candidate)))
            }
            .compactMap { candidate -> ResolvedCandidate? in
                guard let webViewIdentity = resolvedWebViewIdentity(
                    candidate,
                    using: runtimeContext
                ) else { return nil }
                return ResolvedCandidate(candidate: candidate, webViewIdentity: webViewIdentity)
            }
        let liveOwners = Set(candidates.map(\.owner))
        retainedPausedOwners.formIntersection(liveOwners)
        dismissedOwners.formIntersection(liveOwners)

        var refreshedStates: [SumiBackgroundMediaCardState] = []
        for resolvedCandidate in candidates {
            let candidate = resolvedCandidate.candidate
            let owner = resolvedCandidate.owner
            let candidateKey = residenceKey(for: candidate)
            if let invalidatedOwner = invalidatedResidenceByCandidate[candidateKey] {
                guard invalidatedOwner != owner else { continue }
                invalidatedResidenceByCandidate.removeValue(forKey: candidateKey)
            }
            guard shouldSample(candidate, owner: owner) else { continue }

            let info = await infoProvider(candidate.tab, runtimeContext, candidate.windowState)

            guard generation == refreshGeneration,
                  !Task.isCancelled,
                  isFeatureEnabled,
                  isStillResolved(candidate, owner: owner, using: runtimeContext),
                  shouldSample(candidate, owner: owner)
            else {
                if generation != refreshGeneration || Task.isCancelled { return }
                continue
            }

            if dismissedOwners.contains(owner) {
                if info?.playbackState != .playing {
                    dismissedOwners.remove(owner)
                }
                continue
            }

            guard retainedPausedOwners.contains(owner)
                    || info?.playbackState == .playing
                    || (info == nil && candidate.tab.audioState.isPlayingAudio)
            else { continue }

            let state = makeCardState(
                tab: candidate.tab,
                windowState: candidate.windowState,
                info: info,
                owner: owner
            )
            refreshedStates.append(state)
        }

        guard generation == refreshGeneration else { return }
        publish(refreshedStates)
    }

    func activateOwner(cardID: SumiBackgroundMediaCardID) {
        guard isFeatureEnabled,
              let runtimeContext,
              let owner = resolvedOwner(cardID: cardID, using: runtimeContext)
        else { return }

        activationHandler(owner.tab, runtimeContext, owner.windowState)
    }

    func togglePlayPause(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canPlayPause,
              let owner = resolvedOwner(cardID: cardID, using: runtimeContext)
        else { return }

        guard inFlightTransportOwners.insert(cardID).inserted else { return }
        defer { inFlightTransportOwners.remove(cardID) }

        let command: SumiNativeNowPlayingCommand = state.isPlaying ? .pause : .play

        if command == .pause {
            retainedPausedOwners.insert(cardID)
            updateCard(cardID: cardID) { $0.playbackState = .paused }
        }

        let success = await commandExecutor(
            command,
            owner.tab,
            runtimeContext,
            owner.windowState
        )

        guard success else {
            if command == .pause {
                retainedPausedOwners.remove(cardID)
                updateCard(cardID: cardID) { $0.playbackState = .playing }
            }
            return
        }

        guard isStillResolved(owner, owner: cardID, using: runtimeContext) else {
            retainedPausedOwners.remove(cardID)
            removeCard(cardID)
            return
        }

        if command == .play {
            retainedPausedOwners.remove(cardID)
            updateCard(cardID: cardID) { $0.playbackState = .playing }
        }
        scheduleRefresh(delayNanoseconds: 120_000_000)
    }

    func toggleMute(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canMute,
              let owner = resolvedOwner(cardID: cardID, using: runtimeContext)
        else { return }

        owner.tab.toggleMute()
        updateCard(cardID: cardID) { $0.isMuted = owner.tab.audioState.isMuted }
    }

    func togglePictureInPicture(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canPictureInPicture,
              let owner = resolvedOwner(cardID: cardID, using: runtimeContext)
        else { return }

        _ = await commandExecutor(
            .pictureInPicture,
            owner.tab,
            runtimeContext,
            owner.windowState
        )
    }

    func dismiss(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let owner = resolvedOwner(cardID: cardID, using: runtimeContext)
        else { return }

        guard inFlightTransportOwners.insert(cardID).inserted else { return }
        defer { inFlightTransportOwners.remove(cardID) }

        dismissedOwners.insert(cardID)
        retainedPausedOwners.remove(cardID)
        removeCard(cardID)

        let success = await commandExecutor(
            .dismiss,
            owner.tab,
            runtimeContext,
            owner.windowState
        )
        if !success {
            dismissedOwners.remove(cardID)
            scheduleRefresh(delayNanoseconds: 0)
        }
    }

    func handleTabActivated(_ tabId: UUID) {
        guard isFeatureEnabled else { return }
        let retained = retainedPausedOwners.filter { $0.tabId == tabId }
        retainedPausedOwners.subtract(retained)
        dismissedOwners = dismissedOwners.filter { $0.tabId != tabId }
        cardStates.removeAll { $0.tabId == tabId }
        invalidateRefresh()

        guard let runtimeContext else { return }
        for ownerContext in retained {
            guard let owner = resolvedOwner(ownerContext, using: runtimeContext) else { continue }
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.commandExecutor(
                    .play,
                    owner.tab,
                    runtimeContext,
                    owner.windowState
                )
            }
        }
    }

    func handleTabUnloaded(_ tabId: UUID) {
        guard isFeatureEnabled else { return }
        for owner in cardStates.lazy.map(\.id) where owner.tabId == tabId {
            invalidatedResidenceByCandidate[owner.residenceKey] = owner
        }
        retainedPausedOwners = retainedPausedOwners.filter { $0.tabId != tabId }
        dismissedOwners = dismissedOwners.filter { $0.tabId != tabId }
        cardStates.removeAll { $0.tabId == tabId }
        invalidateRefresh()
    }

    private func prioritizedCandidates(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> [Candidate] {
        var seen: Set<SumiMediaResidenceKey> = []
        return candidateProvider(runtimeContext)
            .filter { candidate in
                seen.insert(residenceKey(for: candidate)).inserted
            }
            .sorted { lhs, rhs in
                if lhs.tab.mediaRuntime.lastMediaActivityAt != rhs.tab.mediaRuntime.lastMediaActivityAt {
                    return lhs.tab.mediaRuntime.lastMediaActivityAt > rhs.tab.mediaRuntime.lastMediaActivityAt
                }
                return residenceKey(for: lhs) < residenceKey(for: rhs)
            }
    }

    private func pruneInvalidatedResidences(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) {
        invalidatedResidenceByCandidate = invalidatedResidenceByCandidate.filter { key, _ in
            guard let windowState = runtimeContext.windowState(key.windowId) else {
                return false
            }
            return runtimeContext.resolvedTab(key.tabId, windowState) != nil
        }
    }

    private func shouldSample(_ candidate: Candidate, owner: OwnerContext) -> Bool {
        canBecomeOwner(candidate.tab, in: candidate.windowState)
            && (
                candidate.tab.audioState.isPlayingAudio
                    || retainedPausedOwners.contains(owner)
                    || dismissedOwners.contains(owner)
            )
    }

    private func canBecomeOwner(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        !windowState.isIncognito
            && !tab.isEphemeral
            && windowState.currentTabId != tab.id
    }

    private func makeCardState(
        tab: Tab,
        windowState: BrowserWindowState,
        info: SumiNativeNowPlayingInfo?,
        owner: OwnerContext
    ) -> SumiBackgroundMediaCardState {
        let sourceHost = normalizedHost(for: tab.url)
        let tabTitle = normalizedTitle(tab.name) ?? "Media"
        let title = normalizedTitle(info?.title) ?? tabTitle
        let subtitle = normalizedTitle(info?.artist) ?? ""
        let playbackState: SumiBackgroundMediaPlaybackState =
            retainedPausedOwners.contains(owner) ? .paused
            : info?.playbackState ?? (tab.audioState.isPlayingAudio ? .playing : .paused)

        return SumiBackgroundMediaCardState(
            id: owner,
            tabId: tab.id,
            windowId: windowState.id,
            title: title,
            subtitle: subtitle,
            sourceHost: sourceHost,
            tabTitle: tabTitle,
            playbackState: playbackState,
            isMuted: tab.audioState.isMuted,
            faviconSource: faviconSource(for: tab),
            canPlayPause: true,
            canMute: playbackState == .playing,
            canPictureInPicture: info?.canPictureInPicture == true
        )
    }

    private func faviconSource(for tab: Tab) -> SumiBackgroundMediaFaviconSource? {
        guard TabFaviconStore.referenceKey(forDocumentURL: tab.url) != nil else { return nil }
        return SumiBackgroundMediaFaviconSource(
            documentURL: tab.url,
            partition: tab.faviconService.partition(profile: tab.resolveProfile())
        )
    }

    private func resolvedOwner(
        cardID: SumiBackgroundMediaCardID,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Candidate? {
        guard cardStates.contains(where: { $0.id == cardID }) else { return nil }
        return resolvedOwner(cardID, using: runtimeContext)
    }

    private func resolvedOwner(
        _ owner: OwnerContext,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Candidate? {
        guard let windowState = runtimeContext.windowState(owner.windowId),
              let tab = runtimeContext.resolvedTab(owner.tabId, windowState),
              tab.webViewSession.generation == owner.residenceGeneration,
              runtimeContext.resolvedNowPlayingWebView(tab, windowState)
                .map(ObjectIdentifier.init) == owner.webViewIdentity
        else { return nil }
        return (tab, windowState)
    }

    private func isStillResolved(
        _ candidate: Candidate,
        owner: OwnerContext,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Bool {
        guard let resolved = resolvedOwner(owner, using: runtimeContext) else {
            return false
        }
        return resolved.tab === candidate.tab && resolved.windowState === candidate.windowState
    }

    private func resolvedWebViewIdentity(
        _ candidate: Candidate,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> ObjectIdentifier? {
        runtimeContext.resolvedNowPlayingWebView(candidate.tab, candidate.windowState)
            .map(ObjectIdentifier.init)
    }

    private func normalizedTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedHost(for url: URL) -> String? {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        return host?.isEmpty == false ? host : nil
    }

    private func updateCard(
        cardID: SumiBackgroundMediaCardID,
        update: (inout SumiBackgroundMediaCardState) -> Void
    ) {
        guard let index = cardStates.firstIndex(where: { $0.id == cardID }) else { return }
        update(&cardStates[index])
    }

    private func removeCard(_ cardID: SumiBackgroundMediaCardID) {
        cardStates.removeAll { $0.id == cardID }
    }

    private func publish(_ states: [SumiBackgroundMediaCardState]) {
        if cardStates != states {
            cardStates = states
        }
    }

    private func invalidateRefresh() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func suspend() {
        invalidateRefresh()
        let retained = retainedPausedOwners
        retainedPausedOwners.removeAll()
        dismissedOwners.removeAll()
        inFlightTransportOwners.removeAll()
        invalidatedResidenceByCandidate.removeAll()
        publish([])

        guard let runtimeContext else { return }
        for ownerContext in retained {
            guard let owner = resolvedOwner(ownerContext, using: runtimeContext) else { continue }
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.commandExecutor(
                    .play,
                    owner.tab,
                    runtimeContext,
                    owner.windowState
                )
            }
        }
    }

    private func residenceKey(for candidate: Candidate) -> SumiMediaResidenceKey {
        SumiMediaResidenceKey(
            tabId: candidate.tab.id,
            windowId: candidate.windowState.id
        )
    }

    private struct ResolvedCandidate {
        let candidate: Candidate
        let webViewIdentity: ObjectIdentifier

        @MainActor
        var owner: OwnerContext {
            OwnerContext(
                tabId: candidate.tab.id,
                windowId: candidate.windowState.id,
                residenceGeneration: candidate.tab.webViewSession.generation,
                webViewIdentity: webViewIdentity
            )
        }
    }

    enum SumiNativeNowPlayingCommand {
        case play
        case pause
        case dismiss
        case pictureInPicture
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
        await tab.sampleSumiNativeNowPlayingInfo(using: context, in: windowState)
    }

    private static func defaultCommandExecutor(
        command: SumiNativeNowPlayingCommand,
        tab: Tab,
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) async -> Bool {
        switch command {
        case .play:
            return await tab.setSumiNativeNowPlayingSuspended(
                false,
                using: context,
                in: windowState
            )
        case .pause:
            return await tab.setSumiNativeNowPlayingSuspended(
                true,
                using: context,
                in: windowState
            )
        case .dismiss:
            return await tab.dismissSumiNativeNowPlayingSession(
                using: context,
                in: windowState
            )
        case .pictureInPicture:
            return await tab.toggleSumiNativePictureInPicture(using: context, in: windowState)
        }
    }

    private static func defaultActivationHandler(
        tab: Tab,
        context: SumiNativeNowPlayingRuntimeContext,
        windowState: BrowserWindowState
    ) {
        NSApp.activate(ignoringOtherApps: true)
        windowState.shellWindow(in: context.windowRegistry())?.makeKeyAndOrderFront(nil)
        context.selectTab(tab, windowState)
    }
}
