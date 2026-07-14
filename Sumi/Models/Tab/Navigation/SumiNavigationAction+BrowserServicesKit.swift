import AppKit
import Navigation
import WebKit
import SumiDomain

extension SumiNavigationType {
    init(_ navigationType: NavigationType) {
        switch navigationType {
        case .linkActivated(let isMiddleClick):
            self = .linkActivated(isMiddleClick: isMiddleClick)
        case .formSubmitted:
            self = .formSubmitted
        case .formResubmitted:
            self = .formResubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .redirect:
            self = .redirect(navigationType.debugDescription)
        case .sessionRestoration:
            self = .sessionRestoration
        case .alternateHtmlLoad:
            self = .alternateHtmlLoad
        case .sameDocumentNavigation:
            self = .sameDocumentNavigation
        case .other:
            self = .other
        case .custom(let customType):
            self = .custom(SumiCustomNavigationType(customType))
        }
    }
}

extension NavigationAction {
    var sumiIsUserEnteredURL: Bool {
        if case .other = navigationType,
           case .user = request.attribution {
            return true
        } else if case .custom(.sumiUserEnteredURL) = navigationType {
            return true
        }
        return false
    }

    var sumiIsCustom: Bool {
        if case .custom = navigationType {
            return true
        }
        return false
    }

    /// `FrameInfo.webView` is weak and may disappear while the Navigation
    /// package is awaiting an async responder. Its public
    /// `isTargetingNewWindow` accessor asserts when both frame WebViews have
    /// already been released. Preserve the release-build policy without
    /// crossing that assertion: missing frame ownership is treated as a new
    /// window and therefore cannot silently gain current-tab authority.
    @MainActor
    var sumiIsTargetingNewWindow: Bool {
        let sourceWebViewID = sourceFrame.webView.map(ObjectIdentifier.init)
        let targetWebViewID = targetFrame?.webView.map(ObjectIdentifier.init)
        return sourceWebViewID != targetWebViewID || targetWebViewID == nil
    }
}

extension SumiNavigationRedirectAction {
    init(_ action: NavigationAction) {
        self.init(
            request: action.request,
            url: action.request.url,
            navigationType: SumiNavigationType(action.navigationType),
            isUserInitiated: action.isUserInitiated,
            isUserEnteredURL: action.sumiIsUserEnteredURL
        )
    }
}

extension SumiNavigationMainFrameNavigation {
    @MainActor
    init(_ navigation: Navigation) {
        self.init(
            navigationAction: SumiNavigationRedirectAction(navigation.navigationAction),
            redirectHistory: SumiNavigationRedirectHistory(
                navigation.redirectHistory.map(SumiNavigationRedirectAction.init)
            )
        )
    }
}

extension SumiNavigationAction {
    @MainActor
    init(_ navigationAction: NavigationAction) {
        let sourceFrame = SumiNavigationFrameInfo(navigationFrame: navigationAction.sourceFrame)
        let targetFrame = navigationAction.targetFrame.map(SumiNavigationFrameInfo.init(navigationFrame:))
        self.init(
            request: navigationAction.request,
            url: navigationAction.request.url,
            sourceURL: sourceFrame.url,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            isTargetingNewWindow: navigationAction.sumiIsTargetingNewWindow,
            isForMainFrame: navigationAction.isForMainFrame,
            isUserInitiated: navigationAction.isUserInitiated == true,
            navigationType: SumiNavigationType(navigationAction.navigationType),
            navigationTypeDescription: navigationAction.navigationType.debugDescription,
            redirectHistory: SumiNavigationRedirectHistory(
                navigationAction.redirectHistory?.map(SumiNavigationRedirectAction.init) ?? []
            ),
            mainFrameNavigation: navigationAction.mainFrameNavigation.map(SumiNavigationMainFrameNavigation.init),
            modifierFlags: navigationAction.modifierFlags,
            shouldDownload: navigationAction.shouldDownload,
            isUserEnteredURL: navigationAction.sumiIsUserEnteredURL,
            isCustom: navigationAction.sumiIsCustom,
            isClientRedirect: navigationAction.navigationType.redirect?.isClient == true
        )
    }
}
