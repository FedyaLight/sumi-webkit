import AppKit
import Foundation
import SumiDomain
import WebKit

struct SumiNavigationAction: Equatable {
    let request: URLRequest
    let url: URL?
    let sourceURL: URL?
    let sourceFrame: SumiNavigationFrameInfo?
    let targetFrame: SumiNavigationFrameInfo?
    let isTargetingNewWindow: Bool
    let isForMainFrame: Bool
    let isUserInitiated: Bool
    let navigationType: SumiNavigationType
    let navigationTypeDescription: String
    let redirectHistory: SumiNavigationRedirectHistory
    let mainFrameNavigation: SumiNavigationMainFrameNavigation?
    let modifierFlags: NSEvent.ModifierFlags
    let shouldDownload: Bool
    let isUserEnteredURL: Bool
    let isCustom: Bool

    var redirectInitialAction: SumiNavigationRedirectAction? {
        redirectHistory.first
            ?? mainFrameNavigation?.redirectHistory.first
            ?? mainFrameNavigation?.navigationAction
    }
}

extension SumiNavigationType {
    init(_ navigationType: WKNavigationType) {
        switch navigationType {
        case .linkActivated:
            self = .linkActivated(isMiddleClick: false)
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .other
        }
    }
}

extension SumiNavigationAction {
    @MainActor
    init(webKitNavigationAction navigationAction: WKNavigationAction) {
        let sourceFrame = navigationAction.sumiWebKitSafeSourceFrame.map(SumiNavigationFrameInfo.init(webKitFrame:))
        let targetFrame = navigationAction.targetFrame.map(SumiNavigationFrameInfo.init(webKitFrame:))
        self.init(
            request: navigationAction.request,
            url: navigationAction.request.url,
            sourceURL: sourceFrame?.url,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            isTargetingNewWindow: navigationAction.targetFrame == nil,
            isForMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            isUserInitiated: navigationAction.isUserInitiated == true,
            navigationType: SumiNavigationType(navigationAction.navigationType),
            navigationTypeDescription: "\(navigationAction.navigationType.rawValue)",
            redirectHistory: SumiNavigationRedirectHistory(),
            mainFrameNavigation: nil,
            modifierFlags: navigationAction.modifierFlags,
            shouldDownload: navigationAction.shouldDownload,
            isUserEnteredURL: false,
            isCustom: false
        )
    }
}
