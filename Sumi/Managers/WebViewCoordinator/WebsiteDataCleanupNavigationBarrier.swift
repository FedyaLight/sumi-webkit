import Foundation
import Navigation
import SumiDomain
import SumiWebRuntime
import WebKit

struct WebsiteDataCleanupRestoreCommandReceipt {
    let outcome: TabMainFrameReloadCommandOutcome
    let semanticRevision: UInt64?

    init(
        outcome: TabMainFrameReloadCommandOutcome,
        semanticRevision: UInt64?
    ) {
        self.outcome = outcome
        self.semanticRevision = semanticRevision
    }
}

/// Owns the exact-navigation state machine for every live WebView touched by a
/// website-data cleanup. Discovery and restoration can request state changes,
/// but only this barrier resolves lifecycle callbacks and terminal waits.
@MainActor
final class WebsiteDataCleanupNavigationBarrier {
    struct NavigationIdentity {
        let id: ObjectIdentifier
        let lifetime: AnyObject
    }

    final class Session {
        let id = UUID()
        fileprivate(set) var participants: [Participant] = []
        fileprivate(set) var isInvalidated = false
    }

    final class Participant {
        let sessionID: UUID
        let tab: Tab
        let webView: WKWebView
        fileprivate var phase: ParticipantPhase = .discovered
        fileprivate var terminalResult: Bool?
        fileprivate var terminalContinuation: CheckedContinuation<Bool, Never>?
        fileprivate var terminalWaitID: UUID?
        fileprivate var bufferedRestoreStarts: [RestoreStartCandidate] = []
        fileprivate var wasTouched = false

        fileprivate init(sessionID: UUID, tab: Tab, webView: WKWebView) {
            self.sessionID = sessionID
            self.tab = tab
            self.webView = webView
        }
    }

    typealias MutationPermissionWaiter = @MainActor (WKWebView) async -> Bool
    typealias BlankNavigationLoader = @MainActor (WKWebView) -> NavigationIdentity?

    fileprivate enum ParticipantPhase {
        case discovered
        case awaitingBlank(NavigationIdentity)
        case blanked
        case awaitingRestoreStart(targetURL: URL, semanticRevision: UInt64?)
        case awaitingRestore(NavigationIdentity)
        case completed
        case abandoned
    }

    fileprivate struct RestoreStartCandidate {
        let navigation: NavigationIdentity
        let targetURL: URL
        let semanticRevision: UInt64?
    }

    private let waitForMutationPermission: MutationPermissionWaiter
    private let loadBlankNavigation: BlankNavigationLoader
    private let blankAttemptTimeout: Duration

    private var activeSession: Session?
    private var participantsByWebViewID: [ObjectIdentifier: Participant] = [:]
    private var isTerminallyShutDown = false

    init(
        waitForMutationPermission: @escaping MutationPermissionWaiter,
        loadBlankNavigation: BlankNavigationLoader? = nil,
        blankAttemptTimeout: Duration
    ) {
        self.waitForMutationPermission = waitForMutationPermission
        self.loadBlankNavigation = loadBlankNavigation ?? Self.loadBlank
        self.blankAttemptTimeout = blankAttemptTimeout
    }

    func beginSession() -> Session? {
        guard activeSession == nil, isTerminallyShutDown == false else {
            return nil
        }
        let session = Session()
        activeSession = session
        return session
    }

    func invalidate(_ session: Session) {
        guard activeSession === session else { return }
        session.isInvalidated = true
    }

    func isValid(_ session: Session) -> Bool {
        activeSession === session
            && session.isInvalidated == false
            && isTerminallyShutDown == false
    }

    func participantCount(in session: Session) -> Int {
        guard activeSession === session else { return 0 }
        return session.participants.count
    }

