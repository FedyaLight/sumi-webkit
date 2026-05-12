import Foundation
import Navigation

enum SumiNavigationActionPolicy: Equatable, Sendable, CaseIterable {
    case allow
    case cancel
    case download
}

extension SumiNavigationActionPolicy? {
    static let next = SumiNavigationActionPolicy?.none
}

enum SumiNavigationResponsePolicy: String, Equatable, Sendable, CaseIterable {
    case allow
    case cancel
    case download
}

extension SumiNavigationResponsePolicy? {
    static let next = SumiNavigationResponsePolicy?.none
}

enum SumiAuthChallengeDisposition {
    case credential(URLCredential)
    case cancel
    case rejectProtectionSpace
}

extension SumiAuthChallengeDisposition? {
    static let next = SumiAuthChallengeDisposition?.none
}

enum SumiSameDocumentNavigationType: Int, Equatable, Sendable, CaseIterable {
    case anchorNavigation = 0
    case sessionStatePush
    case sessionStateReplace
    case sessionStatePop
}

struct SumiCustomNavigationType: RawRepresentable, Equatable, Hashable, Sendable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SumiCustomNavigationType {
    static let userEnteredURL = SumiCustomNavigationType(rawValue: "userEnteredUrl")
    static let userRequestedPageDownload = SumiCustomNavigationType(rawValue: "userRequestedPageDownload")
}

extension CustomNavigationType {
    static var sumiUserEnteredURL: CustomNavigationType {
        SumiCustomNavigationType.userEnteredURL.navigationCustomNavigationType
    }
}

extension SumiNavigationActionPolicy {
    init(_ policy: NavigationActionPolicy) {
        switch policy {
        case .allow:
            self = .allow
        case .cancel:
            self = .cancel
        case .download:
            self = .download
        }
    }

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
    init(_ policy: NavigationResponsePolicy) {
        switch policy {
        case .allow:
            self = .allow
        case .cancel:
            self = .cancel
        case .download:
            self = .download
        }
    }

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
