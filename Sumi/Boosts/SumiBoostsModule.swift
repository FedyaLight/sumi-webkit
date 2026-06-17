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

    /// Selects how aggressively a boost mutation is propagated to live pages.
    enum RefreshPath {
        /// Idempotent `<style>` upsert + zoom reapply via `evaluateJavaScript`.
        /// Use for any edit that changes the boost's *contents*.
        case liveState
        /// Just reapply the boost-derived page zoom. Use when only `sizeOverride`
        /// changed, so the CSS payload isn't re-shipped to the page.
        case zoomOnly
    }

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
        // A new active draft may need to take effect on the next navigation,
        // so reinstall the managed user-script set on matching tabs.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
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
        refreshPath: RefreshPath = .liveState,
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
            // Content edits only need a live page update: the existing
            // atDocumentStart WKUserScript does NOT re-run on the current
            // document, so rebuilding/reinstalling the managed-script set
            // would be wasted work. The evaluateJavaScript upsert below is
            // what actually refreshes the visible page. The WKUserScript is
            // re-synced lazily when the editor closes (reinstallUserScripts).
            switch refreshPath {
            case .liveState:
                refreshLiveBoostState(profileId: updated.profileId, host: updated.host)
            case .zoomOnly:
                refreshBoostZoom(profileId: updated.profileId, host: updated.host)
            }
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
        // The *active* boost set changed, so the WKUserScript that runs on
        // the next navigation must be reinstalled for every matching tab.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
    }

    func deleteBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        store.deleteBoost(boost, isEphemeral: isEphemeral)
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
    }

    func discardUnchangedDraft(_ boost: SumiBoost) {
        store.discardUnchangedDraft(boost)
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
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
        // Import replaces/activates a boost, changing the active set → reinstall.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
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

    /// Cheap live update for the current document: idempotent `<style>`
    /// upsert via `evaluateJavaScript` + zoom reapply. Called on every content
    /// edit (dot drag, sliders, font, case, custom CSS, zap selectors). Does
    /// NOT touch the WKUserScript set — `atDocumentStart` scripts don't re-run
    /// on the current document anyway, so rebuilding them would be wasted work.
    func refreshLiveBoostState(profileId: UUID, host: String) {
        guard let browserManager else { return }
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
            browserManager: browserManager,
            profileId: profileId,
            host: normalizedHost
        ) { tab, webView in
            self.applyLiveBoostState(to: webView, tab: tab)
        }
    }

    /// Refreshes only the boost-derived page zoom (the `sizeOverride`
    /// multiplier). Cheaper than `refreshLiveBoostState` because it skips the
    /// CSS injection entirely — use when only the size changed.
    func refreshBoostZoom(profileId: UUID, host: String) {
        guard let browserManager else { return }
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
            browserManager: browserManager,
            profileId: profileId,
            host: normalizedHost
        ) { tab, webView in
            self.browserManager?.applyBoostAwareZoom(for: tab, webView: webView)
        }
    }

    /// Expensive: rebuilds the managed user-script set (extensions +
    /// userscripts + boost) and reinstalls every WKUserScript on each matching
    /// tab's content controller. Required only when the *active boost set*
    /// changes — so the `atDocumentStart` boost script matches reality on the
    /// next navigation. Editor callers should invoke
    /// `reinstallUserScriptsAfterEdit` on close so the edited boost takes
    /// effect on future page loads.
    func reinstallUserScripts(profileId: UUID, host: String) {
        guard let browserManager else { return }
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
            browserManager: browserManager,
            profileId: profileId,
            host: normalizedHost
        ) { tab, webView in
            Task { @MainActor [weak tab, weak webView] in
                guard let tab, let webView else { return }
                await tab.replaceNormalTabUserScripts(
                    on: webView.configuration.userContentController,
                    for: tab.url
                )
                self.applyLiveBoostState(to: webView, tab: tab)
            }
        }
    }

    /// Called by the editor when it closes: re-syncs the WKUserScript set so
    /// the final boost state is applied on the next navigation, and flushes
    /// any debounced disk writes so the edit is durable immediately.
    func reinstallUserScriptsAfterEdit(profileId: UUID, host: String) {
        store.flushPendingWrites()
        reinstallUserScripts(profileId: profileId, host: host)
    }

    private func forEachMatchingWebView(
        browserManager: BrowserManager,
        profileId: UUID,
        host: String,
        body: @escaping @MainActor (Tab, WKWebView) -> Void
    ) {
        // De-dupe by WebView identity so a tab surfaced through both the
        // window registry and the tab manager is only visited once.
        var visited = Set<ObjectIdentifier>()

        func visit(_ tab: Tab, _ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard visited.insert(identifier).inserted else { return }
            Task { @MainActor [weak tab, weak webView] in
                guard let tab, let webView else { return }
                body(tab, webView)
            }
        }

        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            for tab in browserManager.tabsForDisplay(in: windowState)
                where tabMatches(tab, profileId: profileId, host: host) {
                if let webView = browserManager.getWebView(for: tab.id, in: windowState.id)
                    ?? tab.existingWebView {
                    visit(tab, webView)
                }
            }
        }

        for tab in browserManager.tabManager.allTabs()
            where tabMatches(tab, profileId: profileId, host: host) {
            if let webView = tab.existingWebView {
                visit(tab, webView)
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
