import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class SumiBoostsModule: ObservableObject {
    let store: SumiBoostStore
    weak var browserManager: BrowserManager?

    private let editorPresenter = SumiBoostEditorPanelController()
    private var activeZapSession: SumiBoostZapSession?

    init(store: SumiBoostStore = .shared) {
        self.store = store
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func canBoost(url: URL?) -> Bool {
        store.canBoost(url: url)
    }

    func changedBoosts(for url: URL?, profileId: UUID?) -> [SumiBoost] {
        store.changedBoosts(for: url, profileId: profileId)
    }

    func activeBoost(for url: URL?, profileId: UUID?) -> SumiBoost? {
        store.activeBoost(for: url, profileId: profileId)
    }

    func activeBoostId(for url: URL?, profileId: UUID?) -> UUID? {
        store.activeBoostId(for: url, profileId: profileId)
    }

    func sizeOverride(for url: URL?, profileId: UUID?) -> Double {
        activeBoost(for: url, profileId: profileId)?.data.sizeOverride ?? 1
    }

    func normalTabUserScripts(
        for url: URL,
        profileId: UUID?,
        isEphemeral: Bool
    ) -> [SumiUserScript] {
        _ = isEphemeral
        guard let boost = activeBoost(for: url, profileId: profileId) else { return [] }
        return [SumiBoostUserScript(boost: boost)]
    }

    @discardableResult
    func createBoostAndOpenEditor(
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState
    ) throws -> SumiBoost {
        let profile = profile ?? tab.resolveProfile()
        let boost = try store.createDraft(
            for: tab.url,
            profileId: profile?.id,
            isEphemeral: profile?.isEphemeral == true
        )
        refreshTabs(profileId: boost.profileId, host: boost.host)
        presentEditor(
            boost: boost,
            tab: tab,
            profile: profile,
            windowState: windowState
        )
        return boost
    }

    func presentEditor(
        boost: SumiBoost,
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState
    ) {
        editorPresenter.present(
            boost: boost,
            tab: tab,
            profile: profile ?? tab.resolveProfile(),
            windowState: windowState,
            module: self
        )
    }

    @discardableResult
    func updateBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool,
        markChanged: Bool = true,
        mutate: (inout SumiBoostData) -> Void
    ) -> SumiBoost? {
        do {
            let updated = try store.updateBoost(
                id: boost.id,
                profileId: boost.profileId,
                host: boost.host,
                isEphemeral: isEphemeral,
                markChanged: markChanged,
                mutate: mutate
            )
            refreshTabs(profileId: updated.profileId, host: updated.host)
            return updated
        } catch {
            RuntimeDiagnostics.debug(
                "Boost update failed: \(error.localizedDescription)",
                category: "Boosts"
            )
            return nil
        }
    }

    func toggleActiveBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        store.toggleActiveBoost(boost, isEphemeral: isEphemeral)
        refreshTabs(profileId: boost.profileId, host: boost.host)
    }

    func deleteBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        store.deleteBoost(boost, isEphemeral: isEphemeral)
        refreshTabs(profileId: boost.profileId, host: boost.host)
    }

    func discardUnchangedDraft(_ boost: SumiBoost) {
        store.discardUnchangedDraft(boost)
        refreshTabs(profileId: boost.profileId, host: boost.host)
    }

    @discardableResult
    func importBoost(
        from data: Data,
        tab: Tab,
        profile: Profile?
    ) throws -> SumiBoost {
        let resolvedProfile = profile ?? tab.resolveProfile()
        let boost = try store.importBoost(
            from: data,
            for: tab.url,
            profileId: resolvedProfile?.id,
            isEphemeral: resolvedProfile?.isEphemeral == true
        )
        refreshTabs(profileId: boost.profileId, host: boost.host)
        return boost
    }

    func exportData(for boost: SumiBoost) throws -> Data {
        try store.exportData(for: boost)
    }

    @discardableResult
    func startZapSelection(
        for boost: SumiBoost,
        tab: Tab,
        windowState: BrowserWindowState,
        isEphemeral: Bool,
        onSelector: @escaping @MainActor (SumiBoost) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let webView = browserManager?.getWebView(for: tab.id, in: windowState.id)
            ?? tab.existingWebView
        else { return false }

        activeZapSession?.stop()
        activeZapSession = SumiBoostZapSession(
            boost: boost,
            webView: webView,
            isEphemeral: isEphemeral,
            module: self,
            onSelector: onSelector,
            onFinish: onFinish
        )
        activeZapSession?.start()
        return true
    }

    func stopZapSelection() {
        activeZapSession?.stop()
        activeZapSession = nil
    }

    func previewZapSelector(_ selector: String, isHighlighted: Bool, tab: Tab, windowState: BrowserWindowState) {
        guard let webView = browserManager?.getWebView(for: tab.id, in: windowState.id)
            ?? tab.existingWebView
        else { return }
        let script = SumiBoostZapSession.previewJavaScript(selector: selector, isHighlighted: isHighlighted)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func refreshTabs(profileId: UUID, host: String) {
        guard let browserManager else { return }
        let normalizedHost = host.lowercased()
        var appliedWebViews = Set<ObjectIdentifier>()

        func apply(to tab: Tab, webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard appliedWebViews.insert(identifier).inserted else { return }
            Task { @MainActor [weak tab, weak webView] in
                guard let tab, let webView else { return }
                await tab.replaceNormalTabUserScripts(
                    on: webView.configuration.userContentController,
                    for: tab.url
                )
                self.applyLiveBoostState(to: webView, tab: tab)
            }
        }

        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            for tab in browserManager.tabsForDisplay(in: windowState)
                where tabMatches(tab, profileId: profileId, host: normalizedHost) {
                if let webView = browserManager.getWebView(for: tab.id, in: windowState.id)
                    ?? tab.existingWebView {
                    apply(to: tab, webView: webView)
                }
            }
        }

        for tab in browserManager.tabManager.allTabs()
            where tabMatches(tab, profileId: profileId, host: normalizedHost) {
            if let webView = tab.existingWebView {
                apply(to: tab, webView: webView)
            }
        }
    }

    private func tabMatches(_ tab: Tab, profileId: UUID, host: String) -> Bool {
        guard (tab.resolveProfile()?.id ?? tab.profileId) == profileId,
              SumiBoostURLPolicy.normalizedBoostableHost(for: tab.url) == host
        else {
            return false
        }
        return true
    }

    private func applyLiveBoostState(to webView: WKWebView, tab: Tab) {
        let profileId = tab.resolveProfile()?.id ?? tab.profileId
        if let boost = activeBoost(for: tab.url, profileId: profileId) {
            webView.evaluateJavaScript(
                SumiBoostCSSBuilder.installJavaScript(for: boost),
                completionHandler: nil
            )
        } else {
            webView.evaluateJavaScript(
                SumiBoostCSSBuilder.removalJavaScript(),
                completionHandler: nil
            )
        }
        browserManager?.applyBoostAwareZoom(for: tab, webView: webView)
    }
}
