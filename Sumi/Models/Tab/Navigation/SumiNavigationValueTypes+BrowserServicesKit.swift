import Foundation
import Navigation
import WebKit

extension CustomNavigationType {
    static var sumiUserEnteredURL: CustomNavigationType {
        SumiCustomNavigationType.userEnteredURL.navigationCustomNavigationType
    }
}

extension SumiNavigationActionPolicy {
    var navigationActionPolicy: NavigationActionPolicy {
        switch self {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .download:
            return .download
        }
    }
}

extension SumiNavigationResponsePolicy {
    var navigationResponsePolicy: NavigationResponsePolicy {
        switch self {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .download:
            return .download
        }
    }
}

extension SumiNavigationResponse {
    @MainActor
    init(_ navigationResponse: NavigationResponse) {
        self.init(
            url: navigationResponse.url,
            isForMainFrame: navigationResponse.isForMainFrame,
            canShowMIMEType: navigationResponse.canShowMIMEType,
            shouldDownload: navigationResponse.shouldDownload,
            httpResponse: navigationResponse.httpResponse,
            mimeType: navigationResponse.response.mimeType,
            mainFrameNavigation: navigationResponse.mainFrameNavigation.map(SumiNavigationMainFrameNavigation.init)
        )
    }
}

extension SumiAuthChallengeDisposition {
    var navigationAuthChallengeDisposition: AuthChallengeDisposition {
        switch self {
        case .credential(let credential):
            return .credential(credential)
        case .cancel:
            return .cancel
        case .rejectProtectionSpace:
            return .rejectProtectionSpace
        }
    }
}

extension SumiSameDocumentNavigationType {
    init(_ navigationType: WKSameDocumentNavigationType) {
        self = Self(rawValue: navigationType.rawValue) ?? .anchorNavigation
    }
}

extension WKSameDocumentNavigationType {
    var sumiSameDocumentNavigationType: SumiSameDocumentNavigationType {
        SumiSameDocumentNavigationType(self)
    }
}

extension SumiCustomNavigationType {
    init(_ navigationType: CustomNavigationType) {
        self.init(rawValue: navigationType.rawValue)
    }

    var navigationCustomNavigationType: CustomNavigationType {
        CustomNavigationType(rawValue: rawValue)
    }
}