    func register(
        tab: Tab,
        webView: WKWebView,
        in session: Session,
        touchedAndBlanked: Bool = false
    ) -> Participant? {
        guard activeSession === session,
              isTerminallyShutDown == false else {
            return nil
        }

        let webViewID = ObjectIdentifier(webView)
        if let existing = participantsByWebViewID[webViewID] {
            precondition(
                existing.webView === webView,
                "Live WebView identity was reused during destructive cleanup"
            )
            return existing
        }

        let participant = Participant(
            sessionID: session.id,
            tab: tab,
            webView: webView
        )
        if touchedAndBlanked {
            participant.wasTouched = true
            participant.phase = .blanked
        }
        session.participants.append(participant)
        participantsByWebViewID[webViewID] = participant
        return participant
    }

    func contains(_ webView: WKWebView, in session: Session) -> Bool {
        guard activeSession === session,
              let participant = exactParticipant(for: webView) else {
            return false
        }
        return participant.sessionID == session.id
    }

    func prepare(_ participant: Participant) async -> Bool {
        participant.wasTouched = true
        guard stillOwns(participant),
              await waitForMutationPermission(participant.webView),
              stillOwns(participant),
              isTerminallyShutDown == false,
              isAbandoned(participant) == false
        else {
            abandon(participant)
            return false
        }

        let hadActiveLoad = participant.webView.isLoading
        quiescePhysicalActivity(on: participant.webView)
        if hadActiveLoad == false,
           Self.isBlank(participant.webView.committedURL ?? participant.webView.url) {
            participant.phase = .blanked
            return true
        }

        beginTerminalWait(for: participant)
        guard let navigation = loadBlankNavigation(participant.webView) else {
            completeTerminalWait(for: participant, result: false)
            participant.phase = .abandoned
            return false
        }
        participant.phase = .awaitingBlank(navigation)

        guard await terminalResult(
            for: participant,
            timeout: blankAttemptTimeout
        ) else {
            participant.phase = .abandoned
            return false
        }
        participant.phase = .blanked
        return true
    }

    func stillOwns(_ participant: Participant) -> Bool {
        participant.tab.webViewSession.owns(participant.webView)
    }

    func ownedParticipants(in session: Session) -> [Participant] {
        guard activeSession === session else { return [] }
        return session.participants.filter(stillOwns)
    }

    func touchedOwnedParticipants(in session: Session) -> [Participant] {
        guard activeSession === session else { return [] }
        return session.participants.filter { participant in
            participant.wasTouched && stillOwns(participant)
        }
    }

    func beginRestoreAttempt(
        _ participants: [Participant],
        targetURL: URL
    ) {
        for participant in participants {
            beginTerminalWait(for: participant)
            participant.bufferedRestoreStarts.removeAll()
            participant.phase = .awaitingRestoreStart(
                targetURL: targetURL,
                semanticRevision: nil
            )
        }
    }

    func bindRestoreReceipt(
        _ receipt: WebsiteDataCleanupRestoreCommandReceipt,
        to participant: Participant
    ) {
        guard case .awaitingRestoreStart(let targetURL, _) = participant.phase,
              let semanticRevision = receipt.semanticRevision else {
            return
        }
        participant.phase = .awaitingRestoreStart(
            targetURL: targetURL,
            semanticRevision: semanticRevision
        )
        guard let candidate = participant.bufferedRestoreStarts.first(where: {
            $0.semanticRevision == semanticRevision
                && WebRuntimeNavigationIdentity.matches($0.targetURL, targetURL)
        }) else {
            return
        }
        participant.bufferedRestoreStarts.removeAll()
        participant.phase = .awaitingRestore(candidate.navigation)
    }

    func rejectRestoreAttempt(_ participants: [Participant]) {
        participants.forEach {
            completeTerminalWait(for: $0, result: false)
        }
    }

    func awaitRestoreTermination(
        for participant: Participant,
        timeout: Duration
    ) async -> Bool {
        await terminalResult(for: participant, timeout: timeout)
    }

