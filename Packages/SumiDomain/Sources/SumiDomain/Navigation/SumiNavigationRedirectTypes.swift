import Foundation

public enum SumiNavigationType: Equatable, CustomDebugStringConvertible, Sendable {
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

    public var isLinkActivated: Bool {
        if case .linkActivated = self { return true }
        return false
    }

    public var isMiddleButtonClick: Bool {
        if case .linkActivated(let isMiddleClick) = self { return isMiddleClick }
        return false
    }

    public var isRedirect: Bool {
        if case .redirect = self { return true }
        return false
    }

    public var isBackForward: Bool {
        if case .backForward = self { return true }
        return false
    }

    public var debugDescription: String {
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

public struct SumiNavigationRedirectAction: Equatable, Sendable {
    public let request: URLRequest
    public let url: URL?
    public let navigationType: SumiNavigationType
    public let isUserInitiated: Bool
    public let isUserEnteredURL: Bool

    public init(
        request: URLRequest,
        url: URL?,
        navigationType: SumiNavigationType,
        isUserInitiated: Bool,
        isUserEnteredURL: Bool
    ) {
        self.request = request
        self.url = url
        self.navigationType = navigationType
        self.isUserInitiated = isUserInitiated
        self.isUserEnteredURL = isUserEnteredURL
    }

    public var isUserActivated: Bool {
        isUserInitiated || navigationType.isLinkActivated || isUserEnteredURL
    }
}

public struct SumiNavigationRedirectHistory: Equatable, Sendable {
    public let actions: [SumiNavigationRedirectAction]

    public init(_ actions: [SumiNavigationRedirectAction] = []) {
        self.actions = actions
    }

    public var isEmpty: Bool {
        actions.isEmpty
    }

    public var first: SumiNavigationRedirectAction? {
        actions.first
    }

    public var last: SumiNavigationRedirectAction? {
        actions.last
    }
}

public struct SumiNavigationMainFrameNavigation: Equatable, Sendable {
    public let navigationAction: SumiNavigationRedirectAction
    public let redirectHistory: SumiNavigationRedirectHistory

    public init(
        navigationAction: SumiNavigationRedirectAction,
        redirectHistory: SumiNavigationRedirectHistory
    ) {
        self.navigationAction = navigationAction
        self.redirectHistory = redirectHistory
    }
}
