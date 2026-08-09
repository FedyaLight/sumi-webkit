import Foundation
import Navigation
import SumiDomain
import SumiWebRuntime
import WebKit

struct WebsiteDataCleanupRestoreCommandReceipt {
    let outcome: PageReloadCommandOutcome
    let semanticRevision: UInt64?

    init(
        outcome: PageReloadCommandOutcome,
        semanticRevision: UInt64?
    ) {
        self.outcome = outcome
        self.semanticRevision = semanticRevision
    }
}

/// Applies app-owned Tab ownership and physical WebKit effects around the
/// package-owned participant/navigation state machine.
@MainActor
final class WebsiteDataCleanupNavigationBarrier {
    typealias NavigationIdentity =
        WebsiteDataCleanupParticipantLedger.NavigationIdentity

    final class Session {
        fileprivate let ledgerSession: WebsiteDataCleanupParticipantLedger.Session
        fileprivate(set) var participants: [Participant] = []

        var id: UUID { ledgerSession.id }

        fileprivate init(
            ledgerSession: WebsiteDataCleanupParticipantLedger.Session
        ) {
            self.ledgerSession = ledgerSession
        }
    }

    final class Participant {
        fileprivate let ledgerParticipant:
            WebsiteDataCleanupParticipantLedger.Participant
        let tab: Tab

        var sessionID: UUID { ledgerParticipant.sessionID }
        var webView: WKWebView { ledgerParticipant.webView }

        fileprivate init(
            ledgerParticipant: WebsiteDataCleanupParticipantLedger.Participant,
            tab: Tab
        ) {
            self.ledgerParticipant = ledgerParticipant
            self.tab = tab
        }
    }

    typealias MutationPermissionWaiter = @MainActor (WKWebView) async -> Bool
    typealias BlankNavigationLoader = @MainActor (WKWebView) -> NavigationIdentity?

    private let waitForMutationPermission: MutationPermissionWaiter
    private let loadBlankNavigation: BlankNavigationLoader
    private let blankAttemptTimeout: Duration
    private let participantLedger = WebsiteDataCleanupParticipantLedger()

