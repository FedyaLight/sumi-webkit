import Foundation
import WebKit

/// The extension events whose payload depends on a publicly registered window.
@MainActor
protocol BrowserWindowExtensionPublication: AnyObject {
    func isCurrent() -> Bool
    func revokeIfCurrent()
    func revokeIfCurrent(
        closingPublishedTabs: @MainActor () -> Void
    )
}

extension BrowserWindowExtensionPublication {
    func revokeIfCurrent(
        closingPublishedTabs: @MainActor () -> Void
    ) {
        closingPublishedTabs()
        revokeIfCurrent()
    }
}

enum BrowserWindowExtensionPublicationOutcome {
    case notParticipating
    case suppressed
    case published(any BrowserWindowExtensionPublication)
}

@MainActor
protocol BrowserWindowExtensionPublishing: AnyObject {
    func publishWindowIfLoaded(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome
}

@MainActor
protocol BrowserWindowExtensionFocusNotifying: AnyObject {
    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState)
}

/// Silent preparation capability used before WindowRegistry publication.
@MainActor
protocol InitialTabExtensionPreparing: AnyObject {
    func prepareInitialTabExtensionPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> InitialTabExtensionPreparation
}

extension SumiExtensionsModule:
    BrowserWindowExtensionPublishing,
    BrowserWindowExtensionFocusNotifying,
    InitialTabExtensionPreparing {}

/// Owns the exact extension-facing half of WindowRegistry registration. It is
/// intentionally separate from model/session restoration: prepare is silent,
/// commit emits ordered window then Tab events, and discard is reversible.
@MainActor
final class WindowExtensionPublicationTransaction {
    typealias InitialTabResolver = @MainActor (
        BrowserWindowState
    ) -> (tab: Tab, webView: FocusableWKWebView)?

    enum StagingResult: Equatable {
        case extensionPrepared
        case nativeOnly
        case suppressed
        case rejected
    }

    enum InitialPublicationResult: Equatable {
        case extensionPublished
        case nativeOnly
        case suppressed
    }

    private struct ExactInitialTab {
        let tab: Tab
        let webView: FocusableWKWebView

        var tabID: UUID { tab.id }
        var tabIdentity: ObjectIdentifier { ObjectIdentifier(tab) }
        var webViewIdentity: ObjectIdentifier { ObjectIdentifier(webView) }

        func matches(tab: Tab, webView: FocusableWKWebView) -> Bool {
            tab.id == tabID
                && self.tab === tab
                && self.webView === webView
        }

        func matches(_ other: ExactInitialTab) -> Bool {
            tabID == other.tabID
                && tabIdentity == other.tabIdentity
                && webViewIdentity == other.webViewIdentity
        }
    }

    private enum InitialTabPublication {
        case unstaged
        case notParticipating(ExactInitialTab)
        case nativeOnly(ExactInitialTab)
        case prepared(any InitialTabExtensionPublication)
        case suppressed(ExactInitialTab)
    }

    private struct PendingPublication {
        let transactionID: UInt64
        let windowIdentity: ObjectIdentifier
        var initialTab: InitialTabPublication
    }

    private struct CommitAttempt {
        let transactionID: UInt64
        let windowIdentity: ObjectIdentifier
    }

    private struct CommittedPublication {
        let transactionID: UInt64
        let windowIdentity: ObjectIdentifier
        let result: InitialPublicationResult
        let extensionPublication: (any BrowserWindowExtensionPublication)?
        let initialTabPublication: (any InitialTabExtensionPublication)?
    }

    private let preparation: any InitialTabExtensionPreparing
    private let publication: any BrowserWindowExtensionPublishing
    private let resolveInitialTab: InitialTabResolver
    private var pendingByWindowID: [UUID: PendingPublication] = [:]
    private var committingByWindowID: [UUID: CommitAttempt] = [:]
    private var committedByWindowID: [UUID: CommittedPublication] = [:]
    private var nextTransactionID: UInt64 = 0

    init(
        preparation: any InitialTabExtensionPreparing,
        publication: any BrowserWindowExtensionPublishing,
        resolveInitialTab: @escaping InitialTabResolver = { _ in nil }
    ) {
        self.preparation = preparation
        self.publication = publication
        self.resolveInitialTab = resolveInitialTab
    }

    func prepareRegistration(_ window: BrowserWindowState) {
        if let pending = pendingByWindowID[window.id] {
            guard pending.windowIdentity == ObjectIdentifier(window) else {
                return
            }
            return
        }
        let identity = ObjectIdentifier(window)
        if committingByWindowID[window.id] != nil {
            return
        }
        if committedByWindowID[window.id] != nil {
            return
        }
        nextTransactionID &+= 1
        pendingByWindowID[window.id] = PendingPublication(
            transactionID: nextTransactionID,
            windowIdentity: identity,
            initialTab: .unstaged
        )
    }

