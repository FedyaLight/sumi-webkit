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
    func handleTabActivated(_ tabId: UUID, in windowId: UUID)
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
    private typealias SessionID = SumiBackgroundMediaCardID
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
    private var sessions: [SessionID: SessionRecord] = [:]
    private var inFlightTransportSessions: Set<SessionID> = []
    private var retiredSessionByResidence: [SumiMediaResidenceKey: SessionID] = [:]
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
            resetForDisabledFeature()
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

        pruneRetiredResidences(using: runtimeContext)
        let residences = resolvedResidences(using: runtimeContext)
        let liveSessionIDs = Set(residences.map(\.id))
        sessions = sessions.filter { liveSessionIDs.contains($0.key) }

        var refreshedStates: [SumiBackgroundMediaCardState] = []
        for residence in residences {
            if let state = await reconciledCardState(
                for: residence,
                refreshGeneration: generation,
                using: runtimeContext
            ) {
                refreshedStates.append(state)
            }
            guard isCurrentRefresh(generation) else { return }
        }

        guard isCurrentRefresh(generation) else { return }
        publish(refreshedStates)
    }

    func activateOwner(cardID: SumiBackgroundMediaCardID) {
        guard isFeatureEnabled,
              let runtimeContext,
              let residence = resolvedVisibleResidence(cardID, using: runtimeContext)
        else { return }

        activationHandler(residence.tab, runtimeContext, residence.windowState)
    }

    func togglePlayPause(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canPlayPause,
              let residence = resolvedVisibleResidence(cardID, using: runtimeContext)
        else { return }

        guard inFlightTransportSessions.insert(cardID).inserted else { return }
        defer { inFlightTransportSessions.remove(cardID) }

        let command: SumiNativeNowPlayingCommand = state.isPlaying ? .pause : .play
        let requestedPlaybackState: SumiBackgroundMediaPlaybackState =
            command == .pause ? .paused : .playing
        let playbackGeneration = residence.tab.mediaRuntime.playbackStartGeneration
        let previousSession = sessions[cardID]
        if var session = sessions[cardID] {
            session.setPlayback(requestedPlaybackState, at: playbackGeneration)
            sessions[cardID] = session
            updateCard(cardID: cardID) { $0.playbackState = requestedPlaybackState }
        }

        let success = await commandExecutor(
            command,
            residence.tab,
            runtimeContext,
            residence.windowState
        )

        guard success else {
            sessions[cardID] = previousSession
            updateCard(cardID: cardID) { $0.playbackState = state.playbackState }
            return
        }

        guard isStillResolved(residence, using: runtimeContext),
              var session = sessions[cardID]
        else {
            retireSession(cardID)
            return
        }

        session.setPlayback(requestedPlaybackState, at: playbackGeneration)
        updateCard(cardID: cardID) { $0.playbackState = requestedPlaybackState }
        sessions[cardID] = session
        await refreshImmediately()
    }

    func toggleMute(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canMute,
              let residence = resolvedVisibleResidence(cardID, using: runtimeContext)
        else { return }

        guard inFlightTransportSessions.insert(cardID).inserted else { return }
        defer { inFlightTransportSessions.remove(cardID) }

        let muted = !state.isMuted
        if muted, var session = sessions[cardID] {
            session.setMuted(true)
            sessions[cardID] = session
            updateCard(cardID: cardID) { $0.isMuted = true }
        }
        let success = await commandExecutor(
            .setMuted(muted),
            residence.tab,
            runtimeContext,
            residence.windowState
        )
        guard success else {
            if muted, var session = sessions[cardID] {
                session.setMuted(false)
                sessions[cardID] = session
                updateCard(cardID: cardID) { $0.isMuted = false }
            }
            return
        }
        guard isStillResolved(residence, using: runtimeContext),
              var session = sessions[cardID]
        else {
            retireSession(cardID)
            return
        }

        session.setMuted(muted)
        sessions[cardID] = session
        updateCard(cardID: cardID) { $0.isMuted = muted }
        scheduleRefresh(delayNanoseconds: 0)
    }

    func togglePictureInPicture(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let state = cardStates.first(where: { $0.id == cardID }),
              state.canPictureInPicture,
              let residence = resolvedVisibleResidence(cardID, using: runtimeContext)
        else { return }

        _ = await commandExecutor(
            .pictureInPicture,
            residence.tab,
            runtimeContext,
            residence.windowState
        )
    }

    func dismiss(cardID: SumiBackgroundMediaCardID) async {
        guard isFeatureEnabled,
              let runtimeContext,
              let residence = resolvedVisibleResidence(cardID, using: runtimeContext)
        else { return }

        guard inFlightTransportSessions.insert(cardID).inserted else { return }
        defer { inFlightTransportSessions.remove(cardID) }

        guard var session = sessions[cardID] else { return }
        session.dismiss(at: residence.tab.mediaRuntime.playbackStartGeneration)
        sessions[cardID] = session
        removeCard(cardID)

        let success = await commandExecutor(
            .dismiss,
            residence.tab,
            runtimeContext,
            residence.windowState
        )
        if !success {
            sessions[cardID]?.clearSuppression()
            scheduleRefresh(delayNanoseconds: 0)
        }
    }

    func handleTabActivated(_ tabId: UUID, in windowId: UUID) {
        guard isFeatureEnabled else { return }
        let residenceKey = SumiMediaResidenceKey(tabId: tabId, windowId: windowId)
        if let runtimeContext,
           let windowState = runtimeContext.windowState(windowId),
           let tab = runtimeContext.resolvedTab(tabId, windowState) {
            let playbackGeneration = tab.mediaRuntime.playbackStartGeneration
            for sessionID in sessions.keys where sessionID.residenceKey == residenceKey {
                sessions[sessionID]?.suppress(at: playbackGeneration)
            }
        }
        cardStates.removeAll { $0.id.residenceKey == residenceKey }
        invalidateRefresh()
    }

    func handleTabUnloaded(_ tabId: UUID) {
        guard isFeatureEnabled else { return }
        for sessionID in sessions.keys where sessionID.tabId == tabId {
            retiredSessionByResidence[sessionID.residenceKey] = sessionID
        }
        sessions = sessions.filter { $0.key.tabId != tabId }
        inFlightTransportSessions = inFlightTransportSessions.filter { $0.tabId != tabId }
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

    private func resolvedResidences(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> [ResolvedResidence] {
        prioritizedCandidates(using: runtimeContext)
            .filter { canTrack($0.tab, in: $0.windowState) }
            .compactMap { candidate in
                guard let webView = runtimeContext.resolvedNowPlayingWebView(
                    candidate.tab,
                    candidate.windowState
                ) else { return nil }
                return ResolvedResidence(
                    tab: candidate.tab,
                    windowState: candidate.windowState,
                    webView: webView
                )
            }
    }

    private func reconciledCardState(
        for residence: ResolvedResidence,
        refreshGeneration: UInt64,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) async -> SumiBackgroundMediaCardState? {
        guard prepareSessionForPresentation(residence) else { return nil }

        let info = await infoProvider(residence.tab, runtimeContext, residence.windowState)
        guard isCurrentRefresh(refreshGeneration) else { return nil }
        guard isStillResolved(residence, using: runtimeContext) else {
            retireSession(residence.id)
            return nil
        }

        let audioState = residence.webView.sumiNowPlayingAudioState
        let hasAudibleOutput = audioState.isPlayingAudio && !audioState.isMuted
        guard var session = sessions[residence.id], !session.isSuppressed else { return nil }
        guard session.canRemainAdmitted(hasAudibleOutput: hasAudibleOutput) else {
            retireSession(residence.id)
            return nil
        }
        let presentationInfo = session.infoForPresentation(
            latest: info,
            hasAudibleOutput: hasAudibleOutput
        )
        sessions[residence.id] = session

        return makeCardState(
            tab: residence.tab,
            windowState: residence.windowState,
            info: presentationInfo,
            sessionID: residence.id,
            playbackState: session.projectedPlaybackState(
                isPlayingAudio: audioState.isPlayingAudio,
                nativePlaybackState: info?.playbackState
            ),
            isMuted: session.projectsMuted(nativeIsMuted: audioState.isMuted)
        )
    }

    private func prepareSessionForPresentation(
        _ residence: ResolvedResidence
    ) -> Bool {
        if let retiredSession = retiredSessionByResidence[residence.residenceKey] {
            guard retiredSession != residence.id else { return false }
            retiredSessionByResidence.removeValue(forKey: residence.residenceKey)
        }

        let audioState = residence.webView.sumiNowPlayingAudioState
        let hasAudibleOutput = audioState.isPlayingAudio && !audioState.isMuted
        var session = sessions[residence.id]

        if var currentSession = session {
            currentSession.reconcileExternalUnmute(
                nativeIsMuted: audioState.isMuted,
                projectedIsMuted: residence.tab.audioState.isMuted
            )
            currentSession.reconcilePlayback(
                isPlayingAudio: audioState.isPlayingAudio,
                playbackGeneration: residence.tab.mediaRuntime.playbackStartGeneration
            )

            if currentSession.suppressionHasExpired(
                playbackGeneration: residence.tab.mediaRuntime.playbackStartGeneration
            ) {
                sessions.removeValue(forKey: residence.id)
                session = nil
            } else if currentSession.isSuppressed {
                sessions[residence.id] = currentSession
                return false
            } else {
                session = currentSession
            }
        }

        if session == nil {
            guard canPresent(residence.tab, in: residence.windowState),
                  hasAudibleOutput
            else { return false }
            session = SessionRecord()
        }

        guard let admittedSession = session else { return false }
        guard admittedSession.canRemainAdmitted(hasAudibleOutput: hasAudibleOutput) else {
            retireSession(residence.id)
            return false
        }

        sessions[residence.id] = admittedSession
        return canPresent(residence.tab, in: residence.windowState)
    }

    private func pruneRetiredResidences(
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) {
        retiredSessionByResidence = retiredSessionByResidence.filter { key, _ in
            guard let windowState = runtimeContext.windowState(key.windowId) else {
                return false
            }
            return runtimeContext.resolvedTab(key.tabId, windowState) != nil
        }
    }

    private func canTrack(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        !windowState.isIncognito && !tab.isEphemeral
    }

    private func canPresent(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        canTrack(tab, in: windowState) && windowState.currentTabId != tab.id
    }

    private func makeCardState(
        tab: Tab,
        windowState: BrowserWindowState,
        info: SumiNativeNowPlayingInfo?,
        sessionID: SessionID,
        playbackState: SumiBackgroundMediaPlaybackState,
        isMuted: Bool
    ) -> SumiBackgroundMediaCardState {
        let sourceHost = normalizedHost(for: tab.url)
        let tabTitle = normalizedTitle(tab.name) ?? "Media"
        let title = normalizedTitle(info?.title) ?? tabTitle
        let subtitle = normalizedTitle(info?.artist) ?? ""

        return SumiBackgroundMediaCardState(
            id: sessionID,
            tabId: tab.id,
            windowId: windowState.id,
            title: title,
            subtitle: subtitle,
            sourceHost: sourceHost,
            tabTitle: tabTitle,
            playbackState: playbackState,
            isMuted: isMuted,
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

    private func resolvedVisibleResidence(
        _ sessionID: SessionID,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> ResolvedResidence? {
        guard cardStates.contains(where: { $0.id == sessionID }) else { return nil }
        return resolvedResidence(sessionID, using: runtimeContext)
    }

    private func resolvedResidence(
        _ sessionID: SessionID,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> ResolvedResidence? {
        guard let windowState = runtimeContext.windowState(sessionID.windowId),
              let tab = runtimeContext.resolvedTab(sessionID.tabId, windowState),
              let webView = runtimeContext.resolvedNowPlayingWebView(tab, windowState)
        else { return nil }

        let residence = ResolvedResidence(
            tab: tab,
            windowState: windowState,
            webView: webView
        )
        return residence.id == sessionID ? residence : nil
    }

    private func isStillResolved(
        _ residence: ResolvedResidence,
        using runtimeContext: SumiNativeNowPlayingRuntimeContext
    ) -> Bool {
        guard let resolved = resolvedResidence(residence.id, using: runtimeContext) else {
            return false
        }
        return resolved.tab === residence.tab
            && resolved.windowState === residence.windowState
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

    private func retireSession(_ sessionID: SessionID) {
        sessions.removeValue(forKey: sessionID)
        removeCard(sessionID)
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

    private func isCurrentRefresh(_ generation: UInt64) -> Bool {
        generation == refreshGeneration && !Task.isCancelled && isFeatureEnabled
    }

    private func resetForDisabledFeature() {
        invalidateRefresh()
        sessions.removeAll()
        inFlightTransportSessions.removeAll()
        retiredSessionByResidence.removeAll()
        publish([])
    }

    private func residenceKey(for candidate: Candidate) -> SumiMediaResidenceKey {
        SumiMediaResidenceKey(
            tabId: candidate.tab.id,
            windowId: candidate.windowState.id
        )
    }

    private struct ResolvedResidence {
        let tab: Tab
        let windowState: BrowserWindowState
        let webView: any SumiNowPlayingWebViewAdapter
        let id: SessionID
        let residenceKey: SumiMediaResidenceKey

        @MainActor
        init(
            tab: Tab,
            windowState: BrowserWindowState,
            webView: any SumiNowPlayingWebViewAdapter
        ) {
            self.tab = tab
            self.windowState = windowState
            self.webView = webView
            id = SessionID(
                tabId: tab.id,
                windowId: windowState.id,
                residenceGeneration: tab.webViewSession.generation,
                webViewIdentity: ObjectIdentifier(webView)
            )
            residenceKey = SumiMediaResidenceKey(
                tabId: tab.id,
                windowId: windowState.id
            )
        }
    }

    private struct SessionRecord {
        private var playbackHold = PlaybackHold.none
        private var mutedByMiniPlayer = false
        private var suppressedPlaybackGeneration: UInt64?
        private var lastKnownInfo: SumiNativeNowPlayingInfo?

        private var isRetained: Bool {
            switch playbackHold {
            case .none:
                mutedByMiniPlayer
            case .pausedByMiniPlayer, .awaitingAudiblePlayback:
                true
            }
        }

        var isSuppressed: Bool {
            suppressedPlaybackGeneration != nil
        }

        mutating func setPlayback(
            _ playbackState: SumiBackgroundMediaPlaybackState,
            at playbackGeneration: UInt64
        ) {
            playbackHold = switch playbackState {
            case .paused: .pausedByMiniPlayer(at: playbackGeneration)
            case .playing: .awaitingAudiblePlayback
            }
        }

        mutating func setMuted(_ muted: Bool) {
            mutedByMiniPlayer = muted
        }

        mutating func dismiss(at playbackGeneration: UInt64) {
            suppress(at: playbackGeneration)
        }

        mutating func suppress(at playbackGeneration: UInt64) {
            playbackHold = .none
            mutedByMiniPlayer = false
            suppressedPlaybackGeneration = playbackGeneration
        }

        mutating func clearSuppression() {
            suppressedPlaybackGeneration = nil
        }

        mutating func reconcileExternalUnmute(
            nativeIsMuted: Bool,
            projectedIsMuted: Bool
        ) {
            if mutedByMiniPlayer && !nativeIsMuted && !projectedIsMuted {
                mutedByMiniPlayer = false
            }
        }

        func suppressionHasExpired(playbackGeneration: UInt64) -> Bool {
            guard let suppressedPlaybackGeneration else { return false }
            return playbackGeneration > suppressedPlaybackGeneration
        }

        func canRemainAdmitted(hasAudibleOutput: Bool) -> Bool {
            hasAudibleOutput || isRetained
        }

        mutating func reconcilePlayback(
            isPlayingAudio: Bool,
            playbackGeneration: UInt64
        ) {
            switch playbackHold {
            case .pausedByMiniPlayer(let pauseGeneration)
                where playbackGeneration > pauseGeneration:
                playbackHold = .none
            case .awaitingAudiblePlayback where isPlayingAudio:
                playbackHold = .none
            case .none, .pausedByMiniPlayer, .awaitingAudiblePlayback:
                break
            }
        }

        mutating func infoForPresentation(
            latest: SumiNativeNowPlayingInfo?,
            hasAudibleOutput: Bool
        ) -> SumiNativeNowPlayingInfo? {
            guard let latest else { return lastKnownInfo }
            guard !hasAudibleOutput, isRetained, let lastKnownInfo else {
                self.lastKnownInfo = latest
                return latest
            }

            let info = SumiNativeNowPlayingInfo(
                title: latest.title.isEmpty ? lastKnownInfo.title : latest.title,
                artist: latest.artist?.isEmpty == false ? latest.artist : lastKnownInfo.artist,
                playbackState: latest.playbackState,
                canPictureInPicture: latest.canPictureInPicture
            )
            self.lastKnownInfo = info
            return info
        }

        func projectedPlaybackState(
            isPlayingAudio: Bool,
            nativePlaybackState: SumiBackgroundMediaPlaybackState?
        ) -> SumiBackgroundMediaPlaybackState {
            switch playbackHold {
            case .pausedByMiniPlayer:
                return .paused
            case .awaitingAudiblePlayback:
                return .playing
            case .none:
                break
            }
            if isPlayingAudio { return .playing }
            return nativePlaybackState ?? .paused
        }

        func projectsMuted(nativeIsMuted: Bool) -> Bool {
            mutedByMiniPlayer || nativeIsMuted
        }

        private enum PlaybackHold {
            case none
            case pausedByMiniPlayer(at: UInt64)
            case awaitingAudiblePlayback
        }
    }

    enum SumiNativeNowPlayingCommand: Equatable {
        case play
        case pause
        case setMuted(Bool)
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
            return await tab.setSumiNativeNowPlayingPlayback(
                .playing,
                using: context,
                in: windowState
            )
        case .pause:
            return await tab.setSumiNativeNowPlayingPlayback(
                .paused,
                using: context,
                in: windowState
            )
        case .setMuted(let muted):
            return tab.setSumiNativeNowPlayingMuted(
                muted,
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
