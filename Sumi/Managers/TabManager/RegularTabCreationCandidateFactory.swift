import Foundation
import SumiDomain
import WebKit

/// Constructs regular-tab candidates from one resolved creation placement.
/// It owns URL fallback and model defaults, but never publishes residence.
@MainActor
final class RegularTabCreationCandidateFactory {
    private let runtimeConnection: TabRuntimePortConnection
    private let tabFactory: TabFactory
    private let regularTabs: RegularTabCollectionOwner

    init(
        runtimeConnection: TabRuntimePortConnection,
        tabFactory: TabFactory,
        regularTabs: RegularTabCollectionOwner
    ) {
        self.runtimeConnection = runtimeConnection
        self.tabFactory = tabFactory
        self.regularTabs = regularTabs
    }

    func makeTab(
        url: String,
        placement: TabCreationPlacement,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let template = runtimeConnection.current?.settings?
            .resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedURL = normalizeURL(url, queryTemplate: template)
        let validURL: URL
        if let resolvedURL = URL(string: normalizedURL) {
            validURL = resolvedURL
        } else {
            RuntimeDiagnostics.debug(
                "Invalid URL '\(url)' while creating a new tab; falling back to Sumi empty surface.",
                category: "TabManager"
            )
            validURL = SumiSurface.emptyTabURL
        }
        let nextIndex = regularInsertionIndex
            ?? regularTabs.appendIndex(in: placement.space.id)
        let tab = tabFactory.makeTab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: placement.space.id,
            index: nextIndex
        )
        applyPlacementProfile(
            placement,
            executionProfileID: executionProfileID,
            to: tab
        )
        tab.webExtensionContextOverride = webExtensionContextOverride
        if let webViewConfigurationOverride {
            tab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
        }
        return tab
    }

    func makePopup(
        placement: TabCreationPlacement,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?,
        webViewConfigurationOverride: WKWebViewConfiguration?
    ) -> Tab {
        guard let blankURL = URL(string: "about:blank") else {
            preconditionFailure("TabManager: invalid about:blank URL")
        }
        let resolvedIndex = regularInsertionIndex.map {
            regularTabs.clampedInsertionIndex($0, in: placement.space.id)
        } ?? regularTabs.appendIndex(in: placement.space.id)
        let tab = tabFactory.makeTab(
            url: blankURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: placement.space.id,
            index: resolvedIndex
        )
        applyPlacementProfile(
            placement,
            executionProfileID: executionProfileID,
            to: tab
        )
        tab.isPopupHost = true
        if let webViewConfigurationOverride {
            tab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
        }
        return tab
    }

    func makeFallbackTab() -> Tab {
        tabFactory.makeTab(
            url: SumiSurface.emptyTabURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0
        )
    }

    private func applyPlacementProfile(
        _ placement: TabCreationPlacement,
        executionProfileID: UUID?,
        to tab: Tab
    ) {
        tab.profileId = executionProfileID
            ?? placement.temporaryProfileOverrideId
    }
}
