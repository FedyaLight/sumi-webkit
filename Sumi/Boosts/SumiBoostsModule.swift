import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class SumiBoostsModule: ObservableObject {
    struct LivePage {
        let tab: Tab
        let webView: WKWebView
    }

    struct Runtime {
        let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
        let matchingLivePages: @MainActor (UUID, String) -> [LivePage]
        let allLivePages: @MainActor () -> [LivePage]
        let applyBoostAwareZoom: @MainActor (Tab, WKWebView) -> Void
        let openWebInspector: @MainActor (Tab, BrowserWindowState) -> Void
        let sidebarPosition: @MainActor () -> SidebarPosition
        let settings: @MainActor () -> SumiSettingsService?
        let windowRegistry: @MainActor () -> WindowRegistry?

        static let empty = Runtime(
            windowOwnedWebView: { _, _ in nil },
            matchingLivePages: { _, _ in [] },
            allLivePages: { [] },
            applyBoostAwareZoom: { _, _ in /* No-op. */ },
            openWebInspector: { _, _ in /* No-op. */ },
            sidebarPosition: { .left },
            settings: { nil },
            windowRegistry: { nil }
        )
    }

    /// Selects how aggressively a boost mutation is propagated to live pages.
    enum RefreshPath {
        /// Idempotent `<style>` upsert + zoom reapply via `evaluateJavaScript`.
        /// Use for any edit that changes the boost's contents.
        case liveState
        /// Just reapply the boost-derived page zoom. Use when only `sizeOverride`
        /// changed, so the CSS payload is not re-shipped to the page.
        case zoomOnly
    }

    private let moduleRegistry: SumiModuleRegistry
    private let storeFactory: @MainActor () -> SumiBoostStore
    private var runtime: Runtime = .empty
    private var runtimeProvider: (@MainActor () -> Runtime)?
    private(set) var hasAttachedRuntime = false

    private var loadedStore: SumiBoostStore?
    private var storeChangesCancellable: AnyCancellable?
    private let changesSubject = PassthroughSubject<Void, Never>()

    private var editorPresenter: SumiBoostEditorPanelController?
    private var activeZapSession: SumiElementZapperSession?

    init(
        moduleRegistry: SumiModuleRegistry,
        storeFactory: @escaping @MainActor () -> SumiBoostStore
    ) {
        self.moduleRegistry = moduleRegistry
        self.storeFactory = storeFactory
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.boosts)
    }

    var hasLoadedRuntime: Bool {
        loadedStore != nil || editorPresenter != nil || activeZapSession != nil
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    /// Stores a factory used when the module is enabled after BrowserManager wiring.
    func bindRuntimeProvider(_ provider: @escaping @MainActor () -> Runtime) {
        runtimeProvider = provider
    }

    func attach(runtime: Runtime) {
        self.runtime = runtime
        hasAttachedRuntime = true
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled = self.isEnabled
        guard wasEnabled != isEnabled else { return }

        if isEnabled == false {
            closeLoadedEditorBeforeDisable()
        }

        moduleRegistry.setEnabled(isEnabled, for: .boosts)

        if isEnabled == false {
            removeBoostsFromLivePages()
            releaseLoadedRuntime()
            clearAttachedRuntime()
        } else {
            attachRuntimeFromProviderIfNeeded()
        }

        changesSubject.send(())
    }

    private func attachRuntimeFromProviderIfNeeded() {
        guard hasAttachedRuntime == false, let runtimeProvider else { return }
        attach(runtime: runtimeProvider())
    }

    private func clearAttachedRuntime() {
        runtime = .empty
        hasAttachedRuntime = false
    }

    func canBoost(url: URL?) -> Bool {
        guard isEnabled else { return false }
        return SumiBoostURLPolicy.normalizedBoostableHost(for: url) != nil
    }

    func changedBoosts(for url: URL?, profileId: UUID?) -> [SumiBoost] {
        storeIfEnabled()?.changedBoosts(for: url, profileId: profileId) ?? []
    }

    func activeBoost(for url: URL?, profileId: UUID?) -> SumiBoost? {
        storeIfEnabled()?.activeBoost(for: url, profileId: profileId)
    }

    func activeBoostId(for url: URL?, profileId: UUID?) -> UUID? {
        storeIfEnabled()?.activeBoostId(for: url, profileId: profileId)
    }

    func sizeOverride(for url: URL?, profileId: UUID?) -> Double {
        activeBoost(for: url, profileId: profileId)?.data.sizeOverride ?? 1
    }

    func normalTabUserScripts(
        for url: URL,
        profileId: UUID?,
        isEphemeral: Bool
    ) -> [SumiPageScript] {
        _ = isEphemeral
        guard let boost = activeBoost(for: url, profileId: profileId) else { return [] }
        return [SumiBoostUserScript(boost: boost)]
    }

    @discardableResult
    func createBoost(
        tab: Tab,
        profile: Profile?
    ) throws -> SumiBoost {
        guard let store = storeIfEnabled() else {
            throw SumiBoostStoreError.moduleDisabled
        }

        let profile = profile ?? tab.resolveProfile()
        let boost = try store.createDraft(
            for: tab.url,
            profileId: profile?.id,
            isEphemeral: profile?.isEphemeral == true
        )
        // A new active draft may need to take effect on the next navigation,
        // so reinstall the managed user-script set on matching tabs.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
        return boost
    }

    @discardableResult
    func createBoostAndOpenEditor(
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState
    ) throws -> SumiBoost {
        let resolvedProfile = profile ?? tab.resolveProfile()
        let boost = try createBoost(tab: tab, profile: resolvedProfile)
        presentEditor(
            boost: boost,
            tab: tab,
            profile: resolvedProfile,
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
        guard let editorPresenter = loadEditorPresenterIfEnabled() else { return }

        editorPresenter.present(
            boost: boost,
            tab: tab,
            profile: profile ?? tab.resolveProfile(),
            windowState: windowState,
            sidebarPosition: runtime.sidebarPosition(),
            module: self,
            settings: runtime.settings(),
            windowRegistry: runtime.windowRegistry()
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
        guard let store = storeIfEnabled() else { return nil }

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
            // atDocumentStart WKUserScript does not re-run on the current
            // document, so rebuilding/reinstalling the managed-script set
            // would be wasted work. The evaluateJavaScript upsert below is
            // what actually refreshes the visible page. The WKUserScript is
            // re-synced lazily when the editor closes.
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
        guard let store = storeIfEnabled() else { return }

        store.toggleActiveBoost(boost, isEphemeral: isEphemeral)
        // The active boost set changed, so the WKUserScript that runs on the
        // next navigation must be reinstalled for every matching tab.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
    }

    func deleteBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        guard let store = storeIfEnabled() else { return }

        store.deleteBoost(boost, isEphemeral: isEphemeral)
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
    }

    func discardUnchangedDraft(_ boost: SumiBoost) {
        guard let store = storeIfEnabled() else { return }

        store.discardUnchangedDraft(boost)
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
    }

    func deleteProfileData(profileID: UUID) throws {
        try loadStore().deleteProfileData(profileID: profileID)
    }

    @discardableResult
    func importBoost(
        from data: Data,
        tab: Tab,
        profile: Profile?
    ) throws -> SumiBoost {
        guard let store = storeIfEnabled() else {
            throw SumiBoostStoreError.moduleDisabled
        }

        let resolvedProfile = profile ?? tab.resolveProfile()
        let boost = try store.importBoost(
            from: data,
            for: tab.url,
            profileId: resolvedProfile?.id,
            isEphemeral: resolvedProfile?.isEphemeral == true
        )
        // Import replaces/activates a boost, changing the active set.
        reinstallUserScripts(profileId: boost.profileId, host: boost.host)
        return boost
    }

    func exportData(for boost: SumiBoost) throws -> Data {
        guard let store = storeIfEnabled() else {
            throw SumiBoostStoreError.moduleDisabled
        }

        return try store.exportData(for: boost)
    }

    @discardableResult
    func startZapSelection(
        for boost: SumiBoost,
        tab: Tab,
        windowState: BrowserWindowState,
        isEphemeral: Bool,
        onSelector: @escaping @MainActor (SumiBoost) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) async -> Bool {
        guard isEnabled else { return false }
        guard let webView = runtime.windowOwnedWebView(tab, windowState.id) else {
            return false
        }

        focusWebViewForElementPicking(webView)
        activeZapSession?.stop()
        let session = SumiElementZapperSession(
            webView: webView,
            configuration: .boost,
            onSelected: { [weak self] selector in
                guard let self else { return }
                guard let updated = self.updateBoost(
                    boost,
                    isEphemeral: isEphemeral,
                    markChanged: true,
                    mutate: { data in
                        if !data.zapSelectors.contains(selector) {
                            data.zapSelectors.append(selector)
                        }
                    }
                ) else { return }
                onSelector(updated)
            },
            onFinish: { [weak self] in
                self?.activeZapSession = nil
                onFinish()
            }
        )
        activeZapSession = session
        let didStart = await session.start()
        if !didStart {
            activeZapSession = nil
        }
        return didStart
    }

    func stopZapSelection() {
        activeZapSession?.stop()
        activeZapSession = nil
    }

    /// Cheap live update for the current document: idempotent `<style>`
    /// upsert via `evaluateJavaScript` + zoom reapply. Called on every content
    /// edit (dot drag, sliders, font, case, custom CSS, zap selectors). Does
    /// not touch the WKUserScript set because `atDocumentStart` scripts do not
    /// re-run on the current document.
    func refreshLiveBoostState(profileId: UUID, host: String) {
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
            profileId: profileId,
            host: normalizedHost
        ) { tab, webView in
            self.applyLiveBoostState(to: webView, tab: tab)
        }
    }

    /// Refreshes only the boost-derived page zoom multiplier. Cheaper than
    /// `refreshLiveBoostState` because it skips CSS injection entirely.
    func refreshBoostZoom(profileId: UUID, host: String) {
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
            profileId: profileId,
            host: normalizedHost
        ) { tab, webView in
            self.runtime.applyBoostAwareZoom(tab, webView)
        }
    }

    /// Rebuilds the managed page-script set (browser-owned + extension + boost)
    /// and reinstalls every WKUserScript on each matching tab's content
    /// controller. Required when the active boost set changes.
    func reinstallUserScripts(profileId: UUID, host: String) {
        let normalizedHost = host.lowercased()
        forEachMatchingWebView(
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
        loadedStore?.flushPendingWrites()
        reinstallUserScripts(profileId: profileId, host: host)
    }

    func openInspector(tab: Tab, windowState: BrowserWindowState) {
        runtime.openWebInspector(tab, windowState)
    }

    private func forEachMatchingWebView(
        profileId: UUID,
        host: String,
        body: (Tab, WKWebView) -> Void
    ) {
        for page in runtime.matchingLivePages(profileId, host) {
            body(page.tab, page.webView)
        }
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
        runtime.applyBoostAwareZoom(tab, webView)
    }

    private func storeIfEnabled() -> SumiBoostStore? {
        guard isEnabled else { return nil }
        return loadStore()
    }

    private func loadStore() -> SumiBoostStore {
        if let loadedStore {
            return loadedStore
        }

        let store = storeFactory()
        loadedStore = store
        storeChangesCancellable = store.changesPublisher.sink { [weak self] in
            self?.changesSubject.send(())
        }
        return store
    }

    private func loadEditorPresenterIfEnabled() -> SumiBoostEditorPanelController? {
        guard isEnabled else { return nil }
        if let editorPresenter {
            return editorPresenter
        }

        let presenter = SumiBoostEditorPanelController()
        editorPresenter = presenter
        return presenter
    }

    private func focusWebViewForElementPicking(_ webView: WKWebView) {
        guard let window = webView.window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
    }

    private func closeLoadedEditorBeforeDisable() {
        stopZapSelection()
        editorPresenter?.close()
        loadedStore?.flushPendingWrites()
    }

    private func removeBoostsFromLivePages() {
        for page in runtime.allLivePages() {
            let tab = page.tab
            let webView = page.webView
            Task { @MainActor [weak tab, weak webView] in
                guard let tab, let webView else { return }
                await tab.replaceNormalTabUserScripts(
                    on: webView.configuration.userContentController,
                    for: tab.url
                )
                do {
                    _ = try await webView.evaluateJavaScript(
                        SumiBoostCSSBuilder.removalJavaScript()
                    )
                } catch {
                    RuntimeDiagnostics.debug(category: "Boosts") {
                        "Failed to remove Boost CSS from live page: \(error.localizedDescription)"
                    }
                }
                self.runtime.applyBoostAwareZoom(tab, webView)
            }
        }
    }

    private func releaseLoadedRuntime() {
        stopZapSelection()
        storeChangesCancellable?.cancel()
        storeChangesCancellable = nil
        loadedStore = nil
        editorPresenter = nil
    }
}