    func finishRestoreAttempt(
        _ participants: [Participant],
        succeeded: Bool
    ) {
        for participant in participants where stillOwns(participant) {
            participant.phase = succeeded ? .completed : .blanked
        }
    }

    func markBlanked(_ participants: [Participant]) {
        for participant in participants where stillOwns(participant) {
            participant.phase = .blanked
        }
    }

    func currentRestoreParticipants(
        for tab: Tab,
        liveWebViews: [WKWebView],
        in session: Session
    ) -> [Participant] {
        guard activeSession === session else { return [] }
        return liveWebViews.compactMap { webView in
            if let participant = exactParticipant(for: webView) {
                guard participant.tab.id == tab.id,
                      stillOwns(participant) else {
                    return nil
                }
                return participant
            }
            guard tab.webViewSession.owns(webView) else { return nil }
            return register(
                tab: tab,
                webView: webView,
                in: session,
                touchedAndBlanked: true
            )
        }
    }

    func pendingRestoreParticipants(
        among participants: [Participant]
    ) -> [Participant] {
        participants.filter { participant in
            if case .completed = participant.phase { return false }
            return true
        }
    }

    func abandon(_ participant: Participant) {
        switch participant.phase {
        case .awaitingBlank, .awaitingRestore, .awaitingRestoreStart:
            completeTerminalWait(for: participant, result: false)
        case .discovered, .blanked, .completed, .abandoned:
            break
        }
        participant.phase = .abandoned
        participant.bufferedRestoreStarts.removeAll()
    }

    func abandon(_ participants: [Participant]) {
        participants.forEach(abandon)
    }

    func release(_ session: Session) {
        guard activeSession === session else { return }
        for participant in session.participants {
            let webViewID = ObjectIdentifier(participant.webView)
            if participantsByWebViewID[webViewID] === participant {
                participantsByWebViewID.removeValue(forKey: webViewID)
            }
            if participant.terminalContinuation != nil {
                completeTerminalWait(for: participant, result: false)
            }
        }
        activeSession = nil
    }

