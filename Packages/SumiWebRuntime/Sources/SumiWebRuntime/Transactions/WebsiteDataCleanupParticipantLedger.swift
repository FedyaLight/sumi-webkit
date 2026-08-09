import Foundation
import WebKit

/// Product-agnostic state machine for the exact WebViews participating in one
/// destructive website-data transaction. The app retains Tab/Profile policy
/// and performs physical WebKit effects; this ledger alone owns session,
/// navigation-phase, receipt buffering, timeout and terminal settlement state.
@MainActor
public final class WebsiteDataCleanupParticipantLedger {
    public struct NavigationIdentity {
        public let id: ObjectIdentifier
        public let lifetime: AnyObject

        public init(id: ObjectIdentifier, lifetime: AnyObject) {
            self.id = id
            self.lifetime = lifetime
        }
    }

    public final class Session {
        public let id = UUID()
        fileprivate var participants: [Participant] = []
        fileprivate var isInvalidated = false

        fileprivate init() {}
    }

    public final class Participant {
        public let sessionID: UUID
        public let webView: WKWebView
        fileprivate var phase: ParticipantPhase = .discovered
        fileprivate var terminalWait: WebsiteDataCleanupTerminalReceipt?
        fileprivate var bufferedBlankStarts: [BlankStartCandidate] = []
        fileprivate var wasTouched = false

        fileprivate init(sessionID: UUID, webView: WKWebView) {
            self.sessionID = sessionID
            self.webView = webView
        }
    }

    fileprivate enum ParticipantPhase {
        case discovered
        case submittingBlank(targetURL: URL)
        case awaitingBlank(NavigationIdentity)
        case blanked
        case awaitingRestoreSubmission(targetURL: URL)
        case completed
        case abandoned
    }

    fileprivate struct BlankStartCandidate {
        let navigation: NavigationIdentity
        var terminalResult: Bool?
    }

    private var activeSession: Session?
    private var participantsByWebViewID: [ObjectIdentifier: Participant] = [:]
    private var isTerminallyShutDown = false

    public init() {}

    public func beginSession() -> Session? {
        guard activeSession == nil, isTerminallyShutDown == false else {
            return nil
        }
        let session = Session()
        activeSession = session
        return session
    }

    public func invalidate(_ session: Session) {
        guard activeSession === session else { return }
        session.isInvalidated = true
    }

    public func isValid(_ session: Session) -> Bool {
        activeSession === session
            && session.isInvalidated == false
            && isTerminallyShutDown == false
    }

    public func participantCount(in session: Session) -> Int {
        guard activeSession === session else { return 0 }
        return session.participants.count
    }

    public func register(
        _ webView: WKWebView,
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

        let participant = Participant(sessionID: session.id, webView: webView)
        if touchedAndBlanked {
            participant.wasTouched = true
            participant.phase = .blanked
        }
        session.participants.append(participant)
        participantsByWebViewID[webViewID] = participant
        return participant
    }

    public func contains(_ webView: WKWebView, in session: Session) -> Bool {
        guard activeSession === session,
              let participant = participant(for: webView) else {
            return false
        }
        return participant.sessionID == session.id
    }

    public func participant(for webView: WKWebView) -> Participant? {
        let participant = participantsByWebViewID[ObjectIdentifier(webView)]
        return participant?.webView === webView ? participant : nil
    }

    public func markTouched(_ participant: Participant) {
        guard owns(participant) else { return }
        participant.wasTouched = true
    }

    public func wasTouched(_ participant: Participant) -> Bool {
        owns(participant) && participant.wasTouched
    }

    public func isAbandoned(_ participant: Participant) -> Bool {
        guard owns(participant) else { return true }
        if case .abandoned = participant.phase { return true }
        return false
    }

    public func beginBlankSubmission(
        for participant: Participant,
        targetURL: URL,
        deadline: ContinuousClock.Instant
    ) {
        guard owns(participant) else { return }
        beginTerminalWait(for: participant, deadline: deadline)
        participant.bufferedBlankStarts.removeAll()
        participant.phase = .submittingBlank(targetURL: targetURL)
    }

    @discardableResult
    public func bindBlankNavigation(
        _ navigation: NavigationIdentity,
        to participant: Participant
    ) -> Bool {
        guard owns(participant),
              case .submittingBlank = participant.phase else {
            return false
        }
        let candidate = participant.bufferedBlankStarts.first {
            $0.navigation.id == navigation.id
                && $0.navigation.lifetime === navigation.lifetime
        }
        if candidate == nil, participant.bufferedBlankStarts.isEmpty == false {
            activeSession?.isInvalidated = true
            discardTerminalWait(for: participant)
            participant.phase = .abandoned
            participant.bufferedBlankStarts.removeAll()
            return false
        }
        participant.bufferedBlankStarts.removeAll()
        participant.phase = .awaitingBlank(navigation)
        if let terminalResult = candidate?.terminalResult {
            completeTerminalWait(for: participant, result: terminalResult)
        }
        return true
    }

    public func beginRestoreSubmission(
        _ participants: [Participant],
        targetURL: URL
    ) {
        for participant in participants where owns(participant) {
            switch participant.phase {
            case .blanked, .awaitingRestoreSubmission:
                participant.phase = .awaitingRestoreSubmission(
                    targetURL: targetURL
                )
            case .discovered, .submittingBlank, .awaitingBlank,
                 .completed, .abandoned:
                break
            }
        }
    }

    @discardableResult
    public func transferRestoreSubmission(
        for participant: Participant,
        targetURL: URL
    ) -> Bool {
        guard owns(participant),
              case .awaitingRestoreSubmission(let expectedTargetURL) = participant.phase,
              WebRuntimeNavigationIdentity.matches(targetURL, expectedTargetURL) else {
            return false
        }
        participant.phase = .completed
        return true
    }