    func stageInitialTab(
        _ tab: Tab,
        webView: FocusableWKWebView,
        in window: BrowserWindowState,
        reason: String
    ) -> StagingResult {
        guard let pending = pendingByWindowID[window.id],
              pending.windowIdentity == ObjectIdentifier(window),
              case .unstaged = pending.initialTab,
              window.currentTabId == tab.id,
              webView.owningTab === tab
        else {
            return .rejected
        }

        let exactTab = ExactInitialTab(
            tab: tab,
            webView: webView
        )
        let transactionID = pending.transactionID
        let nextInitialTab: InitialTabPublication
        let result: StagingResult
        switch preparation.prepareInitialTabExtensionPublication(
            window: window,
            tab: tab,
            webView: webView,
            reason: reason
        ) {
        case .notParticipating:
            nextInitialTab = .notParticipating(exactTab)
            result = .nativeOnly
        case .privateWindow:
            nextInitialTab = .nativeOnly(exactTab)
            result = .nativeOnly
        case .prepared(let receipt):
            guard receipt.matches(
                window: window,
                tab: tab,
                webView: webView
            ), receipt.validateBeforeWindowPublication() else {
                _ = receipt.cancel()
                return .rejected
            }
            nextInitialTab = .prepared(receipt)
            result = .extensionPrepared
        case .suppressed:
            nextInitialTab = .suppressed(exactTab)
            result = .suppressed
        case .rejected:
            return .rejected
        }
        guard var current = pendingByWindowID[window.id],
              current.transactionID == transactionID,
              current.windowIdentity == ObjectIdentifier(window),
              case .unstaged = current.initialTab,
              window.currentTabId == tab.id,
              webView.owningTab === tab
        else {
            cancel(nextInitialTab)
            return .rejected
        }
        current.initialTab = nextInitialTab
        pendingByWindowID[window.id] = current
        return result
    }

    func validateStagedInitialTab(
        _ tab: Tab,
        webView: FocusableWKWebView,
        in window: BrowserWindowState
    ) -> Bool {
        guard let pending = pendingByWindowID[window.id],
              pending.windowIdentity == ObjectIdentifier(window),
              window.currentTabId == tab.id,
              webView.owningTab === tab
        else {
            return false
        }

        let isValid: Bool
        switch pending.initialTab {
        case .unstaged:
            return false
        case .notParticipating(let exactTab),
             .nativeOnly(let exactTab),
             .suppressed(let exactTab):
            isValid = exactTab.matches(tab: tab, webView: webView)
        case .prepared(let receipt):
            isValid = receipt.matches(
                window: window,
                tab: tab,
                webView: webView
            ) && receipt.validateBeforeWindowPublication()
        }
        guard isValid,
              let current = pendingByWindowID[window.id],
              current.transactionID == pending.transactionID,
              current.windowIdentity == pending.windowIdentity
        else {
            return false
        }
        if case .prepared(let expected) = pending.initialTab {
            guard case .prepared(let currentReceipt) = current.initialTab,
                  (currentReceipt as AnyObject) === (expected as AnyObject)
            else {
                return false
            }
        }
        return true
    }