    func isSuppressingNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        guard let participant = exactParticipant(for: webView),
              case .awaitingBlank(let expected) = participant.phase else {
            return false
        }
        return expected.id == navigationID
            && expected.lifetime === navigationLifetime
    }

    func navigationWillStart(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        semanticRevision: UInt64?
    ) {
        guard let participant = exactParticipant(for: webView) else { return }

        if case .blanked = participant.phase {
            activeSession?.isInvalidated = true
            return
        }

        guard case .awaitingRestoreStart(
            let expectedTargetURL,
            let expectedSemanticRevision
        ) = participant.phase,
        let targetURL,
        WebRuntimeNavigationIdentity.matches(targetURL, expectedTargetURL) else {
            return
        }

        let candidate = RestoreStartCandidate(
            navigation: NavigationIdentity(
                id: navigationID,
                lifetime: navigationLifetime
            ),
            targetURL: targetURL,
            semanticRevision: semanticRevision
        )
        guard let expectedSemanticRevision else {
            participant.bufferedRestoreStarts.append(candidate)
            return
        }
        guard candidate.semanticRevision == expectedSemanticRevision else {
            return
        }
        participant.phase = .awaitingRestore(candidate.navigation)
    }

    func navigationDidTerminate(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        succeeded: Bool
    ) {
        guard let participant = exactParticipant(for: webView) else { return }
        let expected: NavigationIdentity
        switch participant.phase {
        case .awaitingBlank(let navigation), .awaitingRestore(let navigation):
            expected = navigation
        case .discovered, .blanked, .awaitingRestoreStart, .completed, .abandoned:
            return
        }
        guard expected.id == navigationID,
              expected.lifetime === navigationLifetime else {
            return
        }
        completeTerminalWait(for: participant, result: succeeded)
    }

    func webContentProcessDidTerminate(on webView: WKWebView) -> Bool {
        guard let participant = exactParticipant(for: webView) else {
            return false
        }
        switch participant.phase {
        case .awaitingBlank, .awaitingRestore, .awaitingRestoreStart:
            completeTerminalWait(for: participant, result: false)
        case .discovered, .blanked:
            break
        case .completed, .abandoned:
            return false
        }
        participant.phase = .abandoned
        return true
    }

    func webViewDidLeaveRuntime(_ webView: WKWebView) {
        guard let participant = exactParticipant(for: webView) else { return }
        abandon(participant)
    }

    func webViewsDidLeaveRuntime(_ webViewIDs: [ObjectIdentifier]) {
        for webViewID in webViewIDs {
            guard let participant = participantsByWebViewID[webViewID] else {
                continue
            }
            abandon(participant)
        }
    }

    func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        if let activeSession {
            abandon(activeSession.participants)
        }
        participantsByWebViewID.removeAll()
    }

    private func isAbandoned(_ participant: Participant) -> Bool {
        if case .abandoned = participant.phase { return true }
        return false
    }

    private func beginTerminalWait(for participant: Participant) {
        precondition(participant.terminalContinuation == nil)
        participant.terminalResult = nil
        participant.terminalWaitID = UUID()
    }

    private func terminalResult(
        for participant: Participant,
        timeout: Duration
    ) async -> Bool {
        guard let terminalWaitID = participant.terminalWaitID else {
            return false
        }
        if let result = participant.terminalResult {
            participant.terminalResult = nil
            participant.terminalWaitID = nil
            return result
        }

        let sessionID = participant.sessionID
        let webViewID = ObjectIdentifier(participant.webView)
        let watchdog = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self,
                  self.activeSession?.id == sessionID,
                  let current = self.participantsByWebViewID[webViewID],
                  current.sessionID == sessionID,
                  current.terminalWaitID == terminalWaitID else {
                return
            }
            self.completeTerminalWait(for: current, result: false)
        }
        defer { watchdog.cancel() }

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                precondition(participant.terminalContinuation == nil)
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if let result = participant.terminalResult {
                    participant.terminalResult = nil
                    continuation.resume(returning: result)
                } else {
                    participant.terminalContinuation = continuation
                }
            }
        } onCancel: { [weak self, sessionID, webViewID] in
            Task { @MainActor [weak self, sessionID, webViewID] in
                guard let self,
                      self.activeSession?.id == sessionID,
                      let participant = self.participantsByWebViewID[webViewID],
                      participant.sessionID == sessionID else {
                    return
                }
                self.completeTerminalWait(for: participant, result: false)
            }
        }
        if participant.terminalWaitID == terminalWaitID {
            participant.terminalWaitID = nil
        }
        participant.terminalResult = nil
        return result
    }

    private func completeTerminalWait(
        for participant: Participant,
        result: Bool
    ) {
        guard participant.terminalWaitID != nil else { return }
        if let continuation = participant.terminalContinuation {
            participant.terminalContinuation = nil
            continuation.resume(returning: result)
        } else {
            participant.terminalResult = result
        }
    }

    private func exactParticipant(for webView: WKWebView) -> Participant? {
        let participant = participantsByWebViewID[ObjectIdentifier(webView)]
        return participant?.webView === webView ? participant : nil
    }

    private func quiescePhysicalActivity(on webView: WKWebView) {
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }
    }

    private static func loadBlank(
        on webView: WKWebView
    ) -> NavigationIdentity? {
        guard let navigator = webView.navigator(),
              let navigation = webView.load(
                  URLRequest(url: SumiSurface.emptyTabURL)
              ) else {
            return nil
        }
        let expectedNavigation = navigator.expect(navigation)
        return NavigationIdentity(
            id: expectedNavigation.stableIdentifier,
            lifetime: expectedNavigation.identityLifetime
        )
    }

    private static func isBlank(_ url: URL?) -> Bool {
        url.map(SumiSurface.isEmptyNewTabURL) == true
    }
}
