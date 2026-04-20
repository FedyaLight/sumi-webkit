import Combine
import Foundation
import ObjectiveC.runtime
import WebKit

enum TabTitleUpdateSource {
    case manual
}

enum TabMainFrameNavigationKind {
    case load
    case backForward
}

struct TabBackForwardNavigationContext {
    let originURL: URL?
    let originHistoryURL: URL?
    let originHistoryItem: WKBackForwardListItem?
}

enum BackForwardNavigationSettleDecision {
    static func shouldApplyDeferredActions(
        originURL: URL?,
        originHistoryURL: URL?,
        originHistoryItem: WKBackForwardListItem?,
        currentURL: URL?,
        currentHistoryURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        if let originHistoryItem,
           let currentHistoryItem,
           originHistoryItem === currentHistoryItem
        {
            return false
        }

        let resolvedOrigin = originHistoryURL ?? originURL
        let resolvedCurrent = currentHistoryURL ?? currentURL

        guard let resolvedCurrent else { return false }
        guard resolvedCurrent != resolvedOrigin else { return false }
        return true
    }
}

extension URL {
    var sumiSuggestedTitlePlaceholder: String? {
        if isFileURL {
            return lastPathComponent.isEmpty ? nil : lastPathComponent
        }

        let host = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (host?.isEmpty == false) ? host : nil
    }
}

extension WKBackForwardListItem {
    // Mirrors DDG's workaround for stale WebKit history titles.
    private static let tabTitleKey = UnsafeRawPointer(bitPattern: "tabTitleKey".hashValue)!

    var tabTitle: String? {
        get {
            objc_getAssociatedObject(self, Self.tabTitleKey) as? String
        }
        set {
            objc_setAssociatedObject(self, Self.tabTitleKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

@MainActor
final class TabNavigationRuntime {
    var loadingState: Tab.LoadingState = .idle
    var restoredCanGoBack: Bool?
    var restoredCanGoForward: Bool?
    var pendingMainFrameNavigationTask: Task<Void, Never>?
    var pendingMainFrameNavigationToken: UUID?
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind?
    var pendingBackForwardNavigationContext: TabBackForwardNavigationContext?
    var pendingBackForwardSettleTask: Task<Void, Never>?
    var isFreezingNavigationStateDuringBackForwardGesture = false
    let observedWebViews = NSHashTable<AnyObject>.weakObjects()
    var titleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
}

@MainActor
final class TabMediaRuntime {
    var lastMediaActivityAt: Date = .distantPast
    var audioStateCancellables: [ObjectIdentifier: AnyCancellable] = [:]
}

@MainActor
final class TabExtensionRuntimeState {
    var controllerGeneration: UInt64 = 0
    var documentSequence: UInt64 = 0
    var committedMainDocumentURL: URL?
    var lastReportedURL: URL?
    var lastReportedLoadingComplete: Bool?
    var lastReportedTitle: String?
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
}

@MainActor
final class TabWebViewRuntime {
    var webView: WKWebView?
    var existingWebView: WKWebView?
    var webViewConfigurationOverride: WKWebViewConfiguration?
    var pendingContextMenuCapture: WebContextMenuCapture?
    var primaryWindowId: UUID?
    var profileAwaitCancellable: AnyCancellable?
    let extensionRuntimeState = TabExtensionRuntimeState()
    let findInPage = FindInPageTabExtension()
}