    func commitRegistration(_ window: BrowserWindowState) {
        guard var pending = pendingByWindowID[window.id],
              pending.windowIdentity == ObjectIdentifier(window)
        else {
            return
        }

        if case .unstaged = pending.initialTab,
           window.currentTabId != nil {
            guard let resolved = resolveInitialTab(window) else {
                finishPending(
                    pending,
                    as: .suppressed,
                    for: window
                )
                return
            }
            let stagingResult = stageInitialTab(
                resolved.tab,
                webView: resolved.webView,
                in: window,
                reason: "WindowExtensionPublicationTransaction.commitRegistration"
            )
            guard let staged = pendingByWindowID[window.id],
                  staged.transactionID == pending.transactionID,
                  staged.windowIdentity == ObjectIdentifier(window)
            else {
                return
            }
            if stagingResult == .rejected,
               case .unstaged = staged.initialTab {
                finishPending(
                    staged,
                    as: .suppressed,
                    for: window
                )
                return
            }
            pending = staged
        }

        if case .notParticipating(let exactTab) = pending.initialTab {
            guard window.currentTabId == exactTab.tabID,
                  exactTab.webView.owningTab === exactTab.tab
            else {
                finishPending(
                    pending,
                    as: .suppressed,
                    for: window
                )
                return
            }
            guard var current = pendingByWindowID[window.id],
                  current.transactionID == pending.transactionID,
                  current.windowIdentity == pending.windowIdentity
            else {
                return
            }
            current.initialTab = .unstaged
            pendingByWindowID[window.id] = current
            let stagingResult = stageInitialTab(
                exactTab.tab,
                webView: exactTab.webView,
                in: window,
                reason: "WindowExtensionPublicationTransaction.commitRegistration.revalidateParticipation"
            )
            guard let restaged = pendingByWindowID[window.id],
                  restaged.transactionID == pending.transactionID,
                  restaged.windowIdentity == ObjectIdentifier(window)
            else {
                return
            }
            if stagingResult == .rejected,
               case .unstaged = restaged.initialTab {
                finishPending(
                    restaged,
                    as: .suppressed,
                    for: window
                )
                return
            }
            pending = restaged
        }
        guard beginCommit(pending, for: window) else {
            cancel(pending.initialTab)
            return
        }

        switch pending.initialTab {
        case .suppressed:
            _ = record(
                .suppressed,
                for: window,
                transactionID: pending.transactionID
            )
        case .prepared(let receipt):
            let outcome = publication.publishWindowIfLoaded(window)
            guard isCommitCurrent(pending, for: window) else {
                if case .published(let publication) = outcome {
                    publication.revokeIfCurrent()
                }
                _ = receipt.cancel()
                return
            }
            switch outcome {
            case .published(let publication):
                guard receipt.publishInitialTab(
                    afterWindowOpened: window
                ) else {
                    publication.revokeIfCurrent(
                        closingPublishedTabs: {
                            _ = receipt.revokePublishedIfCurrent()
                        }
                    )
                    _ = receipt.cancel()
                    _ = record(
                        .suppressed,
                        for: window,
                        transactionID: pending.transactionID
                    )
                    return
                }
                guard isCommitCurrent(pending, for: window),
                      publication.isCurrent()
                else {
                    publication.revokeIfCurrent(
                        closingPublishedTabs: {
                            _ = receipt.revokePublishedIfCurrent()
                        }
                    )
                    _ = record(
                        .suppressed,
                        for: window,
                        transactionID: pending.transactionID
                    )
                    return
                }
                _ = record(
                    .extensionPublished,
                    for: window,
                    transactionID: pending.transactionID,
                    extensionPublication: publication,
                    initialTabPublication: receipt
                )
            case .notParticipating:
                _ = receipt.cancel()
                _ = record(
                    .nativeOnly,
                    for: window,
                    transactionID: pending.transactionID
                )
            case .suppressed:
                _ = receipt.cancel()
                _ = record(
                    .suppressed,
                    for: window,
                    transactionID: pending.transactionID
                )
            }
        case .unstaged:
            let outcome = publication.publishWindowIfLoaded(window)
            guard isCommitCurrent(pending, for: window) else {
                if case .published(let publication) = outcome {
                    publication.revokeIfCurrent()
                }
                return
            }
            switch outcome {
            case .published(let publication):
                // A loaded runtime may not publish a selected normal window
                // without a prepared initial Tab.
                publication.revokeIfCurrent()
                _ = record(
                    .suppressed,
                    for: window,
                    transactionID: pending.transactionID
                )
            case .notParticipating:
                _ = record(
                    .nativeOnly,
                    for: window,
                    transactionID: pending.transactionID
                )
            case .suppressed:
                _ = record(
                    .suppressed,
                    for: window,
                    transactionID: pending.transactionID
                )
            }
        case .notParticipating, .nativeOnly:
            _ = record(
                .nativeOnly,
                for: window,
                transactionID: pending.transactionID
            )
        }
    }

    func initialPublicationResult(
        for window: BrowserWindowState
    ) -> InitialPublicationResult? {
        guard let committed = committedByWindowID[window.id],
              committed.windowIdentity == ObjectIdentifier(window)
        else {
            return nil
        }
        if committed.result == .extensionPublished,
           committed.extensionPublication?.isCurrent() != true {
            return .suppressed
        }
        return committed.result
    }

    /// Rejects a shell after registry publication but before presentation. The
    /// exact extension open is balanced here because rejected registry rollback
    /// intentionally does not run the ordinary user-close workflow.
    func revokeCommittedPublicationIfNeeded(
        for window: BrowserWindowState
    ) {
        guard let committed = committedByWindowID[window.id],
              committed.windowIdentity == ObjectIdentifier(window)
        else {
            return
        }
        committedByWindowID.removeValue(forKey: window.id)
        revoke(committed)
    }

