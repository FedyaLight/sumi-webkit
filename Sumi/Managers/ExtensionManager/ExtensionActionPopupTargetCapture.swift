import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPopupPresentationTarget {
    enum Source {
        case browserClick(
            BrowserWindowState,
            Tab,
            profileAssignmentRevision: UInt64,
            documentProof: TabCommittedDocumentAuthorityProof
        )
        case associatedTab(
            BrowserWindowState,
            ExtensionTabAdapter,
            ExtensionTabCurrentPublication,
            WKWebExtensionContext
        )
        case presentationOnly(BrowserWindowState)
    }

    let extensionID: String
    let profileID: UUID
    let windowID: UUID
    let anchor: ExtensionActionPopupAnchor?
    let source: Source
}

/// Snapshots one immutable presentation window before popup work yields. A
/// later continuation may revalidate that target, but never adopt a newer
/// active window or click anchor.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupTargetCapture {
    private let anchors: ExtensionActionPopupAnchorStore
    private let browser: any ExtensionActionPopupBrowserProjection

    init(
        anchors: ExtensionActionPopupAnchorStore,
        browser: any ExtensionActionPopupBrowserProjection
    ) {
        self.anchors = anchors
        self.browser = browser
    }

    func capture(
        action: WKWebExtension.Action,
        evidence: ExtensionActionPopupCallbackEvidence
    ) -> ExtensionActionPopupPresentationTarget? {
        if let invocation = evidence.invocation {
            let target = invocation.target
            guard let anchor = anchors.claimAnchor(
                      sessionToken: target.anchorSessionToken,
                      extensionID: evidence.extensionID
                  ),
                  anchor.profileID == evidence.profileID,
                  anchor.windowID == target.windowID,
                  let windowState = anchor.windowState,
                  browser.popupWindowState(id: target.windowID)
                      === windowState,
                  browser.popupWindow(windowState, matches: evidence.profileID),
                  exactTab(in: anchor, windowState: windowState)
            else { return nil }
            let source: ExtensionActionPopupPresentationTarget.Source
            if let tab = anchor.tab {
                guard let profileAssignmentRevision =
                        anchor.tabProfileAssignmentRevision,
                      let documentProof = anchor.tabDocumentProof
                else { return nil }
                source = .browserClick(
                    windowState,
                    tab,
                    profileAssignmentRevision: profileAssignmentRevision,
                    documentProof: documentProof
                )
            } else {
                source = .presentationOnly(windowState)
            }
            return .init(
                extensionID: evidence.extensionID,
                profileID: evidence.profileID,
                windowID: target.windowID,
                anchor: anchor,
                source: source
            )
        }

        if let associatedTab = action.associatedTab {
            guard let adapter = associatedTab as? ExtensionTabAdapter,
                  let publication = adapter.evidence.currentPublication(
                      visibleTo: evidence.context
                  ),
                  publication.contextIdentity.extensionID
                      == evidence.extensionID,
                  publication.contextIdentity.profileID == evidence.profileID,
                  let window = browser.popupWindow(containing: publication.tab),
                  browser.popupTab(id: publication.tab.id, in: window)
                      === publication.tab,
                  browser.popupCurrentTab(in: window)
                      === publication.tab,
                  browser.popupWindow(window, matches: evidence.profileID)
            else { return nil }
            return .init(
                extensionID: evidence.extensionID,
                profileID: evidence.profileID,
                windowID: window.id,
                anchor: nil,
                source: .associatedTab(
                    window,
                    adapter,
                    publication,
                    evidence.context
                )
            )
        }

        guard let window = browser.popupActiveWindow(),
              browser.popupWindow(window, matches: evidence.profileID)
        else {
            return nil
        }
        return .init(
            extensionID: evidence.extensionID,
            profileID: evidence.profileID,
            windowID: window.id,
            anchor: nil,
            source: .presentationOnly(window)
        )
    }

    func isCurrent(_ target: ExtensionActionPopupPresentationTarget) -> Bool {
        guard browser.popupWindowState(id: target.windowID)
                  === target.source.windowState,
              browser.popupWindow(
                  target.source.windowState,
                  matches: target.profileID
              )
        else { return false }
        switch target.source {
        case .browserClick(
            let windowState,
            let tab,
            let profileAssignmentRevision,
            let documentProof
        ):
            return browser.popupTab(id: tab.id, in: windowState) === tab
                && browser.popupCurrentTab(in: windowState) === tab
                && tab.profileAssignment.changeRevision
                    == profileAssignmentRevision
                && tab.committedDocumentRuntime.authorityProof == documentProof
        case .associatedTab(
            let windowState,
            let adapter,
            let publication,
            let context
        ):
            guard browser.popupTab(
                      id: publication.tab.id,
                      in: windowState
                  ) === publication.tab,
                  browser.popupCurrentTab(in: windowState)
                      === publication.tab,
                  adapter.evidence.isCurrent(
                      publication,
                      visibleTo: context
                  )
            else { return false }
            return true
        case .presentationOnly:
            return true
        }
    }

    private func exactTab(
        in anchor: ExtensionActionPopupAnchor,
        windowState: BrowserWindowState
    ) -> Bool {
        guard let tabID = anchor.tabID else {
            return anchor.tab == nil
        }
        guard let tab = anchor.tab,
              browser.popupTab(id: tabID, in: windowState) === tab,
              browser.popupCurrentTab(in: windowState) === tab,
              tab.profileAssignment.changeRevision
                  == anchor.tabProfileAssignmentRevision,
              tab.committedDocumentRuntime.authorityProof
                  == anchor.tabDocumentProof
        else { return false }
        return true
    }
}

@available(macOS 15.5, *)
extension ExtensionActionPopupPresentationTarget.Source {
    var windowState: BrowserWindowState {
        switch self {
        case .browserClick(let windowState, _, _, _),
             .associatedTab(let windowState, _, _, _),
             .presentationOnly(let windowState):
            return windowState
        }
    }

    var exactTab: Tab? {
        switch self {
        case .browserClick(_, let tab, _, _):
            return tab
        case .associatedTab(_, _, let publication, _):
            return publication.tab
        case .presentationOnly:
            return nil
        }
    }
}
