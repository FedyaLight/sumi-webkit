import AppKit
import Foundation
import Navigation
import WebKit

enum SumiPopupPermissionPath: String, Codable, Equatable, Sendable {
    case uiDelegateCreateWebView
    case navigationResponderTargetFrame
}

enum SumiPopupClassification: String, Codable, Equatable, Sendable {
    case directUserActivated
    case shortWindowUserActivated
    case scriptOrBackground
    case emptyOrAboutBlank
    case internalOrBrowserOwned
}

enum SumiPopupUserActivationState: Equatable, Sendable {
    case directWebKit
    case navigationAction
    case recentBrowserEvent(kind: String, eventTimestamp: TimeInterval, currentTime: TimeInterval)
    case none
    case unknown

    var isUserActivated: Bool {
        switch self {
        case .directWebKit, .navigationAction, .recentBrowserEvent:
            return true
        case .none, .unknown:
            return false
        }
    }

    var metadataValue: String {
        switch self {
        case .directWebKit:
            return "direct-webkit"
        case .navigationAction:
            return "navigation-action"
        case .recentBrowserEvent(let kind, let eventTimestamp, let currentTime):
            return "recent-browser-event:\(kind):\(eventTimestamp):\(currentTime)"
        case .none:
            return "none"
        case .unknown:
            return "unknown"
        }
    }
}

@MainActor
final class SumiPopupUserActivationTracker {
    struct RecordedActivation {
        let kind: String
        let timestamp: TimeInterval
    }

    private let threshold: TimeInterval
    private let currentTime: () -> TimeInterval
    private var lastActivation: RecordedActivation?

    init(
        threshold: TimeInterval = 6,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        if let override = ProcessInfo.processInfo.environment["POPUP_TIMEOUT_OVERRIDE"],
           let overrideValue = TimeInterval(override),
           overrideValue > 0 {
            self.threshold = overrideValue
        } else {
            self.threshold = threshold
        }
        self.currentTime = currentTime
    }

    func record(event: NSEvent, kind: String) {
        lastActivation = RecordedActivation(
            kind: kind,
            timestamp: event.timestamp
        )
    }

    func activationState(
        webKitUserInitiated: Bool?,
        navigationActionUserInitiated: Bool? = nil
    ) -> SumiPopupUserActivationState {
        if webKitUserInitiated == true {
            return .directWebKit
        }
        if navigationActionUserInitiated == true {
            return .navigationAction
        }
        guard let lastActivation else {
            return webKitUserInitiated == nil && navigationActionUserInitiated == nil ? .unknown : .none
        }
        let now = currentTime()
        if (0...threshold).contains(now - lastActivation.timestamp) {
            return .recentBrowserEvent(
                kind: lastActivation.kind,
                eventTimestamp: lastActivation.timestamp,
                currentTime: now
            )
        }
        return .none
    }

    func consumeIfUserActivated(_ activationState: SumiPopupUserActivationState) {
        guard activationState.isUserActivated else { return }
        lastActivation = nil
    }
}

struct SumiPopupPermissionTabContext: Sendable {
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
        displayDomain: String? = nil
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
    }
}

struct SumiPopupPermissionRequest: Sendable {
    let id: String
    let targetURL: URL?
    let sourceURL: URL?
    let requestingOrigin: SumiPermissionOrigin
    let userActivation: SumiPopupUserActivationState
    let classification: SumiPopupClassification
    let isMainFrame: Bool
    let navigationActionMetadata: [String: String]

    init(
        id: String = UUID().uuidString,
        targetURL: URL?,
        sourceURL: URL?,
        requestingOrigin: SumiPermissionOrigin,
        userActivation: SumiPopupUserActivationState,
        classification: SumiPopupClassification? = nil,
        isMainFrame: Bool,
        navigationActionMetadata: [String: String] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.targetURL = targetURL
        self.sourceURL = sourceURL
        self.requestingOrigin = requestingOrigin
        self.userActivation = userActivation
        self.classification = classification ?? Self.classify(
            targetURL: targetURL,
            sourceURL: sourceURL,
            userActivation: userActivation
        )
        self.isMainFrame = isMainFrame
        self.navigationActionMetadata = navigationActionMetadata
    }

    var isUserActivated: Bool {
        userActivation.isUserActivated
    }

    var isExtensionOwnedPopup: Bool {
        Self.isExtensionScheme(sourceURL) || Self.isExtensionScheme(targetURL)
            || navigationActionMetadata["isExtensionOriginated"] == "true"
    }

