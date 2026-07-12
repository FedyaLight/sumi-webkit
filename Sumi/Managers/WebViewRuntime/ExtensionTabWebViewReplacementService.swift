import Foundation
import WebKit

enum ExtensionTabWebViewReplacementRejection: Equatable {
    case runtimeTabIdentityConflict
    case creationFailed
    case validationFailed
    case trackedAdmission(TrackedWebViewAdmissionOutcome)
    case untrackedInstallation(UntrackedWebViewInstallationOutcome)
}

enum ExtensionTabWebViewReplacementOutcome {
    case committed(WKWebView)
    case deferred
    case superseded
    case rejected(ExtensionTabWebViewReplacementRejection)

    var committedWebView: WKWebView? {
        guard case .committed(let webView) = self else { return nil }
        return webView
    }
}

/// Creates and commits one replacement WebView for an extension-visible Tab.
/// Candidate ownership is settled exactly once across placement rejection,
/// website-data deferral, and replacement-pipeline consumption.
@MainActor
final class ExtensionTabWebViewReplacementService {
    private enum Slot: Hashable {
        case tracked(tabID: UUID, windowID: UUID)
        case untracked(tabID: UUID)
    }

    private struct Request: Equatable {
        let slot: Slot
        let revision: UInt64
    }

    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let query: WebViewOwnershipQuery
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let trackedAdmission: TrackedWebViewAdmissionService
    private let untrackedInstallation: UntrackedWebViewInstallationService
    private var nextRequestRevision: UInt64 = 0
    private var requestRevisionBySlot: [Slot: UInt64] = [:]

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        query: WebViewOwnershipQuery,
        websiteDataCleanup: WebsiteDataCleanupService,
        trackedAdmission: TrackedWebViewAdmissionService,
        untrackedInstallation: UntrackedWebViewInstallationService
    ) {
        self.runtimeTabs = runtimeTabs
        self.query = query
        self.websiteDataCleanup = websiteDataCleanup
        self.trackedAdmission = trackedAdmission
        self.untrackedInstallation = untrackedInstallation
    }

    @discardableResult
    func replace(
        for tab: Tab,
        in windowID: UUID?,
        reason: String,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)? = nil,
        prepareCommittedReplacement: ((WKWebView) -> Void)? = nil,
        validate: ((WKWebView) -> Bool)? = nil
    ) -> ExtensionTabWebViewReplacementOutcome {
        guard runtimeTabs.bind(tab).isAccepted else {
            return .rejected(.runtimeTabIdentityConflict)
        }
        let request = beginRequest(
            windowID.map { .tracked(tabID: tab.id, windowID: $0) }
                ?? .untracked(tabID: tab.id)
        )
        let replay = replacementReplay(
            tab: tab,
            windowID: windowID,
            reason: reason,
            prepareCandidateConfiguration: prepareCandidateConfiguration,
            prepareCommittedReplacement: prepareCommittedReplacement,
            validate: validate
        )
        if windowID == nil {
            precondition(
                query.windowIDs(for: tab.id).isEmpty,
                "Untracked replacement requires an untracked tab session"
            )
        }
        let isDeferred = if let windowID {
            websiteDataCleanup.deferTrackedWebViewReplacement(
                for: tab,
                in: windowID,
                replay: replay
            )
        } else {
            websiteDataCleanup.deferUntrackedWebViewReplacement(
                for: tab,
                replay: replay
            )
        }
        if isDeferred {
            finish(request)
            return .deferred
        }

        guard let replacement = tab.makeNormalTabWebView(
            reason: reason,
            prepareExtensionRuntime: false,
            prepareCandidateConfiguration: prepareCandidateConfiguration
        ) else {
            finish(request)
            return .rejected(.creationFailed)
        }
        guard isCurrent(request) else {
            tab.cleanupCloneWebView(replacement)
            return .superseded
        }
        if let validate {
            let isValid = validate(replacement)
            guard isCurrent(request) else {
                tab.cleanupCloneWebView(replacement)
                return .superseded
            }
            guard isValid else {
                tab.cleanupCloneWebView(replacement)
                finish(request)
                return .rejected(.validationFailed)
            }
        }

        guard isCurrent(request) else {
            tab.cleanupCloneWebView(replacement)
            return .superseded
        }

        if let windowID {
            let admission = trackedAdmission.attemptAssignment(
                replacement,
                to: tab,
                in: windowID,
                replaySemanticOperation: replay
            )
            guard admission.isAccepted else {
                tab.cleanupCloneWebView(replacement)
                if case .deferred = admission {
                    finish(request)
                    return .deferred
                }
                finish(request)
                return .rejected(.trackedAdmission(admission))
            }
        } else {
            if websiteDataCleanup.deferUntrackedWebViewReplacement(
                for: tab,
                replay: replay
            ) {
                tab.cleanupCloneWebView(replacement)
                finish(request)
                return .deferred
            }
            let outcome = untrackedInstallation.installUntracked(
                replacement,
                for: tab
            )
            guard outcome.isAccepted else {
                if outcome.callerRetainsWebView {
                    tab.cleanupCloneWebView(replacement)
                }
                finish(request)
                return .rejected(.untrackedInstallation(outcome))
            }
        }

        guard isCurrent(request) else { return .superseded }
        prepareCommittedReplacement?(replacement)
        guard isCurrent(request) else { return .superseded }
        finish(request)
        return .committed(replacement)
    }

    private func replacementReplay(
        tab: Tab,
        windowID: UUID?,
        reason: String,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)?,
        prepareCommittedReplacement: ((WKWebView) -> Void)?,
        validate: ((WKWebView) -> Bool)?
    ) -> @MainActor () -> Void {
        { [weak self, weak tab] in
            guard let self, let tab else { return }
            _ = replace(
                for: tab,
                in: windowID,
                reason: reason,
                prepareCandidateConfiguration: prepareCandidateConfiguration,
                prepareCommittedReplacement: prepareCommittedReplacement,
                validate: validate
            )
        }
    }

    private func beginRequest(_ slot: Slot) -> Request {
        nextRequestRevision &+= 1
        requestRevisionBySlot[slot] = nextRequestRevision
        return Request(slot: slot, revision: nextRequestRevision)
    }

    private func isCurrent(_ request: Request) -> Bool {
        requestRevisionBySlot[request.slot] == request.revision
    }

    private func finish(_ request: Request) {
        guard isCurrent(request) else { return }
        requestRevisionBySlot.removeValue(forKey: request.slot)
    }
}
