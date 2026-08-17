import Foundation
import WebKit

enum PagePresentation: Equatable {
    case empty
    case browserSurface(pageID: UUID)
    case certificateTrustWarning(pageID: UUID, host: String)
    case dataClearing(pageID: UUID, destination: URL)
    case loading(pageID: UUID, destination: URL)
    case live(pageID: UUID)
    case preparationFailure(pageID: UUID, destination: URL)
    case restoreFailure(pageID: UUID, destination: URL?)
    case recoveryFailure(
        pageID: UUID,
        destination: URL,
        nativeSnapshotAvailable: Bool
    )
    case integrityFailure(pageID: UUID)

    var hasLiveWebContentResidence: Bool {
        if case .live = self {
            return true
        }
        return false
    }
}

@MainActor
enum PagePresentationResolver {
    static func resolve(
        tab: Tab?,
        windowState: BrowserWindowState,
        webView: WKWebView?
    ) -> PagePresentation {
        guard let tab else { return .empty }
        if tab.isRestoreFailure {
            return .restoreFailure(
                pageID: tab.id,
                destination: tab.restoreFailureDestination
            )
        }
        if tab.representsSumiEmptySurface {
            return .empty
        }
        guard tab.requiresPrimaryWebView else {
            return .browserSurface(pageID: tab.id)
        }
        if let session = tab.certificateTrustWarningSession {
            return .certificateTrustWarning(
                pageID: tab.id,
                host: session.host
            )
        }
        if let mutation = tab.websiteDataMutationPresentation {
            return .dataClearing(
                pageID: tab.id,
                destination: mutation.destination
            )
        }
        if let webView,
           let recovery = tab.webContentRecoveryMarkers.recoveryState(
               on: webView
           ) {
            if recovery.isFailure {
                return .recoveryFailure(
                    pageID: tab.id,
                    destination: recovery.destination,
                    nativeSnapshotAvailable: recovery.snapshot != nil
                )
            }
            return .loading(
                pageID: tab.id,
                destination: recovery.destination
            )
        }
        if let webView,
           tab.committedDocumentRuntime.hasCommittedDocument(on: webView) {
            return .live(pageID: tab.id)
        }
        if let request = windowState.pageMaterializationRequests.currentRequest(
            for: tab.id,
            in: windowState.id
        ),
           request.residenceGeneration == tab.webViewSession.generation {
            return .loading(pageID: tab.id, destination: request.destination)
        }
        if tab.isLoading {
            return .loading(
                pageID: tab.id,
                destination: tab.mainFrameLoads.currentIntent.targetURL
            )
        }
        return .preparationFailure(pageID: tab.id, destination: tab.url)
    }
}

struct WebsiteDisplayState: Equatable {
    let splitPresentation: WindowSplitPresentation?
    let currentId: UUID?
    let compositorVersion: Int
    let currentPagePresentation: PagePresentation
    let pagePresentationsByID: [UUID: PagePresentation]
    let isSplitDropCaptureActive: Bool

    init(
        splitPresentation: WindowSplitPresentation?,
        currentId: UUID?,
        compositorVersion: Int,
        currentPagePresentation: PagePresentation,
        pagePresentationsByID: [UUID: PagePresentation] = [:],
        isSplitDropCaptureActive: Bool
    ) {
        self.splitPresentation = splitPresentation
        self.currentId = currentId
        self.compositorVersion = compositorVersion
        self.currentPagePresentation = currentPagePresentation
        var presentations = pagePresentationsByID
        if let currentId {
            presentations[currentId] = currentPagePresentation
        }
        self.pagePresentationsByID = presentations
        self.isSplitDropCaptureActive = isSplitDropCaptureActive
    }

    func presentation(for pageID: UUID) -> PagePresentation {
        pagePresentationsByID[pageID] ?? .integrityFailure(pageID: pageID)
    }

    var activeSplitPresentation: WindowSplitPresentation? {
        guard let splitPresentation,
              let currentId,
              splitPresentation.activeTabID == currentId
        else {
            return nil
        }
        return splitPresentation
    }

    var visibleTabIDs: Set<UUID> {
        if let activeSplitPresentation {
            return Set(activeSplitPresentation.visibleTabIDs)
        }
        return currentId.map { Set([$0]) } ?? []
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitPresentation == rhs.splitPresentation
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentPagePresentation == rhs.currentPagePresentation
            && lhs.pagePresentationsByID == rhs.pagePresentationsByID
            && lhs.isSplitDropCaptureActive == rhs.isSplitDropCaptureActive
    }
}
