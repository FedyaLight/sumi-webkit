import Foundation

public enum SumiNavigationActionPolicy: Equatable, Sendable, CaseIterable {
    case allow
    case cancel
    case download
}

extension SumiNavigationActionPolicy? {
    public static let next = SumiNavigationActionPolicy?.none
}

public enum SumiNavigationResponsePolicy: String, Equatable, Sendable, CaseIterable {
    case allow
    case cancel
    case download
}

extension SumiNavigationResponsePolicy? {
    public static let next = SumiNavigationResponsePolicy?.none
}

public enum SumiAuthChallengeDisposition {
    case credential(URLCredential)
    case cancel
    case rejectProtectionSpace
}

extension SumiAuthChallengeDisposition? {
    public static let next = SumiAuthChallengeDisposition?.none
}

public enum SumiSameDocumentNavigationType: Int, Equatable, Sendable, CaseIterable {
    case anchorNavigation = 0
    case sessionStatePush
    case sessionStateReplace
    case sessionStatePop
}

public struct SumiCustomNavigationType: RawRepresentable, Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SumiCustomNavigationType {
    public static let userEnteredURL = SumiCustomNavigationType(rawValue: "userEnteredUrl")
    public static let userRequestedPageDownload = SumiCustomNavigationType(rawValue: "userRequestedPageDownload")
}
