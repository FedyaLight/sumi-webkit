import Foundation
import Navigation

enum SumiExternalSchemeClassification: String, Codable, Equatable, Sendable {
    case directUserActivated
    case scriptOrBackground
    case redirectChainUserActivated
    case redirectChainBackground
    case unknownOrUnsupported
    case internalOrBrowserOwned
}

enum SumiExternalSchemeUserActivationState: Equatable, Sendable {
    case navigationAction
    case userEntered
    case redirectChain
    case none
    case unknown

    var isUserActivated: Bool {
        switch self {
        case .navigationAction, .userEntered, .redirectChain:
            return true
        case .none, .unknown:
            return false
        }
    }

}

struct SumiExternalSchemePermissionTabContext: Sendable {
    let tabId: String
    let pageId: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let committedURL: URL?
    let visibleURL: URL?
    let mainFrameURL: URL?
    let isActiveTab: Bool
    let isVisibleTab: Bool
    let navigationOrPageGeneration: String?
    let displayDomain: String?
    let isCurrentPage: (@MainActor @Sendable () -> Bool)?

    init(
        tabId: String,
        pageId: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        committedURL: URL?,
        visibleURL: URL?,
        mainFrameURL: URL?,
        isActiveTab: Bool,
        isVisibleTab: Bool,
        navigationOrPageGeneration: String?,
        displayDomain: String? = nil,
        isCurrentPage: (@MainActor @Sendable () -> Bool)? = nil
    ) {
        self.tabId = tabId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.pageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.committedURL = committedURL
        self.visibleURL = visibleURL
        self.mainFrameURL = mainFrameURL
        self.isActiveTab = isActiveTab
        self.isVisibleTab = isVisibleTab
        self.navigationOrPageGeneration = navigationOrPageGeneration?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayDomain = displayDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isCurrentPage = isCurrentPage
    }
}

struct SumiExternalSchemePermissionRequest: Sendable {
    let id: String
    let targetURL: URL?
    let requestingOrigin: SumiPermissionOrigin
    let normalizedScheme: String
    let redactedTargetURLString: String?
    let userActivation: SumiExternalSchemeUserActivationState
    let classification: SumiExternalSchemeClassification
    let isMainFrame: Bool

    init(
        id: String = UUID().uuidString,
        targetURL: URL?,
        requestingOrigin: SumiPermissionOrigin,
        userActivation: SumiExternalSchemeUserActivationState,
        classification: SumiExternalSchemeClassification? = nil,
        isMainFrame: Bool,
        isRedirectChain: Bool
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.targetURL = targetURL
        self.requestingOrigin = requestingOrigin
        self.normalizedScheme = Self.normalizedScheme(for: targetURL)
        self.redactedTargetURLString = Self.redactedDisplayString(for: targetURL)
        self.userActivation = userActivation
        self.classification = classification ?? Self.classify(
            targetURL: targetURL,
            userActivation: userActivation,
            isRedirectChain: isRedirectChain
        )
        self.isMainFrame = isMainFrame
    }

    var isUserActivated: Bool {
        userActivation.isUserActivated
    }

    static func classify(
        targetURL: URL?,
        userActivation: SumiExternalSchemeUserActivationState,
        isRedirectChain: Bool
    ) -> SumiExternalSchemeClassification {
        guard let targetURL,
              isValidExternalSchemeURL(targetURL)
        else {
            if targetURL.map(isInternalOrBrowserSchemeURL) == true {
                return .internalOrBrowserOwned
            }
            return .unknownOrUnsupported
        }

        if isInternalOrBrowserSchemeURL(targetURL) {
            return .internalOrBrowserOwned
        }
        if isRedirectChain {
            return userActivation.isUserActivated ? .redirectChainUserActivated : .redirectChainBackground
        }
        return userActivation.isUserActivated ? .directUserActivated : .scriptOrBackground
    }

    @MainActor
    static func fromNavigationAction(
        _ navigationAction: NavigationAction,
        userActivation: SumiExternalSchemeUserActivationState? = nil
    ) -> SumiExternalSchemePermissionRequest {
        let targetURL = navigationAction.url
        let isRedirectChain = navigationAction.redirectHistory?.isEmpty == false
            || navigationAction.mainFrameNavigation?.navigationAction.redirectHistory?.isEmpty == false
            || navigationAction.navigationType.isRedirect
        let resolvedActivation = userActivation ?? userActivationState(from: navigationAction)

        return SumiExternalSchemePermissionRequest(
            targetURL: targetURL,
            requestingOrigin: permissionOrigin(from: SumiSecurityOrigin(navigationAction.sourceFrame.securityOrigin)),
            userActivation: resolvedActivation,
            isMainFrame: navigationAction.sourceFrame.isMainFrame,
            isRedirectChain: isRedirectChain
        )
    }

    @MainActor
    static func userActivationState(
        from navigationAction: NavigationAction
    ) -> SumiExternalSchemeUserActivationState {
        if navigationAction.sumiIsUserEnteredURL {
            return .userEntered
        }
        if navigationAction.isUserInitiated || navigationAction.navigationType.isLinkActivated {
            return .navigationAction
        }
        if let initialRedirectAction = initialRedirectAction(for: navigationAction),
           initialRedirectAction.isUserInitiated
                || initialRedirectAction.navigationType.isLinkActivated
                || initialRedirectAction.sumiIsUserEnteredURL {
            return .redirectChain
        }
        return .none
    }

    static func normalizedScheme(for url: URL?) -> String {
        SumiPermissionType.normalizedExternalScheme(url?.scheme ?? "")
    }

    static func isValidExternalSchemeURL(_ url: URL) -> Bool {
        let scheme = normalizedScheme(for: url)
        guard isValidSchemeName(scheme), !isInternalOrBrowserScheme(scheme) else {
            return false
        }
        return !url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isInternalOrBrowserSchemeURL(_ url: URL) -> Bool {
        isInternalOrBrowserScheme(normalizedScheme(for: url))
    }

    static func isInternalOrBrowserScheme(_ scheme: String) -> Bool {
        [
            "http",
            "https",
            "about",
            "file",
            "blob",
            "data",
            "ftp",
            "javascript",
            "duck",
            "sumi",
            "sumi-internal",
            "webkit-extension",
            "safari-web-extension",
        ].contains(SumiPermissionType.normalizedExternalScheme(scheme))
    }

    static func redactedDisplayString(for url: URL?) -> String? {
        guard let url else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.scheme.map { "\(SumiPermissionType.normalizedExternalScheme($0)):<redacted>" }
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.scheme.map { "\(SumiPermissionType.normalizedExternalScheme($0)):<redacted>" }
    }

    private static func isValidSchemeName(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first,
              CharacterSet.lowercaseLetters.contains(first)
        else {
            return false
        }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "+.-"))
        return scheme.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func permissionOrigin(from origin: SumiSecurityOrigin) -> SumiPermissionOrigin {
        origin.permissionOrigin(missingReason: "missing-navigation-external-scheme-security-origin")
    }

    @MainActor
    private static func initialRedirectAction(for navigationAction: NavigationAction) -> NavigationAction? {
        navigationAction.redirectHistory?.first
            ?? navigationAction.mainFrameNavigation?.navigationAction.redirectHistory?.first
            ?? navigationAction.mainFrameNavigation?.navigationAction
    }
}
