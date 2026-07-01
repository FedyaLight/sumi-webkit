import AppKit
import Foundation
import WebKit

enum SumiNavigationType: Equatable, CustomDebugStringConvertible {
    case linkActivated(isMiddleClick: Bool)
    case formSubmitted
    case formResubmitted
    case backForward
    case reload
    case redirect(String)
    case sessionRestoration
    case alternateHtmlLoad
    case sameDocumentNavigation
    case other
    case custom(SumiCustomNavigationType)

    var isLinkActivated: Bool {
        if case .linkActivated = self { return true }
        return false
    }

    var isMiddleButtonClick: Bool {
        if case .linkActivated(let isMiddleClick) = self { return isMiddleClick }
        return false
    }

    var isRedirect: Bool {
        if case .redirect = self { return true }
        return false
    }

    var isBackForward: Bool {
        if case .backForward = self { return true }
        return false
    }

    var debugDescription: String {
        switch self {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .formResubmitted:
            return "formResubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .redirect(let description):
            return description
        case .sessionRestoration:
            return "sessionRestoration"
        case .alternateHtmlLoad:
            return "alternateHtmlLoad"
        case .sameDocumentNavigation:
            return "sameDocumentNavigation"
        case .other:
            return "other"
        case .custom(let navigationType):
            return "custom(\(navigationType.rawValue))"
        }
    }
}

struct SumiNavigationRedirectAction: Equatable {
    let request: URLRequest
    let url: URL?
    let navigationType: SumiNavigationType
    let isUserInitiated: Bool
    let isUserEnteredURL: Bool

    var isUserActivated: Bool {
        isUserInitiated || navigationType.isLinkActivated || isUserEnteredURL
    }
}

struct SumiNavigationRedirectHistory: Equatable {
    let actions: [SumiNavigationRedirectAction]

    init(_ actions: [SumiNavigationRedirectAction] = []) {
        self.actions = actions
    }

    var isEmpty: Bool {
        actions.isEmpty
    }

    var first: SumiNavigationRedirectAction? {
        actions.first
    }

    var last: SumiNavigationRedirectAction? {
        actions.last
    }
}

struct SumiNavigationMainFrameNavigation: Equatable {
    let navigationAction: SumiNavigationRedirectAction
    let redirectHistory: SumiNavigationRedirectHistory
}

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