    func discardRegistration(_ window: BrowserWindowState) {
        if committedByWindowID[window.id]?.windowIdentity
            == ObjectIdentifier(window) {
            committedByWindowID.removeValue(forKey: window.id)
        }
        if committingByWindowID[window.id]?.windowIdentity
            == ObjectIdentifier(window) {
            committingByWindowID.removeValue(forKey: window.id)
        }
        guard pendingByWindowID[window.id]?.windowIdentity
                == ObjectIdentifier(window),
              let removed = pendingByWindowID.removeValue(forKey: window.id)
        else {
            return
        }
        cancel(removed.initialTab)
    }

    /// Registry reconciliation is authoritative: a missing exact object, or a
    /// replacement object with the same UUID, makes the old receipt stale.
    func discardRegistrations(
        notIn registeredWindows: [BrowserWindowState]
    ) {
        let registeredByID = Dictionary(
            uniqueKeysWithValues: registeredWindows.map {
                ($0.id, ObjectIdentifier($0))
            }
        )
        for (windowID, pending) in Array(pendingByWindowID) {
            guard registeredByID[windowID] == pending.windowIdentity else {
                pendingByWindowID.removeValue(forKey: windowID)
                cancel(pending.initialTab)
                continue
            }
        }
        for (windowID, committed) in Array(committedByWindowID)
            where registeredByID[windowID] != committed.windowIdentity {
            committedByWindowID.removeValue(forKey: windowID)
            revoke(committed)
        }
        for (windowID, attempt) in Array(committingByWindowID)
            where registeredByID[windowID] != attempt.windowIdentity {
            committingByWindowID.removeValue(forKey: windowID)
        }
    }

    private func cancel(_ initialTab: InitialTabPublication) {
        guard case .prepared(let receipt) = initialTab else { return }
        _ = receipt.cancel()
    }

    private func revoke(_ committed: CommittedPublication) {
        guard let extensionPublication = committed.extensionPublication else {
            _ = committed.initialTabPublication?.revokePublishedIfCurrent()
            return
        }
        extensionPublication.revokeIfCurrent(
            closingPublishedTabs: {
                _ = committed.initialTabPublication?
                    .revokePublishedIfCurrent()
            }
        )
    }

    private func finishPending(
        _ pending: PendingPublication,
        as result: InitialPublicationResult,
        for window: BrowserWindowState
    ) {
        guard beginCommit(pending, for: window) else { return }
        cancel(pending.initialTab)
        _ = record(
            result,
            for: window,
            transactionID: pending.transactionID
        )
    }

    private func beginCommit(
        _ pending: PendingPublication,
        for window: BrowserWindowState
    ) -> Bool {
        guard let current = pendingByWindowID[window.id],
              current.transactionID == pending.transactionID,
              current.windowIdentity == pending.windowIdentity,
              sameInitialPublication(
                  current.initialTab,
                  pending.initialTab
              ),
              current.windowIdentity == ObjectIdentifier(window)
        else {
            return false
        }
        pendingByWindowID.removeValue(forKey: window.id)
        committingByWindowID[window.id] = CommitAttempt(
            transactionID: pending.transactionID,
            windowIdentity: pending.windowIdentity
        )
        return true
    }

    private func isCommitCurrent(
        _ pending: PendingPublication,
        for window: BrowserWindowState
    ) -> Bool {
        guard let attempt = committingByWindowID[window.id] else {
            return false
        }
        return attempt.transactionID == pending.transactionID
            && attempt.windowIdentity == pending.windowIdentity
            && attempt.windowIdentity == ObjectIdentifier(window)
    }

    private func sameInitialPublication(
        _ lhs: InitialTabPublication,
        _ rhs: InitialTabPublication
    ) -> Bool {
        switch (lhs, rhs) {
        case (.unstaged, .unstaged):
            return true
        case let (.notParticipating(left), .notParticipating(right)),
             let (.nativeOnly(left), .nativeOnly(right)),
             let (.suppressed(left), .suppressed(right)):
            return left.matches(right)
        case let (.prepared(left), .prepared(right)):
            return (left as AnyObject) === (right as AnyObject)
        default:
            return false
        }
    }

    @discardableResult
    private func record(
        _ result: InitialPublicationResult,
        for window: BrowserWindowState,
        transactionID: UInt64,
        extensionPublication: (any BrowserWindowExtensionPublication)? = nil,
        initialTabPublication: (any InitialTabExtensionPublication)? = nil
    ) -> Bool {
        guard let attempt = committingByWindowID[window.id],
              attempt.transactionID == transactionID,
              attempt.windowIdentity == ObjectIdentifier(window)
        else {
            return false
        }
        committingByWindowID.removeValue(forKey: window.id)
        committedByWindowID[window.id] = CommittedPublication(
            transactionID: transactionID,
            windowIdentity: ObjectIdentifier(window),
            result: result,
            extensionPublication: extensionPublication,
            initialTabPublication: initialTabPublication
        )
        return true
    }
}