    var involvesSumiInternalScheme: Bool {
        sourceURL?.scheme?.lowercased() == "sumi"
            || targetURL?.scheme?.lowercased() == "sumi"
    }

    static func classify(
        targetURL: URL?,
        sourceURL: URL?,
        userActivation: SumiPopupUserActivationState
    ) -> SumiPopupClassification {
        if isBrowserOwned(sourceURL) || isBrowserOwned(targetURL) {
            return .internalOrBrowserOwned
        }
        guard let targetURL, !targetURL.sumiIsEmpty else {
            return .emptyOrAboutBlank
        }
        if targetURL.sumiNavigationalScheme == .about {
            return .emptyOrAboutBlank
        }
        switch userActivation {
        case .recentBrowserEvent:
            return .shortWindowUserActivated
        case .directWebKit, .navigationAction:
            return .directUserActivated
        case .none, .unknown:
            return .scriptOrBackground
        }
    }

    @MainActor
    static func fromWKNavigationAction(
        _ navigationAction: WKNavigationAction,
        path: SumiPopupPermissionPath,
        activationState: SumiPopupUserActivationState,
        isExtensionOriginated: Bool
    ) -> SumiPopupPermissionRequest {
        let sourceFrame = navigationAction.safeSourceFrame
        let targetURL = navigationAction.request.url
        let sourceURL = sourceFrame?.safeRequest?.url
        let requestingOrigin = sourceFrame.map { permissionOrigin(from: $0.securityOrigin) }
            ?? SumiPermissionOrigin(url: sourceURL)
        var metadata: [String: String] = [
            "path": path.rawValue,
            "navigationType": "\(navigationAction.navigationType.rawValue)",
            "activation": activationState.metadataValue,
            "isExtensionOriginated": String(isExtensionOriginated),
        ]
        if let targetFrame = navigationAction.targetFrame {
            metadata["targetFrameIsMainFrame"] = String(targetFrame.isMainFrame)
        } else {
            metadata["targetFrameIsMainFrame"] = "nil"
        }
        if let targetURL {
            metadata["targetURLScheme"] = targetURL.scheme?.lowercased() ?? ""
        }

        return SumiPopupPermissionRequest(
            targetURL: targetURL,
            sourceURL: sourceURL,
            requestingOrigin: requestingOrigin,
            userActivation: activationState,
            classification: isExtensionOriginated ? .internalOrBrowserOwned : nil,
            isMainFrame: sourceFrame?.isMainFrame ?? true,
            navigationActionMetadata: metadata
        )
    }

    static func fromNavigationAction(
        _ navigationAction: NavigationAction,
        activationState: SumiPopupUserActivationState
    ) -> SumiPopupPermissionRequest {
        var metadata: [String: String] = [
            "path": SumiPopupPermissionPath.navigationResponderTargetFrame.rawValue,
            "navigationType": navigationAction.navigationType.debugDescription,
            "activation": activationState.metadataValue,
            "isTargetingNewWindow": String(navigationAction.isTargetingNewWindow),
            "isForMainFrame": String(navigationAction.isForMainFrame),
        ]
        metadata["modifierFlags"] = "\(navigationAction.modifierFlags.rawValue)"
        return SumiPopupPermissionRequest(
            targetURL: navigationAction.url,
            sourceURL: navigationAction.sourceFrame.url,
            requestingOrigin: permissionOrigin(from: SumiSecurityOrigin(navigationFrame: navigationAction.sourceFrame)),
            userActivation: activationState,
            isMainFrame: navigationAction.sourceFrame.isMainFrame,
            navigationActionMetadata: metadata
        )
    }

    @MainActor
    private static func permissionOrigin(from origin: WKSecurityOrigin) -> SumiPermissionOrigin {
        SumiSecurityOrigin(
            protocol: origin.`protocol`,
            host: origin.host,
            port: origin.port
        ).permissionOrigin(missingReason: "missing-webkit-popup-security-origin")
    }

    private static func permissionOrigin(from origin: SumiSecurityOrigin) -> SumiPermissionOrigin {
        origin.permissionOrigin(missingReason: "missing-navigation-popup-security-origin")
    }

    private static func isBrowserOwned(_ url: URL?) -> Bool {
        let scheme = url?.scheme?.lowercased()
        return scheme == "sumi" || scheme == "webkit-extension" || scheme == "safari-web-extension"
    }

    private static func isExtensionScheme(_ url: URL?) -> Bool {
        let scheme = url?.scheme?.lowercased()
        return scheme == "webkit-extension" || scheme == "safari-web-extension"
    }
}