    public func awaitTerminalResult(for participant: Participant) async -> Bool {
        await terminalResult(for: participant)
    }

    public func markBlanked(_ participants: [Participant]) {
        for participant in participants where owns(participant) {
            participant.phase = .blanked
        }
    }

    public func markBlanked(_ participant: Participant) {
        markBlanked([participant])
    }

    public func abandon(_ participant: Participant) {
        guard owns(participant) else { return }
        switch participant.phase {
        case .submittingBlank, .awaitingBlank:
            discardTerminalWait(for: participant)
        case .discovered, .blanked, .awaitingRestoreSubmission,
             .completed, .abandoned:
            break
        }
        participant.phase = .abandoned
        participant.bufferedBlankStarts.removeAll()
    }

    public func abandon(_ participants: [Participant]) {
        participants.forEach(abandon)
    }

    public func release(_ session: Session) {
        guard activeSession === session else { return }
        for participant in session.participants {
            let webViewID = ObjectIdentifier(participant.webView)
            if participantsByWebViewID[webViewID] === participant {
                participantsByWebViewID.removeValue(forKey: webViewID)
            }
            if participant.terminalWait != nil {
                discardTerminalWait(for: participant)
            }
        }
        activeSession = nil
    }

    public func isSuppressingNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        guard let participant = participant(for: webView) else {
            return false
        }
        switch participant.phase {
        case .submittingBlank:
            return participant.bufferedBlankStarts.contains {
                $0.navigation.id == navigationID
                    && $0.navigation.lifetime === navigationLifetime
            }
        case .awaitingBlank(let expected):
            return expected.id == navigationID
                && expected.lifetime === navigationLifetime
        case .discovered, .blanked, .awaitingRestoreSubmission,
             .completed, .abandoned:
            return false
        }
    }

    public func navigationWillStart(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        semanticRevision: UInt64?
    ) {
        guard let participant = participant(for: webView) else { return }

        if case .submittingBlank(let expectedTargetURL) = participant.phase {
            guard let targetURL,
                  WebRuntimeNavigationIdentity.matches(
                      targetURL,
                      expectedTargetURL
                  ) else {
                activeSession?.isInvalidated = true
                return
            }
            participant.bufferedBlankStarts.append(
                BlankStartCandidate(
                    navigation: NavigationIdentity(
                        id: navigationID,
                        lifetime: navigationLifetime
                    ),
                    terminalResult: nil
                )
            )
            return
        }

        if case .blanked = participant.phase {
            activeSession?.isInvalidated = true
            return
        }

        // Restore callbacks belong to the ordinary successor document. The
        // cleanup transaction transfers authority only from the concrete
        // native submission proof returned by the command owner.
    }

    public func navigationDidTerminate(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        succeeded: Bool
    ) {
        guard let participant = participant(for: webView) else { return }
        let expected: NavigationIdentity
        switch participant.phase {
        case .submittingBlank:
            guard let index = participant.bufferedBlankStarts.firstIndex(
                where: {
                    $0.navigation.id == navigationID
                        && $0.navigation.lifetime === navigationLifetime
                }
            ) else {
                return
            }
            participant.bufferedBlankStarts[index].terminalResult = succeeded
            return
        case .awaitingBlank(let navigation):
            expected = navigation
        case .discovered, .blanked, .awaitingRestoreSubmission,
             .completed, .abandoned:
            return
        }
        guard expected.id == navigationID,
              expected.lifetime === navigationLifetime else {
            return
        }
        completeTerminalWait(for: participant, result: succeeded)
    }

    public func webContentProcessDidTerminate(on webView: WKWebView) -> Bool {
        guard let participant = participant(for: webView) else {
            return false
        }
        switch participant.phase {
        case .submittingBlank, .awaitingBlank:
            discardTerminalWait(for: participant)
        case .discovered, .blanked, .awaitingRestoreSubmission:
            break
        case .completed, .abandoned:
            return false
        }
        participant.phase = .abandoned
        return true
    }

    public func webViewDidLeaveRuntime(_ webView: WKWebView) {
        guard let participant = participant(for: webView) else { return }
        abandon(participant)
    }

    public func webViewsDidLeaveRuntime(_ webViewIDs: [ObjectIdentifier]) {
        for webViewID in webViewIDs {
            guard let participant = participantsByWebViewID[webViewID] else {
                continue
            }
            abandon(participant)
        }
    }

    public func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        if let activeSession {
            abandon(activeSession.participants)
        }
        participantsByWebViewID.removeAll()
    }

    private func owns(_ participant: Participant) -> Bool {
        activeSession?.id == participant.sessionID
            && participantsByWebViewID[ObjectIdentifier(participant.webView)] === participant
    }

    private func beginTerminalWait(
        for participant: Participant,
        deadline: ContinuousClock.Instant
    ) {
        precondition(participant.terminalWait == nil)
        participant.terminalWait = WebsiteDataCleanupTerminalReceipt(
            deadline: deadline
        )
    }

    private func terminalResult(for participant: Participant) async -> Bool {
        guard owns(participant),
              let terminalWait = participant.terminalWait else {
            return false
        }
        let result = await terminalWait.awaitResult()
        if participant.terminalWait === terminalWait {
            participant.terminalWait = nil
        }
        return result
    }

    private func completeTerminalWait(
        for participant: Participant,
        result: Bool
    ) {
        guard owns(participant),
              let terminalWait = participant.terminalWait else {
            return
        }
        terminalWait.complete(with: result)
    }

    private func discardTerminalWait(for participant: Participant) {
        guard let terminalWait = participant.terminalWait else { return }
        participant.terminalWait = nil
        terminalWait.discard()
    }
}
