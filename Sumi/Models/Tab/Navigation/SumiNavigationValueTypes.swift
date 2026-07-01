import Foundation

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