    private var activeSession: Session?

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
        guard activeSession == nil,
              let ledgerSession = participantLedger.beginSession() else {
            return nil
        }
        let session = Session(ledgerSession: ledgerSession)
        activeSession = session
        return session
    }

    func invalidate(_ session: Session) {
        guard activeSession === session else { return }
        participantLedger.invalidate(session.ledgerSession)
    }

    func isValid(_ session: Session) -> Bool {
        activeSession === session
            && participantLedger.isValid(session.ledgerSession)
    }

    func participantCount(in session: Session) -> Int {
        guard activeSession === session else { return 0 }
        return participantLedger.participantCount(in: session.ledgerSession)
    }

    func register(
        tab: Tab,
        webView: WKWebView,
        in session: Session,
        touchedAndBlanked: Bool = false
    ) -> Participant? {
        guard activeSession === session else { return nil }
        if let existing = exactParticipant(for: webView) {
            return existing
        }
        precondition(
            participantLedger.participant(for: webView) == nil,
            "App and cleanup-ledger participant indexes diverged"
        )
        guard let ledgerParticipant = participantLedger.register(
            webView,
            in: session.ledgerSession,
            touchedAndBlanked: touchedAndBlanked
        ) else {
            return nil
        }
        let participant = Participant(
            ledgerParticipant: ledgerParticipant,
            tab: tab
        )
        session.participants.append(participant)
        tab.beginWebsiteDataMutationPresentation(
            sessionID: session.id,
            destination: tab.mainFrameLoads.currentIntent.targetURL
        )
        return participant
    }

    func contains(_ webView: WKWebView, in session: Session) -> Bool {
        guard activeSession === session else { return false }
        return participantLedger.contains(webView, in: session.ledgerSession)
    }

    func prepare(_ participant: Participant) async -> Bool {
        guard Task.isCancelled == false,
              stillOwns(participant),
              await waitForMutationPermission(participant.webView),
              stillOwns(participant),
              Task.isCancelled == false,
              participantLedger.isAbandoned(participant.ledgerParticipant) == false
        else {
            abandon(participant)
            return false
        }

        participantLedger.markTouched(participant.ledgerParticipant)
        let hadActiveLoad = participant.webView.isLoading
        quiescePhysicalActivity(on: participant.webView)
        if hadActiveLoad == false,
           Self.isBlank(participant.webView.committedURL ?? participant.webView.url) {
            participantLedger.markBlanked(participant.ledgerParticipant)
            return true
        }

        participantLedger.beginBlankSubmission(
            for: participant.ledgerParticipant,
            targetURL: SumiSurface.emptyTabURL,
            deadline: ContinuousClock.now + blankAttemptTimeout
        )
        guard let navigation = loadBlankNavigation(participant.webView),
              participantLedger.bindBlankNavigation(
                  navigation,
                  to: participant.ledgerParticipant
              ) else {
            participantLedger.abandon(participant.ledgerParticipant)
            return false
        }

        guard await participantLedger.awaitTerminalResult(
            for: participant.ledgerParticipant
        ) else {
            participantLedger.abandon(participant.ledgerParticipant)
            return false
        }
        participantLedger.markBlanked(participant.ledgerParticipant)
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
            participantLedger.wasTouched(participant.ledgerParticipant)
                && stillOwns(participant)
        }
    }

    func beginRestoreSubmission(
        _ participants: [Participant],
        targetURL: URL
    ) {
        participantLedger.beginRestoreSubmission(
            participants.filter(stillOwns).map(\.ledgerParticipant),
            targetURL: targetURL
        )
    }

    @discardableResult
    func transferRestoreSubmission(
        for participant: Participant,
        targetURL: URL
    ) -> Bool {
        participantLedger.transferRestoreSubmission(
            for: participant.ledgerParticipant,
            targetURL: targetURL
        )
    }

    func markBlanked(_ participants: [Participant]) {
        participantLedger.markBlanked(
            participants.filter(stillOwns).map(\.ledgerParticipant)
        )
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

    func abandon(_ participant: Participant) {
        participantLedger.abandon(participant.ledgerParticipant)
    }

    func abandon(_ participants: [Participant]) {
        participantLedger.abandon(participants.map(\.ledgerParticipant))
    }

    func release(_ session: Session) {
        guard activeSession === session else { return }
        let tabs = Dictionary(
            session.participants.map { ($0.tab.id, $0.tab) },
            uniquingKeysWith: { first, _ in first }
        ).values
        participantLedger.release(session.ledgerSession)
        activeSession = nil
        for tab in tabs {
            tab.endWebsiteDataMutationPresentation(sessionID: session.id)
        }
    }

    func isSuppressingNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        participantLedger.isSuppressingNavigation(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func navigationWillStart(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        semanticRevision: UInt64?
    ) {
        participantLedger.navigationWillStart(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            semanticRevision: semanticRevision
        )
    }

    func navigationDidTerminate(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        succeeded: Bool
    ) {
        participantLedger.navigationDidTerminate(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            succeeded: succeeded
        )
    }

    func webContentProcessDidTerminate(on webView: WKWebView) -> Bool {
        participantLedger.webContentProcessDidTerminate(on: webView)
    }

    func webViewDidLeaveRuntime(_ webView: WKWebView) {
        participantLedger.webViewDidLeaveRuntime(webView)
    }

    func webViewsDidLeaveRuntime(_ webViewIDs: [ObjectIdentifier]) {
        participantLedger.webViewsDidLeaveRuntime(webViewIDs)
    }

    func resetForTerminalShutdown() {
        participantLedger.resetForTerminalShutdown()
    }

    private func exactParticipant(for webView: WKWebView) -> Participant? {
        guard let ledgerParticipant = participantLedger.participant(for: webView),
              let activeSession else {
            return nil
        }
        return activeSession.participants.first {
            $0.ledgerParticipant === ledgerParticipant
        }
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

    private static func loadBlank(on webView: WKWebView) -> NavigationIdentity? {
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
