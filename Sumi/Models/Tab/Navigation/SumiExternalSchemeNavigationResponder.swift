import AppKit
import Foundation
import Navigation
import WebKit

@MainActor
protocol SumiWorkspaceOpening: AnyObject {
    func urlForApplication(toOpen url: URL) -> URL?
    func open(_ url: URL)
}

@MainActor
final class SumiNSWorkspaceOpening: SumiWorkspaceOpening {
    static let shared = SumiNSWorkspaceOpening()

    func urlForApplication(toOpen url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SumiExternalSchemeNavigationResponder: NavigationResponder {
    private weak var tab: Tab?
    private let workspace: SumiWorkspaceOpening
    private var shouldCloseTabOnExternalAppOpen = true

    init(tab: Tab, workspace: SumiWorkspaceOpening? = nil) {
        self.tab = tab
        self.workspace = workspace ?? SumiNSWorkspaceOpening.shared
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        let externalURL = navigationAction.url
        guard externalURL.sumiIsExternalSchemeLink, externalURL.scheme != nil else {
            if navigationAction.isForMainFrame,
               navigationAction.redirectHistory?.isEmpty == false {
                shouldCloseTabOnExternalAppOpen = false
            }
            return .next
        }

        if let mainFrameNavigationAction = navigationAction.mainFrameNavigation?.navigationAction,
           (mainFrameNavigationAction.redirectHistory?.first ?? mainFrameNavigationAction).sumiIsUserEnteredURL {
            shouldCloseTabOnExternalAppOpen = false
        }

        defer {
            if navigationAction.isForMainFrame {
                shouldCloseTabOnExternalAppOpen = false
            }
        }

        let initialRequest = navigationAction.mainFrameNavigation?.navigationAction.redirectHistory?.first?.request
            ?? navigationAction.mainFrameNavigation?.navigationAction.request
            ?? navigationAction.request
        if [.returnCacheDataElseLoad, .returnCacheDataDontLoad].contains(initialRequest.cachePolicy) {
            return .cancel
        }

        guard workspace.urlForApplication(toOpen: externalURL) != nil else {
            return .cancel
        }

        navigationAction.targetFrame?.webView?.window?.makeFirstResponder(nil)
        workspace.open(externalURL)

        if shouldCloseTabOnExternalAppOpen,
           let webView = navigationAction.targetFrame?.webView {
            webView.sumiCloseWindow()
        }

        return .cancel
    }

    func navigationDidFinish(_: Navigation) {
        shouldCloseTabOnExternalAppOpen = false
    }

    func navigation(_: Navigation, didFailWith error: WKError) {
        shouldCloseTabOnExternalAppOpen = false
    }
}
