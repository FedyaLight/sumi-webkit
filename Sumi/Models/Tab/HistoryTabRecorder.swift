import Foundation
import WebKit

@MainActor
final class HistoryTabRecorder {
    private enum VisitState {
        case expected
        case added
    }

    private var currentURL: URL? {
        didSet {
            if oldValue != currentURL {
                visitState = .expected
            }
        }
    }
    private var visitState: VisitState = .expected
    private(set) var localVisitIDs: [UUID] = []

    func didCommitMainFrameNavigation(
        to url: URL,
        kind: SumiHistoryNavigationKind,
        tab: Tab
    ) {
        currentURL = url
        guard shouldCapture(url: url, tab: tab), visitState == .expected else { return }

        if kind == .backForward {
            visitState = .added
            return
        }

        addVisit(url: url, tab: tab)
    }

    func didSameDocumentNavigation(to url: URL, type: SumiSameDocumentNavigationType?, tab: Tab) {
        currentURL = url
        guard shouldCapture(url: url, tab: tab) else { return }
        guard type == .anchorNavigation || type == .sessionStatePush else { return }
        addVisit(url: url, tab: tab)
    }

    func updateTitle(_ title: String, tab: Tab) {
        let url = currentURL ?? tab.existingWebView?.url ?? tab.url
        let profile = tab.resolveProfile()
        tab.historyRecordingRuntime.updateTitleIfNeeded(
            title,
            url,
            profile?.id ?? tab.historyRecordingRuntime.currentProfileId(),
            profile?.isEphemeral ?? tab.isEphemeral
        )
    }

    private func addVisit(url: URL, tab: Tab) {
        let profile = tab.resolveProfile()
        let title = tab.resolvedHistoryTitle(for: url)
        if let visitID = tab.historyRecordingRuntime.addVisit(
            url,
            title,
            Date(),
            tab.id,
            profile?.id ?? tab.historyRecordingRuntime.currentProfileId(),
            profile?.isEphemeral ?? tab.isEphemeral
        ) {
            localVisitIDs.append(visitID)
            if let profile {
                tab.visitedLinkStore.recordVisitedLink(
                    url,
                    for: profile,
                    sourceConfiguration: tab.existingWebView?.configuration
                )
            }
        }
        visitState = .added
    }

    private func shouldCapture(url: URL, tab: Tab) -> Bool {
        guard !tab.isEphemeral else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }
}
