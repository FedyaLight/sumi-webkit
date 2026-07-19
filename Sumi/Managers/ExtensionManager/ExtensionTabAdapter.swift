import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let evidence: ExtensionTabCurrentPublicationEvidence
    let projection: ExtensionTabReadProjection
    let commands: ExtensionTabCommandMutation

    var tabId: UUID { evidence.tabID }
    var tab: Tab? { evidence.currentTab }

    init(
        evidence: ExtensionTabCurrentPublicationEvidence,
        projection: ExtensionTabReadProjection,
        commands: ExtensionTabCommandMutation
    ) {
        self.evidence = evidence
        self.projection = projection
        self.commands = commands
        super.init()
        evidence.bind(adapter: self)
    }

    func represents(_ tab: Tab) -> Bool { evidence.represents(tab) }
    func hasExactTabIdentity(_ tab: Tab) -> Bool {
        evidence.hasExactIdentity(tab)
    }
    func canBeReplaced(by tab: Tab) -> Bool { evidence.canBeReplaced(by: tab) }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else { return false }
        return other === self
    }

    override var hash: Int { ObjectIdentifier(self).hashValue }

    func url(for context: WKWebExtensionContext) -> URL? {
        projection.url(for: context)
    }
    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        projection.pendingURL(for: context)
    }
    func title(for context: WKWebExtensionContext) -> String? {
        projection.title(for: context)
    }
    func isSelected(for context: WKWebExtensionContext) -> Bool {
        projection.isSelected(for: context)
    }
    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        projection.indexInWindow(for: context)
    }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        projection.isLoadingComplete(for: context)
    }
    func isPinned(for context: WKWebExtensionContext) -> Bool {
        projection.isPinned(for: context)
    }
    func isMuted(for context: WKWebExtensionContext) -> Bool {
        projection.isMuted(for: context)
    }
    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        projection.isPlayingAudio(for: context)
    }
    func isReaderModeActive(for _: WKWebExtensionContext) -> Bool { false }
    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        projection.webView(for: context)
    }
    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        projection.zoomFactor(for: context)
    }
    func size(for context: WKWebExtensionContext) -> CGSize {
        projection.size(for: context)
    }
    func shouldGrantPermissionsOnUserGesture(
        for context: WKWebExtensionContext
    ) -> Bool {
        evidence.currentPublication(visibleTo: context) != nil
    }
    func shouldBypassPermissions(for _: WKWebExtensionContext) -> Bool { false }
    func window(
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        projection.window(for: context)
    }

    func activate(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.activate(for: context, completion: completionHandler)
    }
    func close(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.close(for: context, completion: completionHandler)
    }
    func reload(
        fromOrigin: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.reload(
            fromOrigin: fromOrigin,
            for: context,
            completion: completionHandler
        )
    }
    func loadURL(
        _ url: URL,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.loadURL(url, for: context, completion: completionHandler)
    }
    func setMuted(
        _ muted: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.setMuted(muted, for: context, completion: completionHandler)
    }
    func setZoomFactor(
        _ zoomFactor: Double,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        commands.setZoomFactor(
            zoomFactor,
            for: context,
            completion: completionHandler
        )
    }

    func detectWebpageLocale(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Locale?, Error?) -> Void
    ) {
        commands.detectWebpageLocale(
            for: context,
            completion: completionHandler
        )
    }
}
